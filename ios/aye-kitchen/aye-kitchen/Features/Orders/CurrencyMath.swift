import Foundation
import SwiftUI

/// Matemáticas exactas de dinero y cantidades para pedidos y pagos.
/// Regla 4 de GEMINI.md y Criterio 5: Nunca Double, solo Int en centavos y Decimal.
nonisolated enum CurrencyMath {
    static let halfUpRounding = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 0,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )

    /// Convierte un monto Decimal (en pesos/moneda) a centavos enteros sin usar Double.
    static func cents(from decimal: Decimal) -> Int {
        let inCents = decimal * 100
        return NSDecimalNumber(decimal: inCents).rounding(accordingToBehavior: halfUpRounding).intValue
    }

    /// Convierte centavos enteros a Decimal (en pesos/moneda).
    static func decimal(from cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// Convierte centavos a texto para edición ("250" o "250.50").
    static func formatForInput(cents: Int) -> String {
        let dec = decimal(from: cents)
        let number = NSDecimalNumber(decimal: dec)
        return number.stringValue
    }

    /// Convierte texto de dinero ("$250", "250.50", "250,50") a centavos enteros con Decimal.
    /// Devuelve nil si no es un número válido mayor o igual a 0.
    static func parseCents(from text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty,
              let dec = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
              dec >= 0 else {
            return nil
        }
        return cents(from: dec)
    }

    /// Subtotal de una línea de pedido: cantidad × precio unitario en centavos enteros.
    static func calculateSubtotalCents(quantity: String, unitPriceCents: Int) -> Int {
        let normalized = quantity.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let qty = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), qty > 0 else {
            return unitPriceCents
        }
        let totalDecimal = qty * Decimal(unitPriceCents)
        return NSDecimalNumber(decimal: totalDecimal).rounding(accordingToBehavior: halfUpRounding).intValue
    }
}

/// Formateo de fechas y horas en español de México (es_MX) y la zona horaria del dispositivo.
nonisolated enum OrderDateFormatter {
    private static let mxLocale = Locale(identifier: "es_MX")

    /// Encabezado de sección: "Hoy", "Mañana" o fecha completa ("Sábado 26 de octubre").
    static func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Hoy"
        } else if calendar.isDateInTomorrow(date) {
            return "Mañana"
        } else {
            let formatter = DateFormatter()
            formatter.locale = mxLocale
            formatter.timeZone = .current
            formatter.dateFormat = "EEEE d 'de' MMMM"
            let str = formatter.string(from: date)
            return str.prefix(1).uppercased() + str.dropFirst()
        }
    }

    /// Día abreviado en mayúsculas sin punto ("SÁB", "DOM", "LUN").
    static func dayAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = mxLocale
        formatter.timeZone = .current
        formatter.dateFormat = "EEE"
        let str = formatter.string(from: date).uppercased()
        return str.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Número del día ("26").
    static func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = mxLocale
        formatter.timeZone = .current
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    /// Hora en formato "4:00 pm".
    static func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = mxLocale
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        let str = formatter.string(from: date).lowercased()
        return str.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Fecha y hora completa para encabezado de detalle ("Sábado 26 de octubre, 4:00 pm").
    static func fullDateTime(for date: Date) -> String {
        let dfDate = DateFormatter()
        dfDate.locale = mxLocale
        dfDate.timeZone = .current
        dfDate.dateFormat = "EEEE d 'de' MMMM"
        let dateStr = dfDate.string(from: date)
        let capitalizedDate = dateStr.prefix(1).uppercased() + dateStr.dropFirst()

        let timeStr = timeString(for: date)
        return "\(capitalizedDate), \(timeStr)"
    }

    /// Fecha de pago ("25 de octubre, 3:30 pm").
    static func paymentDate(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = mxLocale
        formatter.timeZone = .current
        formatter.dateFormat = "d 'de' MMMM, h:mm a"
        let str = formatter.string(from: date).lowercased()
        return str.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

