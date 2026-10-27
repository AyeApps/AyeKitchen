import Foundation

/// Las cantidades viajan como string decimal ("0.5", "1000") para no perder precisión.
nonisolated enum Quantity {
    /// "1000" → "1,000"; "0.50" → "0.5". Si el texto no es un número, lo devuelve igual.
    static func format(_ value: String) -> String {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return value }
        return decimal.formatted(.number.precision(.fractionLength(0...3)).locale(Locale(identifier: "es_MX")))
    }

    /// Lo que escribe la usuaria ("1,5" o "1.5") → string decimal para el backend; nulo si no es un número > 0.
    static func parse(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), decimal > 0 else {
            return nil
        }
        return "\(decimal)"
    }
}
