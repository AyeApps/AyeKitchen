import AuthenticationServices
import Observation

/// Estado de la sesión de toda la app. Se inyecta en el entorno desde `AyeKitchenApp`.
@Observable
final class SessionStore {
    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(Me)
        case unavailable(String)
    }

    private(set) var state: State = .checking

    var me: Me? {
        if case .signedIn(let me) = state { return me }
        return nil
    }

    func start() async {
        state = .checking
        await NetworkService.shared.setSessionExpiredHandler { [weak self] in
            self?.state = .signedOut
        }
        guard KeychainStore.load() != nil else {
            state = .signedOut
            return
        }
        await loadMe()
    }

    func signIn(email: String, password: String) async throws {
        try await NetworkService.shared.login(email: email, password: password)
        await loadMe()
    }

    func signUp(name: String, email: String, password: String) async throws {
        try await NetworkService.shared.register(name: name, email: email, password: password)
        await loadMe()
    }

    func signInWithApple(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.decoding("Apple no devolvió identityToken")
        }
        // Apple solo manda nombre y correo la primera vez que la persona entra.
        let name = credential.fullName
            .map { PersonNameComponentsFormatter().string(from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }
        try await NetworkService.shared.signInWithApple(identityToken: identityToken, name: name, email: credential.email)
        await loadMe()
    }

    func signOut() async {
        await NetworkService.shared.logout()
        state = .signedOut
    }

    private func loadMe() async {
        do {
            let me: Me = try await NetworkService.shared.request(.get, "/me/")
            state = .signedIn(me)
        } catch APIError.unauthorized {
            state = .signedOut
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }
}
