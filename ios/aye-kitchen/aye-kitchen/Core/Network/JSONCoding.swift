import Foundation

/// Llaves en snake_case como las manda el backend; fechas ISO 8601 en UTC.
nonisolated enum JSONCoding {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = APIDate.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Fecha inválida: \(string)")
            }
            return date
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}

nonisolated enum APIDate {
    // Se crean una sola vez: armar un formateador por cada fecha hacía lento decodificar listas.
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    /// Acepta fechas con o sin zona (sin zona = UTC) y con microsegundos, como las devuelve Pydantic.
    static func parse(_ string: String) -> Date? {
        var value = string
        if !hasZone(value) {
            value += "Z"
        }
        value = truncatingFraction(value)
        return (try? withFraction.parse(value)) ?? (try? plain.parse(value))
    }

    /// Termina en "Z" o en un desfase "+hh:mm" / "-hh:mm".
    private static func hasZone(_ value: String) -> Bool {
        if value.hasSuffix("Z") { return true }
        let chars = Array(value.suffix(6))
        guard chars.count == 6, chars[0] == "+" || chars[0] == "-", chars[3] == ":" else { return false }
        return [1, 2, 4, 5].allSatisfy { chars[$0].isASCII && chars[$0].isNumber }
    }

    /// El formato ISO 8601 solo lee hasta milisegundos: ".264000" pasa a ".264".
    private static func truncatingFraction(_ value: String) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        var end = value.index(after: dot)
        while end < value.endIndex, value[end].isASCII, value[end].isNumber {
            end = value.index(after: end)
        }
        let digits = value.distance(from: value.index(after: dot), to: end)
        guard digits > 3 else { return value }
        let keepEnd = value.index(dot, offsetBy: 4)
        return String(value[..<keepEnd]) + String(value[end...])
    }
}
