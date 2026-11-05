import Foundation

/// Modificaciones y consultas para clientes (bloque K2c).
///
/// Reglas:
/// - Nombre obligatorio y único entre clientes activos (DUPLICATE_NAME, sin distinguir mayúsculas ni espacios de los lados).
/// - Renombrar o cambiar teléfono actualiza `customerName`/`customerPhone` (y su `updatedAt`) en los pedidos activos ligados.
/// - Borrar marca `deletedAt` y deja `customerId = nil` en sus pedidos activos sin tocar su nombre ni teléfono.

public struct CustomerUpdateDraft: Sendable {
    public var name: String?
    public var phone: String??
    public var notes: String??

    public init(name: String? = nil, phone: String?? = nil, notes: String?? = nil) {
        self.name = name
        self.phone = phone
        self.notes = notes
    }
}

extension KitchenData {
    // MARK: - Lecturas

    /// Clientes activos, opcionalmente filtrados por búsqueda de texto (nombre o teléfono),
    /// ordenados alfabéticamente por nombre.
    public func listCustomers(query: String? = nil) -> [Customer] {
        var result = customers.filter { $0.isActive }

        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !q.isEmpty {
            result = result.filter { customer in
                if customer.name.lowercased().contains(q) {
                    return true
                }
                if let phone = customer.phone?.lowercased(), phone.contains(q) {
                    return true
                }
                return false
            }
        }

        return result.sorted { a, b in
            let cmp = a.name.localizedStandardCompare(b.name)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return a.id < b.id
        }
    }

    /// Obtiene un cliente activo por id o lanza DomainError.notFound.
    public func customer(id: String) throws -> Customer {
        guard let cust = customers.active(id) else {
            throw DomainError.notFound(detail: "Cliente no encontrado")
        }
        return cust
    }

    // MARK: - Escrituras

    /// Crea un cliente activo.
    @discardableResult
    public mutating func createCustomer(
        name: String,
        phone: String? = nil,
        notes: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Customer {
        var clone = self

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainError.invalidValue(detail: "El nombre es obligatorio")
        }

        let normalized = trimmedName.normalizedName
        if clone.customers.contains(where: { $0.isActive && $0.name.normalizedName == normalized }) {
            throw DomainError.duplicateName(detail: "Ya existe un cliente con ese nombre")
        }

        let cleanPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPhone = (cleanPhone?.isEmpty == false) ? cleanPhone : nil

        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = (cleanNotes?.isEmpty == false) ? cleanNotes : nil

        let customer = Customer(
            id: ctx.newId(),
            name: trimmedName,
            phone: finalPhone,
            notes: finalNotes,
            createdAt: ctx.now,
            updatedAt: ctx.now,
            deletedAt: nil
        )

        clone.customers.append(customer)
        self = clone
        return customer
    }

    /// Edita un cliente activo y propaga cambios de nombre/teléfono a los pedidos activos asociados.
    @discardableResult
    public mutating func updateCustomer(
        id: String,
        draft: CustomerUpdateDraft,
        ctx: MutationContext = MutationContext()
    ) throws -> Customer {
        var clone = self

        guard let idx = clone.customers.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Cliente no encontrado")
        }

        var customer = clone.customers[idx]
        var nameChanged = false
        var phoneChanged = false

        if let newName = draft.name {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidValue(detail: "El nombre es obligatorio")
            }
            let normalized = trimmed.normalizedName
            let existsOther = clone.customers.contains { other in
                other.isActive && other.id != id && other.name.normalizedName == normalized
            }
            if existsOther {
                throw DomainError.duplicateName(detail: "Ya existe un cliente con ese nombre")
            }
            if customer.name != trimmed {
                customer.name = trimmed
                nameChanged = true
            }
        }

        if let phoneWrapped = draft.phone {
            let clean = phoneWrapped?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalPhone = (clean?.isEmpty == false) ? clean : nil
            if customer.phone != finalPhone {
                customer.phone = finalPhone
                phoneChanged = true
            }
        }

        if let notesWrapped = draft.notes {
            let clean = notesWrapped?.trimmingCharacters(in: .whitespacesAndNewlines)
            customer.notes = (clean?.isEmpty == false) ? clean : nil
        }

        customer.updatedAt = ctx.now
        clone.customers[idx] = customer

        if nameChanged || phoneChanged {
            for i in clone.orders.indices {
                if clone.orders[i].isActive && clone.orders[i].customerId == customer.id {
                    clone.orders[i].customerName = customer.name
                    clone.orders[i].customerPhone = customer.phone
                    clone.orders[i].updatedAt = ctx.now
                }
            }
        }

        self = clone
        return customer
    }

    /// Sobrecarga conveniente para editar un cliente sin armar el struct de draft.
    @discardableResult
    public mutating func updateCustomer(
        id: String,
        name: String? = nil,
        phone: String?? = nil,
        notes: String?? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Customer {
        try updateCustomer(
            id: id,
            draft: CustomerUpdateDraft(name: name, phone: phone, notes: notes),
            ctx: ctx
        )
    }

    /// Borra un cliente en modo soft delete y desliga sus pedidos activos dejando `customerId = nil`.
    public mutating func deleteCustomer(
        id: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var clone = self

        guard let idx = clone.customers.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Cliente no encontrado")
        }

        clone.customers[idx].deletedAt = ctx.now
        clone.customers[idx].updatedAt = ctx.now

        for i in clone.orders.indices {
            if clone.orders[i].isActive && clone.orders[i].customerId == id {
                clone.orders[i].customerId = nil
                clone.orders[i].updatedAt = ctx.now
            }
        }

        self = clone
    }
}
