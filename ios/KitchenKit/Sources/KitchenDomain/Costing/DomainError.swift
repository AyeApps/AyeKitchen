import Foundation

public enum DomainError: Error, Equatable, Sendable {
    case unitNotConvertible(detail: String)
    case invalidReference(detail: String)
    case notFound(detail: String)
}

extension DomainError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { detail }
    public var description: String { detail }

    public var detail: String {
        switch self {
        case .unitNotConvertible(let detail):
            return detail
        case .invalidReference(let detail):
            return detail
        case .notFound(let detail):
            return detail
        }
    }

    public var code: String {
        switch self {
        case .unitNotConvertible:
            return "UNIT_NOT_CONVERTIBLE"
        case .invalidReference:
            return "INVALID_REFERENCE"
        case .notFound:
            return "NOT_FOUND"
        }
    }
}
