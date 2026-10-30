import Foundation

// Clientes según docs/api-contract.md (B5).

/// `/customers/{id}`
nonisolated struct Customer: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let phone: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}
