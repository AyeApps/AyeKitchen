import Foundation
import KitchenDomain

// MARK: - Texto del tamaño de una marca

public enum PackageText {
    /// Devuelve el texto del tamaño de una marca para mostrar:
    /// "24 × 900 ml" si tiene paquete grande, o "1,000 g" como hoy si no.
    public static func format(_ presentation: CatalogPresentation) -> String {
        packageText(for: presentation)
    }
}

/// Devuelve el texto del tamaño de una marca para mostrar:
/// "24 × 900 ml" si tiene paquete grande, o "1,000 g" como hoy si no.
public func packageText(for presentation: CatalogPresentation) -> String {
    if let packCount = presentation.packCount,
       let packItemQuantity = presentation.packItemQuantity {
        let countStr = Quantity.format("\(packCount)")
        let itemQtyStr = Quantity.format(packItemQuantity)
        return "\(countStr) × \(itemQtyStr) \(presentation.baseUnit.rawValue)"
    } else {
        let pkgQty = Quantity.format(presentation.packageQuantity)
        return "\(pkgQty) \(presentation.baseUnit.rawValue)"
    }
}
