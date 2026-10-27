import Foundation

/// Lista paginada del contrato: `?page=1&limit=20` (máx. 100).
nonisolated struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let total: Int
    let page: Int
    let limit: Int
    let pages: Int

    var hasMore: Bool { page < pages }
}

/// Unidad base de ingredientes, presentaciones y rendimiento de recetas.
nonisolated enum BaseUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case g, ml, pz
}
