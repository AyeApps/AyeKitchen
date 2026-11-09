import Foundation

/// Reglas y operaciones de pedidos y pagos (bloque K2c).
///
/// Comportamiento idéntico al backend (`backend/app/services/order_service.py`):
/// - Validaciones: cliente requerido o existente, cantidad > 0, recetas activas, saldo suficiente para pagos.
/// - Por tanda (.batch) o por pieza (.unit): precios sugeridos por defecto, snapshots de costo por unidad, unitLabel y recipeName.
/// - Al editar pedidos, las líneas se preservan por (recipeId, soldBy): mantienen snapshot, unitLabel, recipeName y precio convenido.
/// - Totales calculados en Decimal con un solo redondeo al final por total, como `compute_order_totals`.
/// - Listados con filtros (estado, deliveryAt desde/hasta, cliente) ordenados por deliveryAt ascendente.

public struct OrderTotals: Sendable, Hashable {
    public var totalCents: Int
    public var paidCents: Int
    public var balanceCents: Int
    public var costCents: Int
    public var profitCents: Int

    public var profitPercent: Int? {
        guard costCents != 0 else { return nil }
        let unrounded = (Decimal(profitCents) / Decimal(costCents)) * Decimal(100)
        return CostingMath.roundToCents(unrounded)
    }

    public init(totalCents: Int, paidCents: Int, balanceCents: Int, costCents: Int, profitCents: Int) {
        self.totalCents = totalCents
        self.paidCents = paidCents
        self.balanceCents = balanceCents
        self.costCents = costCents
        self.profitCents = profitCents
    }
}

public struct OrderItemDraft: Sendable, Hashable {
    public var recipeId: String
    public var soldBy: OrderSoldBy
    public var quantity: String
    public var unitPriceCents: Int?

    public init(
        recipeId: String,
        soldBy: OrderSoldBy = .batch,
        quantity: String = "1",
        unitPriceCents: Int? = nil
    ) {
        self.recipeId = recipeId
        self.soldBy = soldBy
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
    }

    public init(_ item: OrderItem) {
        self.recipeId = item.recipeId
        self.soldBy = item.soldBy
        self.quantity = item.quantity
        self.unitPriceCents = item.unitPriceCents
    }
}

public struct OrderUpdateDraft: Sendable {
    public var customerId: String??
    public var customerName: String?
    public var customerPhone: String??
    public var deliveryAt: Date?
    public var status: OrderStatus?
    public var notes: String??
    public var items: [OrderItemDraft]?

    public init(
        customerId: String?? = nil,
        customerName: String? = nil,
        customerPhone: String?? = nil,
        deliveryAt: Date? = nil,
        status: OrderStatus? = nil,
        notes: String?? = nil,
        items: [OrderItemDraft]? = nil
    ) {
        self.customerId = customerId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.deliveryAt = deliveryAt
        self.status = status
        self.notes = notes
        self.items = items
    }
}

public struct OrderPage: Sendable {
    public var items: [Order]
    public var total: Int
    public var page: Int
    public var pages: Int

    public init(items: [Order], total: Int, page: Int, pages: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.pages = pages
    }
}

extension Order {
    /// Totales de este pedido calculados con precisión Decimal.
    public var totals: OrderTotals {
        KitchenData.computeOrderTotals(order: self)
    }
}

extension KitchenData {
    // MARK: - Totales

    /// Calcula total, pagado, saldo, costo y ganancia con precisión Decimal y un solo redondeo por total.
    public static func computeOrderTotals(order: Order) -> OrderTotals {
        var unroundedTotal = Decimal(0)
        var unroundedCost = Decimal(0)

        for item in order.items {
            let qty = Qty.decimal(item.quantity) ?? Decimal(0)
            unroundedTotal += qty * Decimal(item.unitPriceCents)
            unroundedCost += qty * Decimal(item.unitCostCentsSnapshot)
        }

        let unroundedProfit = unroundedTotal - unroundedCost

        let totalCents = CostingMath.roundToCents(unroundedTotal)
        let costCents = CostingMath.roundToCents(unroundedCost)
        let profitCents = CostingMath.roundToCents(unroundedProfit)
        let paidCents = order.payments.reduce(0) { $0 + $1.amountCents }
        let balanceCents = totalCents - paidCents

        return OrderTotals(
            totalCents: totalCents,
            paidCents: paidCents,
            balanceCents: balanceCents,
            costCents: costCents,
            profitCents: profitCents
        )
    }

    /// Conveniencia en la instancia de KitchenData.
    public func computeOrderTotals(order: Order) -> OrderTotals {
        KitchenData.computeOrderTotals(order: order)
    }

    // MARK: - Lecturas

    /// Obtiene un pedido activo por id.
    public func order(id: String) throws -> Order {
        guard let ord = orders.active(id) else {
            throw DomainError.notFound(detail: "Pedido no encontrado")
        }
        return ord
    }

    /// Lista pedidos activos aplicando filtros opcionales, ordenados por `deliveryAt` ascendente.
    public func listOrders(
        status: OrderStatus? = nil,
        from: Date? = nil,
        to: Date? = nil,
        customerId: String? = nil
    ) -> [Order] {
        var result = orders.filter { $0.isActive }

        if let status = status {
            result = result.filter { $0.status == status }
        }
        if let customerId = customerId {
            result = result.filter { $0.customerId == customerId }
        }
        if let from = from {
            result = result.filter { $0.deliveryAt >= from }
        }
        if let to = to {
            result = result.filter { $0.deliveryAt <= to }
        }

        return result.sorted { a, b in
            if a.deliveryAt != b.deliveryAt {
                return a.deliveryAt < b.deliveryAt
            }
            if a.createdAt != b.createdAt {
                return a.createdAt < b.createdAt
            }
            return a.id < b.id
        }
    }

    /// Lista pedidos paginados.
    public func listOrders(
        page: Int = 1,
        limit: Int = 20,
        status: OrderStatus? = nil,
        from: Date? = nil,
        to: Date? = nil,
        customerId: String? = nil
    ) -> OrderPage {
        let all = listOrders(status: status, from: from, to: to, customerId: customerId)
        let limitClamped = min(max(1, limit), 100)
        let pageClamped = max(1, page)
        let total = all.count
        let pages = total > 0 ? Int(ceil(Double(total) / Double(limitClamped))) : 0
        let skip = (pageClamped - 1) * limitClamped
        let items = Array(all.dropFirst(skip).prefix(limitClamped))

        return OrderPage(items: items, total: total, page: pageClamped, pages: pages)
    }

    // MARK: - Escrituras de Pedidos

    /// Crea un pedido con sus líneas, calculando precios por defecto y snapshots de costo.
    @discardableResult
    public mutating func createOrder(
        customerId: String? = nil,
        customerName: String? = nil,
        customerPhone: String? = nil,
        deliveryAt: Date,
        items: [OrderItemDraft],
        notes: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Order {
        var clone = self

        guard !items.isEmpty else {
            throw DomainError.invalidValue(detail: "El pedido debe tener al menos una línea")
        }

        // Validación de cantidades y recetas activas
        for it in items {
            guard let q = Qty.decimal(it.quantity), q > Decimal(0) else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }
            guard clone.recipes.active(it.recipeId) != nil else {
                throw DomainError.invalidReference(detail: "Receta no encontrada: \(it.recipeId)")
            }
        }

        // Resolución del cliente
        let resolvedCustomerId: String?
        let resolvedCustomerName: String
        let resolvedCustomerPhone: String?

        if let cid = customerId {
            guard let cust = clone.customers.active(cid) else {
                throw DomainError.invalidReference(detail: "Cliente no encontrado")
            }
            resolvedCustomerId = cust.id
            resolvedCustomerName = cust.name
            resolvedCustomerPhone = cust.phone
        } else {
            guard let name = customerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                throw DomainError.customerRequired(detail: "Elige un cliente o escribe su nombre")
            }
            resolvedCustomerId = nil
            resolvedCustomerName = name
            let phone = customerPhone?.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedCustomerPhone = (phone?.isEmpty == false) ? phone : nil
        }

        // Cálculo de líneas con CostingIndex
        let costing = CostingIndex(data: clone)
        var recipeCostCache: [String: RecipeCost] = [:]
        var orderItems: [OrderItem] = []

        for it in items {
            let rec = clone.recipes.active(it.recipeId)!
            let costInfo: RecipeCost
            if let cached = recipeCostCache[it.recipeId] {
                costInfo = cached
            } else {
                costInfo = try costing.calculateRecipeCost(recipe: rec, version: nil, now: ctx.now)
                recipeCostCache[it.recipeId] = costInfo
            }

            let unitPrice: Int
            let snapshot: Int
            let unitLabel: BaseUnit?

            let defaultPrice = clone.defaultLinePriceCents(recipeId: it.recipeId, soldBy: it.soldBy, cost: costInfo)
            unitPrice = it.unitPriceCents ?? defaultPrice

            if it.soldBy == .unit {
                snapshot = CostingMath.roundToCents(Qty.decimal(costInfo.costPerYieldUnit) ?? Decimal(0))
                unitLabel = rec.yieldUnit
            } else {
                snapshot = costInfo.batchCostCents
                unitLabel = nil
            }

            orderItems.append(
                OrderItem(
                    recipeId: it.recipeId,
                    recipeName: rec.name,
                    soldBy: it.soldBy,
                    unitLabel: unitLabel,
                    quantity: it.quantity,
                    unitPriceCents: unitPrice,
                    unitCostCentsSnapshot: snapshot
                )
            )
        }

        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = (cleanNotes?.isEmpty == false) ? cleanNotes : nil

        let order = Order(
            id: ctx.newId(),
            customerId: resolvedCustomerId,
            customerName: resolvedCustomerName,
            customerPhone: resolvedCustomerPhone,
            deliveryAt: deliveryAt,
            items: orderItems,
            payments: [],
            status: .pendiente,
            notes: finalNotes,
            createdAt: ctx.now,
            updatedAt: ctx.now,
            deletedAt: nil
        )

        clone.orders.append(order)
        self = clone
        return order
    }

    /// Edita un pedido activo. Preserva líneas por pareja (receta, soldBy) conservando snapshots, labels y precios anteriores.
    @discardableResult
    public mutating func updateOrder(
        id: String,
        draft: OrderUpdateDraft,
        ctx: MutationContext = MutationContext()
    ) throws -> Order {
        var clone = self

        guard let idx = clone.orders.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Pedido no encontrado")
        }

        var order = clone.orders[idx]

        // Actualización de cliente
        if let cidWrapped = draft.customerId {
            if let cid = cidWrapped {
                guard let cust = clone.customers.active(cid) else {
                    throw DomainError.invalidReference(detail: "Cliente no encontrado")
                }
                order.customerId = cust.id
                order.customerName = cust.name
                order.customerPhone = cust.phone
            } else {
                order.customerId = nil
                if let name = draft.customerName {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        order.customerName = trimmed
                    }
                }
                if let phoneWrapped = draft.customerPhone {
                    let clean = phoneWrapped?.trimmingCharacters(in: .whitespacesAndNewlines)
                    order.customerPhone = (clean?.isEmpty == false) ? clean : nil
                }
            }
        } else {
            if order.customerId == nil {
                if let name = draft.customerName {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        order.customerName = trimmed
                    }
                }
                if let phoneWrapped = draft.customerPhone {
                    let clean = phoneWrapped?.trimmingCharacters(in: .whitespacesAndNewlines)
                    order.customerPhone = (clean?.isEmpty == false) ? clean : nil
                }
            }
        }

        if let deliv = draft.deliveryAt {
            order.deliveryAt = deliv
        }

        if let status = draft.status {
            order.status = status
        }

        if let notesWrapped = draft.notes {
            let clean = notesWrapped?.trimmingCharacters(in: .whitespacesAndNewlines)
            order.notes = (clean?.isEmpty == false) ? clean : nil
        }

        // Actualización de líneas
        if let newItemsDraft = draft.items {
            guard !newItemsDraft.isEmpty else {
                throw DomainError.invalidValue(detail: "El pedido debe tener al menos una línea")
            }

            for it in newItemsDraft {
                guard let q = Qty.decimal(it.quantity), q > Decimal(0) else {
                    throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
                }
                guard clone.recipes.active(it.recipeId) != nil else {
                    throw DomainError.invalidReference(detail: "Receta no encontrada: \(it.recipeId)")
                }
            }

            // Mapa de líneas previas por pareja (recipeId, soldBy)
            struct LineKey: Hashable {
                let recipeId: String
                let soldBy: OrderSoldBy
            }
            var existingLines: [LineKey: OrderItem] = [:]
            for line in order.items {
                let key = LineKey(recipeId: line.recipeId, soldBy: line.soldBy)
                if existingLines[key] == nil {
                    existingLines[key] = line
                }
            }

            let costing = CostingIndex(data: clone)
            var recipeCostCache: [String: RecipeCost] = [:]
            var updatedItems: [OrderItem] = []

            for it in newItemsDraft {
                let rec = clone.recipes.active(it.recipeId)!
                let key = LineKey(recipeId: it.recipeId, soldBy: it.soldBy)

                if let prev = existingLines[key] {
                    // Conserva snapshot, unitLabel, recipeName y precio previo si no se envía uno nuevo
                    let unitPrice = it.unitPriceCents ?? prev.unitPriceCents
                    updatedItems.append(
                        OrderItem(
                            recipeId: it.recipeId,
                            recipeName: prev.recipeName,
                            soldBy: it.soldBy,
                            unitLabel: prev.unitLabel,
                            quantity: it.quantity,
                            unitPriceCents: unitPrice,
                            unitCostCentsSnapshot: prev.unitCostCentsSnapshot
                        )
                    )
                } else {
                    // Línea nueva calcula según costeo
                    let costInfo: RecipeCost
                    if let cached = recipeCostCache[it.recipeId] {
                        costInfo = cached
                    } else {
                        costInfo = try costing.calculateRecipeCost(recipe: rec, version: nil, now: ctx.now)
                        recipeCostCache[it.recipeId] = costInfo
                    }

                    let unitPrice: Int
                    let snapshot: Int
                    let unitLabel: BaseUnit?

                    let defaultPrice = clone.defaultLinePriceCents(recipeId: it.recipeId, soldBy: it.soldBy, cost: costInfo)
                    unitPrice = it.unitPriceCents ?? defaultPrice

                    if it.soldBy == .unit {
                        snapshot = CostingMath.roundToCents(Qty.decimal(costInfo.costPerYieldUnit) ?? Decimal(0))
                        unitLabel = rec.yieldUnit
                    } else {
                        snapshot = costInfo.batchCostCents
                        unitLabel = nil
                    }

                    updatedItems.append(
                        OrderItem(
                            recipeId: it.recipeId,
                            recipeName: rec.name,
                            soldBy: it.soldBy,
                            unitLabel: unitLabel,
                            quantity: it.quantity,
                            unitPriceCents: unitPrice,
                            unitCostCentsSnapshot: snapshot
                        )
                    )
                }
            }

            order.items = updatedItems
        }

        // Validación de pago vs nuevo total
        let totals = computeOrderTotals(order: order)
        if totals.totalCents < totals.paidCents {
            throw DomainError.paymentExceedsBalance(detail: "El total quedaría por debajo de lo que ya te pagaron")
        }

        order.updatedAt = ctx.now
        clone.orders[idx] = order
        self = clone
        return order
    }

    /// Sobrecarga conveniente para editar pedidos pasando argumentos opcionales.
    @discardableResult
    public mutating func updateOrder(
        id: String,
        customerId: String?? = nil,
        customerName: String? = nil,
        customerPhone: String?? = nil,
        deliveryAt: Date? = nil,
        status: OrderStatus? = nil,
        notes: String?? = nil,
        items: [OrderItemDraft]? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Order {
        try updateOrder(
            id: id,
            draft: OrderUpdateDraft(
                customerId: customerId,
                customerName: customerName,
                customerPhone: customerPhone,
                deliveryAt: deliveryAt,
                status: status,
                notes: notes,
                items: items
            ),
            ctx: ctx
        )
    }

    /// Borra un pedido en modo soft delete.
    public mutating func deleteOrder(
        id: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var clone = self

        guard let idx = clone.orders.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Pedido no encontrado")
        }

        clone.orders[idx].deletedAt = ctx.now
        clone.orders[idx].updatedAt = ctx.now
        self = clone
    }

    // MARK: - Pagos

    /// Agrega un pago a un pedido activo. Valida que el monto no exceda el saldo pendiente.
    @discardableResult
    public mutating func addPayment(
        orderId: String,
        amountCents: Int,
        paidAt: Date? = nil,
        method: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Payment {
        var clone = self

        guard let idx = clone.orders.activeIndex(of: orderId) else {
            throw DomainError.notFound(detail: "Pedido no encontrado")
        }

        guard amountCents > 0 else {
            throw DomainError.invalidValue(detail: "El monto debe ser mayor que cero")
        }

        let totals = computeOrderTotals(order: clone.orders[idx])
        if totals.paidCents + amountCents > totals.totalCents {
            throw DomainError.paymentExceedsBalance(detail: "El pago excede el saldo pendiente")
        }

        let cleanMethod = method?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalMethod = (cleanMethod?.isEmpty == false) ? cleanMethod : nil

        let payment = Payment(
            id: ctx.newId(),
            amountCents: amountCents,
            paidAt: paidAt ?? ctx.now,
            method: finalMethod
        )

        clone.orders[idx].payments.append(payment)
        clone.orders[idx].updatedAt = ctx.now
        self = clone
        return payment
    }

    /// Quita un pago de un pedido activo.
    public mutating func deletePayment(
        orderId: String,
        paymentId: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var clone = self

        guard let idx = clone.orders.activeIndex(of: orderId) else {
            throw DomainError.notFound(detail: "Pedido no encontrado")
        }

        guard let payIdx = clone.orders[idx].payments.firstIndex(where: { $0.id == paymentId }) else {
            throw DomainError.notFound(detail: "Pago no encontrado")
        }

        clone.orders[idx].payments.remove(at: payIdx)
        clone.orders[idx].updatedAt = ctx.now
        self = clone
    }
}
