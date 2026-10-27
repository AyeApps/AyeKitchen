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
    /// Acepta fechas con o sin zona (sin zona = UTC) y con microsegundos, como las devuelve Pydantic.
    static func parse(_ string: String) -> Date? {
        var value = string
        if value.range(of: #"(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) == nil {
            value += "Z"
        }
        // ISO8601DateFormatter solo lee hasta milisegundos.
        value = value.replacing(/(\.\d{3})\d+/) { $0.output.1 }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: value) ?? plain.date(from: value)
    }
}
