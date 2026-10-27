import Foundation

// Pedidos y pagos según docs/api-contract.md (B4).

/// `/orders/{id}`
nonisolated struct Order: Decodable, Sendable, Hashable, Identifiable {
    let id: String
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
}

nonisolated struct Payment: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let amountCents: Int
    let paidAt: Date
    let method: String?
}
