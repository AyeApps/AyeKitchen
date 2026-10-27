import Foundation

/// Errores de red y del contrato (`{"detail": "...", "code": "..."}`, ver docs/api-contract.md).
/// Las pantallas deciden por `code`, nunca por el texto de `detail`.
nonisolated enum APIError: Error, Sendable {
    /// La sesión terminó y no se pudo renovar. La app ya volvió a la pantalla de entrar.
    case unauthorized
    case server(status: Int, code: String?, message: String?)
    case network(URLError)
    case decoding(String)
    case invalidURL(String)

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    var status: Int? {
        if case .server(let status, _, _) = self { return status }
        return nil
    }

    static func from(status: Int, data: Data) -> APIError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        return .server(status: status, code: body?.code, message: body?.message)
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Tu sesión terminó. Vuelve a entrar."
        case .server(_, _, let message):
            message ?? "Algo salió mal. Intenta de nuevo."
        case .network:
            "No pudimos conectarnos. Revisa tu internet e intenta de nuevo."
        case .decoding, .invalidURL:
            "Recibimos una respuesta que no entendimos. Intenta de nuevo."
        }
    }
}

private nonisolated struct ErrorBody: Decodable {
    let code: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case detail, code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decode(String.self, forKey: .code)
        // El 422 de validación de FastAPI trae una lista en `detail`: ahí no hay texto para mostrar.
        message = try? container.decode(String.self, forKey: .detail)
    }
}
