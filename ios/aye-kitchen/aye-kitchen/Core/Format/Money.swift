import Foundation

/// El dinero viaja en centavos enteros (`*_cents`) y solo se convierte a texto para mostrarlo.
nonisolated enum Money {
    static func format(cents: Int, currency: String = "MXN") -> String {
        let amount = Decimal(cents) / 100
        return amount.formatted(.currency(code: currency).locale(Locale(identifier: "es_MX")))
    }
}
