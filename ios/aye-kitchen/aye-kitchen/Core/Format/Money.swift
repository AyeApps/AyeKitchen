import Foundation
import KitchenDomain

/// El dinero viaja en centavos enteros (`*_cents`) y solo se convierte a texto para mostrarlo.
nonisolated enum Money {
    static func format(cents: Int, currency: String = "MXN") -> String {
        let amount = Decimal(cents) / 100
        return amount.formatted(.currency(code: currency).locale(Locale(identifier: "es_MX")))
    }

    /// Precio por unidad comparable entre marcas, desde `cost_per_base_unit` (centavos por g/ml/pz).
    /// g → "$23.50 el kg", ml → "$23.50 el litro", pz → "$3.20 la pieza". Nulo si el texto no es un número.
    static func formatPerUnit(costPerBaseUnit: String, baseUnit: RemoteBaseUnit) -> String? {
        formatPerUnit(costPerBaseUnit: costPerBaseUnit, baseUnit: BaseUnit(rawValue: baseUnit.rawValue) ?? .g)
    }

    /// Igual, con la unidad de KitchenDomain (pantallas locales).
    static func formatPerUnit(costPerBaseUnit: String, baseUnit: BaseUnit) -> String? {
        guard let perBase = Decimal(string: costPerBaseUnit, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        let (multiplier, suffix): (Decimal, String) = switch baseUnit {
        case .g: (1000, "el kg")
        case .ml: (1000, "el litro")
        case .pz: (1, "la pieza")
        }
        var unrounded = perBase * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &unrounded, 0, .plain)
        let cents = NSDecimalNumber(decimal: rounded).intValue
        return "\(format(cents: cents)) \(suffix)"
    }
}
