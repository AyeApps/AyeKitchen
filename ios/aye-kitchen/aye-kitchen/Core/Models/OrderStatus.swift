import Foundation

/// Estados de pedido del contrato (`status` en `/orders`).
nonisolated enum OrderStatus: String, Codable, Sendable, CaseIterable {
    case pending = "pendiente"
    case inProgress = "en_proceso"
    case delivered = "entregado"
    case cancelled = "cancelado"

    var label: String {
        switch self {
        case .pending: "Pendiente"
        case .inProgress: "En proceso"
        case .delivered: "Entregado"
        case .cancelled: "Cancelado"
        }
    }
}
