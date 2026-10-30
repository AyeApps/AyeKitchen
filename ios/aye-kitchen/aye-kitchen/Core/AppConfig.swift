import Foundation

nonisolated enum AppConfig {
    #if DEBUG
    static let apiBaseURL = URL(string: "http://localhost:8006/api/v1")!
    static let authBaseURL = URL(string: "http://localhost:8000/api/v1/auth")!
    #else
    static let apiBaseURL = URL(string: "https://api-aykchn.ayeapps.com/api/v1")!
    static let authBaseURL = URL(string: "https://api-auth.ayeapps.com/api/v1/auth")!
    #endif

    /// `app_client` que aye-auth usa para dar acceso a esta app (`apps_access.kitchen`).
    static let appClient = "kitchen"
}
