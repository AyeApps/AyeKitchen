import Foundation

/// Todo lo que se borra marcando `deletedAt`. Las reglas y consultas usan `isActive`.
public protocol SoftDeletable {
    var deletedAt: Date? { get }
}

extension SoftDeletable {
    public var isActive: Bool { deletedAt == nil }
}

extension KitchenUnit: SoftDeletable {}
extension Ingredient: SoftDeletable {}
extension Supplier: SoftDeletable {}
extension Presentation: SoftDeletable {}
extension PriceRecord: SoftDeletable {}
extension Recipe: SoftDeletable {}
extension CostVersion: SoftDeletable {}
extension Customer: SoftDeletable {}
extension Order: SoftDeletable {}
extension Expense: SoftDeletable {}

extension Array where Element: SoftDeletable & Identifiable, Element.ID == String {
    /// Índice del elemento activo con ese id, o nulo (para editarlo en su lugar).
    func activeIndex(of id: String) -> Int? {
        firstIndex { $0.id == id && $0.isActive }
    }

    /// El elemento activo con ese id, o nulo.
    func active(_ id: String) -> Element? {
        first { $0.id == id && $0.isActive }
    }
}
