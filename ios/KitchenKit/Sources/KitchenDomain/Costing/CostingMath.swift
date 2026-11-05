import Foundation

public enum CostingMath {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Redondeo half-up a centavos enteros (como round_to_cents en Python).
    public static func roundToCents(_ amount: Decimal) -> Int {
        var result = Decimal()
        var input = amount
        NSDecimalRound(&result, &input, 0, .plain)
        return NSDecimalNumber(decimal: result).intValue
    }

    /// Formatea a 6 decimales con redondeo half-up (como quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP)).
    public static func formatSixDecimals(_ amount: Decimal) -> String {
        var result = Decimal()
        var input = amount
        NSDecimalRound(&result, &input, 6, .plain)
        let formatter = NumberFormatter()
        formatter.locale = posix
        formatter.minimumFractionDigits = 6
        formatter.maximumFractionDigits = 6
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: result)) ?? "0.000000"
    }
}
