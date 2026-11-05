import CryptoKit
import Foundation

/// Guarda en disco la última respuesta cruda (JSON) de algunas peticiones GET, para mostrar
/// datos al abrir la app sin esperar a la red, o sin conexión.
///
/// - Una carpeta por cuenta (`useAccount`): una cuenta nunca ve la caché de otra.
/// - Vive en Caches (iOS puede borrarla si falta espacio: es solo una copia) con protección de
///   archivo `completeUntilFirstUserAuthentication`.
/// - Se borra completa al cerrar sesión (`clearAll`).
///
/// No se usa directo desde las pantallas: `NetworkService.request(..., cache: true)` guarda y
/// `NetworkService.cached(...)` lee.
actor ResponseCache {
    static let shared = ResponseCache()

    private var accountId: String?
    private let fileManager = FileManager.default

    private var rootURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ResponseCache", isDirectory: true)
    }

    private var accountURL: URL? {
        guard let accountId, let rootURL else { return nil }
        return rootURL.appendingPathComponent(Self.hash(accountId), isDirectory: true)
    }

    /// Cuenta cuyos datos se leen y escriben. Sin cuenta, la caché no guarda ni devuelve nada.
    func useAccount(_ id: String?) {
        accountId = id
    }

    func save(_ data: Data, for key: String) {
        guard let dir = accountURL else { return }
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(
                to: dir.appendingPathComponent(Self.hash(key) + ".json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            // Es solo una copia: si no se puede guardar, la app sigue funcionando con la red.
        }
    }

    func load(for key: String) -> Data? {
        guard let dir = accountURL else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(Self.hash(key) + ".json"))
    }

    /// Borra la caché de todas las cuentas (cerrar sesión, sesión vencida).
    func clearAll() {
        guard let rootURL else { return }
        try? fileManager.removeItem(at: rootURL)
    }

    /// Clave estable para una petición: ruta + query ordenada.
    static func key(path: String, query: [URLQueryItem]) -> String {
        let sorted = query
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return sorted.isEmpty ? path : "\(path)?\(sorted)"
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
