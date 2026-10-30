import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

/// Único cliente HTTP de la app. Pone el token de la cuenta Aye, renueva la sesión una sola vez
/// ante un 401 y convierte las respuestas de error en `APIError`.
///
/// Uso desde un ViewModel:
///     let me: Me = try await NetworkService.shared.request(.get, "/me/")
///     try await NetworkService.shared.requestNoContent(.delete, "/ingredients/\(id)")
/// Las rutas salen tal cual de docs/api-contract.md (colecciones con `/` final, recursos sin ella).
actor NetworkService {
    static let shared = NetworkService()

    private let session: URLSession = .shared
    private var refreshTask: Task<Void, Error>?
    private var onSessionExpired: (@MainActor @Sendable () -> Void)?

    func setSessionExpiredHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        onSessionExpired = handler
    }

    // MARK: API de AyeKitchen

    func request<T: Decodable & Sendable>(
        _ method: HTTPMethod = .get,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        let data = try await perform(method, AppConfig.apiBaseURL, path, query: query, body: body, authorized: true)
        return try JSONCoding.decode(T.self, from: data)
    }

    func requestNoContent(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil
    ) async throws {
        _ = try await perform(method, AppConfig.apiBaseURL, path, query: query, body: body, authorized: true)
    }

    // MARK: Cuenta Aye (aye-auth)

    func register(name: String, email: String, password: String) async throws {
        let body = RegisterBody(name: name, email: email, password: password, appClient: AppConfig.appClient)
        let data = try await perform(.post, AppConfig.authBaseURL, "/register", body: body, authorized: false)
        try store(JSONCoding.decode(TokenResponse.self, from: data))
    }

    func login(email: String, password: String) async throws {
        let body = LoginBody(email: email, password: password, appClient: AppConfig.appClient)
        let data = try await perform(.post, AppConfig.authBaseURL, "/login", body: body, authorized: false)
        try store(JSONCoding.decode(TokenResponse.self, from: data))
    }

    func signInWithApple(identityToken: String, name: String?, email: String?) async throws {
        let body = AppleBody(identityToken: identityToken, name: name, email: email, appClient: AppConfig.appClient)
        let data = try await perform(.post, AppConfig.authBaseURL, "/oauth/apple", body: body, authorized: false)
        try store(JSONCoding.decode(TokenResponse.self, from: data))
    }

    /// Cierra la sesión en aye-auth si se puede; los tokens locales se borran siempre.
    func logout() async {
        if let tokens = KeychainStore.load() {
            _ = try? await perform(
                .delete, AppConfig.authBaseURL, "/logout",
                body: RefreshBody(refreshToken: tokens.refreshToken), authorized: true, isRetry: true
            )
        }
        KeychainStore.clear()
    }

    // MARK: Internos

    private func perform(
        _ method: HTTPMethod,
        _ base: URL,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        authorized: Bool,
        isRetry: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(string: base.absoluteString + path) else {
            throw APIError.invalidURL(path)
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONCoding.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let tokens = KeychainStore.load() else {
                throw await expireSession()
            }
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401 where authorized && !isRetry:
            try await refreshTokens()
            return try await perform(method, base, path, query: query, body: body, authorized: true, isRetry: true)
        case 401 where authorized:
            throw await expireSession()
        default:
            throw APIError.from(status: http.statusCode, data: data)
        }
    }

    /// Varias peticiones pueden recibir 401 a la vez: todas esperan la misma renovación.
    private func refreshTokens() async throws {
        if let refreshTask {
            do {
                return try await refreshTask.value
            } catch {
                throw APIError.unauthorized
            }
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            try await task.value
        } catch {
            throw await expireSession()
        }
    }

    private func performRefresh() async throws {
        guard let tokens = KeychainStore.load() else {
            throw APIError.unauthorized
        }
        let body = RefreshBody(refreshToken: tokens.refreshToken)
        let data = try await perform(.post, AppConfig.authBaseURL, "/refresh", body: body, authorized: false)
        try store(JSONCoding.decode(TokenResponse.self, from: data))
    }

    private func store(_ response: TokenResponse) throws {
        KeychainStore.save(AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken))
    }

    private func expireSession() async -> APIError {
        KeychainStore.clear()
        if let onSessionExpired {
            await onSessionExpired()
        }
        return .unauthorized
    }
}

private nonisolated struct RegisterBody: Encodable, Sendable {
    let name: String
    let email: String
    let password: String
    let appClient: String
}

private nonisolated struct LoginBody: Encodable, Sendable {
    let email: String
    let password: String
    let appClient: String
}

private nonisolated struct AppleBody: Encodable, Sendable {
    let identityToken: String
    let name: String?
    let email: String?
    let appClient: String
}

private nonisolated struct RefreshBody: Encodable, Sendable {
    let refreshToken: String
}

/// Respuesta de aye-auth; aquí solo importan los tokens (el perfil sale de `/me/`).
private nonisolated struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
}
