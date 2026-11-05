import Foundation

/// Errores de negocio, uno por código de la tabla de `docs/api-contract.md`. Las pantallas deciden
/// por `code` y muestran `detail` (texto en palabras de la cocina, igual que el backend).
public enum DomainError: Error, Equatable, Sendable {
    case notFound(detail: String)
    case systemUnitReadonly(detail: String)
    case unitNotConvertible(detail: String)
    case duplicateName(detail: String)
    case inUse(detail: String)
    case recipeCycle(detail: String)
    case recipeTooDeep(detail: String)
    case invalidReference(detail: String)
    case customerRequired(detail: String)
    case paymentExceedsBalance(detail: String)
    /// Datos que no pasan una regla de forma (vacío, fuera de rango). Equivale al 422 estándar.
    case invalidValue(detail: String)
}

extension DomainError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { detail }
    public var description: String { detail }

    public var detail: String {
        switch self {
        case .notFound(let detail), .systemUnitReadonly(let detail), .unitNotConvertible(let detail),
             .duplicateName(let detail), .inUse(let detail), .recipeCycle(let detail), .recipeTooDeep(let detail),
             .invalidReference(let detail), .customerRequired(let detail), .paymentExceedsBalance(let detail),
             .invalidValue(let detail):
            detail
        }
    }

    public var code: String {
        switch self {
        case .notFound: "NOT_FOUND"
        case .systemUnitReadonly: "SYSTEM_UNIT_READONLY"
        case .unitNotConvertible: "UNIT_NOT_CONVERTIBLE"
        case .duplicateName: "DUPLICATE_NAME"
        case .inUse: "IN_USE"
        case .recipeCycle: "RECIPE_CYCLE"
        case .recipeTooDeep: "RECIPE_TOO_DEEP"
        case .invalidReference: "INVALID_REFERENCE"
        case .customerRequired: "CUSTOMER_REQUIRED"
        case .paymentExceedsBalance: "PAYMENT_EXCEEDS_BALANCE"
        case .invalidValue: "INVALID_VALUE"
        }
    }
}
