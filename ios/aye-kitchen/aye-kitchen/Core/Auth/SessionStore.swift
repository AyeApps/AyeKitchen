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

    /// Última cuenta que entró en este teléfono: permite abrir la app sin red con sus datos guardados.
    private static let lastAccountKey = "SessionStore.lastAccountId"

    func start() async {
        state = .checking
        await NetworkService.shared.setSessionExpiredHandler { [weak self] in
            self?.state = .signedOut
            Task { await self?.forgetLocalData() }
        }
        guard KeychainStore.load() != nil else {
            state = .signedOut
            return
        }
        await useAccount(UserDefaults.standard.string(forKey: Self.lastAccountKey))
        await loadMe()
    }

    func signIn(email: String, password: String) async throws {
        #if DEBUG
        if DebugAccount.matches(email: email, password: password) {
            DebugAccount.isActive = true
            state = .signedIn(DebugAccount.me)
            return
        }
        #endif
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
        #if DEBUG
        if DebugAccount.isActive {
            DebugAccount.isActive = false
            state = .signedOut
            return
        }
        #endif
        await NetworkService.shared.logout()
        await forgetLocalData()
        state = .signedOut
    }

    /// Pide `/me/`. Sin red, si esta cuenta ya había entrado en el teléfono, entra con su copia
    /// guardada para que se puedan ver los datos de la caché.
    private func loadMe() async {
        do {
            let me: Me = try await NetworkService.shared.request(.get, "/me/")
            await useAccount(me.id)
            await NetworkService.shared.cacheMe(me)
            state = .signedIn(me)
        } catch APIError.unauthorized {
            state = .signedOut
        } catch APIError.network(let error) {
            if let saved: Me = await NetworkService.shared.cached("/me/") {
                state = .signedIn(saved)
            } else {
                state = .unavailable(APIError.network(error).localizedDescription)
            }
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    /// Caché en disco y marcas de cambios por cuenta: una cuenta nunca ve los datos de otra.
    private func useAccount(_ id: String?) async {
        if let id {
            UserDefaults.standard.set(id, forKey: Self.lastAccountKey)
        }
        await ResponseCache.shared.useAccount(id)
    }

    private func forgetLocalData() async {
        UserDefaults.standard.removeObject(forKey: Self.lastAccountKey)
        await ResponseCache.shared.clearAll()
        await ResponseCache.shared.useAccount(nil)
    }
}
