import Foundation

/// Modificaciones y consultas para gastos (bloque K2c).
///
/// Comportamiento idéntico al backend (`backend/app/services/expense_service.py`):
/// - Validación de descripción obligatoria y monto > 0.
/// - Validación de proveedor activo si se especifica (`INVALID_REFERENCE`).
/// - Listado con filtros (rango de fechas en spentAt y categoría), ordenados por spentAt descendente.
/// - Borrado en modo soft delete.

public struct ExpenseUpdateDraft: Sendable {
    public var description: String?
    public var amountCents: Int?
    public var spentAt: Date?
    public var category: String??
    public var supplierId: String??

    public init(
        description: String? = nil,
        amountCents: Int? = nil,
        spentAt: Date? = nil,
        category: String?? = nil,
        supplierId: String?? = nil
    ) {
        self.description = description
        self.amountCents = amountCents
        self.spentAt = spentAt
        self.category = category
        self.supplierId = supplierId
    }
}

public struct ExpensePage: Sendable {
    public var items: [Expense]
    public var total: Int
    public var page: Int
    public var pages: Int

    public init(items: [Expense], total: Int, page: Int, pages: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.pages = pages
    }
}

extension KitchenData {
    // MARK: - Lecturas

    /// Obtiene un gasto activo por id.
    public func expense(id: String) throws -> Expense {
        guard let exp = expenses.active(id) else {
            throw DomainError.notFound(detail: "Gasto no encontrado")
        }
        return exp
    }

    /// Lista gastos activos aplicando filtros opcionales de fechas y categoría, ordenados por `spentAt` descendente.
    public func listExpenses(
        from: Date? = nil,
        to: Date? = nil,
        category: String? = nil
    ) -> [Expense] {
        var result = expenses.filter { $0.isActive }

        if let cat = category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
            result = result.filter { $0.category == cat }
        }
        if let from = from {
            result = result.filter { $0.spentAt >= from }
        }
        if let to = to {
            result = result.filter { $0.spentAt <= to }
        }

        return result.sorted { a, b in
            if a.spentAt != b.spentAt {
                return a.spentAt > b.spentAt
            }
            if a.createdAt != b.createdAt {
                return a.createdAt > b.createdAt
            }
            return a.id > b.id
        }
    }

    /// Lista gastos paginados.
    public func listExpenses(
        page: Int = 1,
        limit: Int = 20,
        from: Date? = nil,
        to: Date? = nil,
        category: String? = nil
    ) -> ExpensePage {
        let all = listExpenses(from: from, to: to, category: category)
        let limitClamped = min(max(1, limit), 100)
        let pageClamped = max(1, page)
        let total = all.count
        let pages = total > 0 ? Int(ceil(Double(total) / Double(limitClamped))) : 0
        let skip = (pageClamped - 1) * limitClamped
        let items = Array(all.dropFirst(skip).prefix(limitClamped))

        return ExpensePage(items: items, total: total, page: pageClamped, pages: pages)
    }

    // MARK: - Escrituras

    /// Registra un gasto activo.
    @discardableResult
    public mutating func createExpense(
        description: String,
        amountCents: Int,
        spentAt: Date? = nil,
        category: String? = nil,
        supplierId: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Expense {
        var clone = self

        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDesc.isEmpty else {
            throw DomainError.invalidValue(detail: "La descripción es obligatoria")
        }

        guard amountCents > 0 else {
            throw DomainError.invalidValue(detail: "El monto debe ser mayor que cero")
        }

        if let sid = supplierId, !sid.isEmpty {
            guard clone.suppliers.active(sid) != nil else {
                throw DomainError.invalidReference(detail: "Proveedor no encontrado: \(sid)")
            }
        }

        let cleanCat = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCat = (cleanCat?.isEmpty == false) ? cleanCat : nil

        let expense = Expense(
            id: ctx.newId(),
            description: trimmedDesc,
            amountCents: amountCents,
            spentAt: spentAt ?? ctx.now,
            category: finalCat,
            supplierId: (supplierId?.isEmpty == false) ? supplierId : nil,
            createdAt: ctx.now,
            updatedAt: ctx.now,
            deletedAt: nil
        )

        clone.expenses.append(expense)
        self = clone
        return expense
    }

    /// Edita un gasto activo.
    @discardableResult
    public mutating func updateExpense(
        id: String,
        draft: ExpenseUpdateDraft,
        ctx: MutationContext = MutationContext()
    ) throws -> Expense {
        var clone = self

        guard let idx = clone.expenses.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Gasto no encontrado")
        }

        var expense = clone.expenses[idx]

        if let desc = draft.description {
            let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidValue(detail: "La descripción es obligatoria")
            }
            expense.description = trimmed
        }

        if let amt = draft.amountCents {
            guard amt > 0 else {
                throw DomainError.invalidValue(detail: "El monto debe ser mayor que cero")
            }
            expense.amountCents = amt
        }

        if let spentAt = draft.spentAt {
            expense.spentAt = spentAt
        }

        if let catWrapped = draft.category {
            let clean = catWrapped?.trimmingCharacters(in: .whitespacesAndNewlines)
            expense.category = (clean?.isEmpty == false) ? clean : nil
        }

        if let suppWrapped = draft.supplierId {
            if let sid = suppWrapped, !sid.isEmpty {
                guard clone.suppliers.active(sid) != nil else {
                    throw DomainError.invalidReference(detail: "Proveedor no encontrado: \(sid)")
                }
                expense.supplierId = sid
            } else {
                expense.supplierId = nil
            }
        }

        expense.updatedAt = ctx.now
        clone.expenses[idx] = expense
        self = clone
        return expense
    }

    /// Sobrecarga conveniente para editar un gasto con argumentos opcionales.
    @discardableResult
    public mutating func updateExpense(
        id: String,
        description: String? = nil,
        amountCents: Int? = nil,
        spentAt: Date? = nil,
        category: String?? = nil,
        supplierId: String?? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Expense {
        try updateExpense(
            id: id,
            draft: ExpenseUpdateDraft(
                description: description,
                amountCents: amountCents,
                spentAt: spentAt,
                category: category,
                supplierId: supplierId
            ),
            ctx: ctx
        )
    }

    /// Borra un gasto en modo soft delete.
    public mutating func deleteExpense(
        id: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var clone = self

        guard let idx = clone.expenses.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Gasto no encontrado")
        }

        clone.expenses[idx].deletedAt = ctx.now
        clone.expenses[idx].updatedAt = ctx.now
        self = clone
    }
}
