import Foundation

/// `GET /me/` (docs/api-contract.md).
nonisolated struct Me: Decodable, Sendable, Equatable {
    let id: String
    let email: String
    let name: String
    let avatarUrl: String?
    let workspace: Workspace

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

nonisolated struct Workspace: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let currency: String
    let defaultMarginPercent: Int
    let priceStaleDays: Int
}
