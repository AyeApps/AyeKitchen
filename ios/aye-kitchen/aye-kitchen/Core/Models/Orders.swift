import Foundation

// Pedidos y pagos según docs/api-contract.md (B4).

/// `/orders/{id}`
nonisolated struct Order: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    /// Cliente guardado al que está ligado el pedido (B5); `nil` si el nombre se escribió a mano.
    var customerId: String? = nil
    let customerName: String
    let customerPhone: String?
    let deliveryAt: Date
    let status: OrderStatus
    let notes: String?
    let items: [OrderItem]
    let payments: [Payment]
    let totalCents: Int
    let paidCents: Int
    let balanceCents: Int
    let costCents: Int
    let profitCents: Int
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct OrderItem: Decodable, Sendable, Hashable {
    let recipeId: String
    let recipeName: String
    let quantity: String
    /// Precio acordado con el cliente por unidad.
    let unitPriceCents: Int
    /// Costo de la receta cuando se creó la línea; no cambia aunque cambien los precios.
    let unitCostCentsSnapshot: Int
    /// B7. Por tanda o por la unidad que rinde la receta. Nulo en servidores viejos = tanda.
    var soldBy: OrderSoldBy? = nil
    /// B7. La unidad de la línea cuando `soldBy == .unit` ("pz", "g"); nulo en tandas.
    var unitLabel: BaseUnit? = nil
}

/// B7. Cómo se vende una línea del pedido.
nonisolated enum OrderSoldBy: String, Codable, Sendable, Hashable {
    /// Tandas completas de la receta.
    case batch
    /// La unidad que rinde la receta (piezas, g, ml).
    case unit
}

nonisolated struct Payment: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let amountCents: Int
    let paidAt: Date
    let method: String?
}
