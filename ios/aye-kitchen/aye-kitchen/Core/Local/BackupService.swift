import Foundation
import KitchenDomain
import Observation

/// Respaldo del teléfono en el servidor (`/backup`, docs/api-contract.md).
///
/// - `backupNow(force:)` sube los datos actuales. Manda `base_backup_id` (el último que este
///   teléfono subió o restauró); si otro dispositivo subió después, el servidor responde
///   `BACKUP_CONFLICT` y aquí se lanza `BackupError.conflict` para que la pantalla pregunte.
/// - `restoreLatest()` baja el último respaldo y reemplaza los datos locales.
/// - El respaldo automático (bloque I20) llama `backupNow()` cuando `LocalStore` avisa cambios.
@Observable
final class BackupService {
    static let shared = BackupService()

    enum BackupError: LocalizedError, Equatable {
        /// Otro teléfono subió un respaldo más nuevo. `detail` trae la fecha.
        case conflict(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .conflict(let detail), .failed(let detail): detail
            }
        }
    }

    private(set) var isBackingUp = false
    private(set) var lastBackupAt: Date?
    private(set) var lastError: BackupError?

    private var accountId: String?

    private init() {}

    func useAccount(_ id: String?) {
        accountId = id
        lastBackupAt = UserDefaults.standard.object(forKey: key("lastAt")) as? Date
        lastError = nil
    }

    /// Sube los datos actuales. `force` sobrescribe aunque otro teléfono haya subido después.
    func backupNow(force: Bool = false) async throws {
        let store = LocalStore.shared
        guard store.state == .ready, !isBackingUp else { return }
        isBackingUp = true
        defer { isBackingUp = false }

        let revision = store.revision
        var snapshot = store.data
        snapshot.exportedAt = Date()
        let payload = snapshot
        do {
            let json = try await Task.detached(priority: .utility) { try KitchenCoding.encode(payload) }.value
            var query: [URLQueryItem] = []
            if let base = lastBackupId {
                query.append(URLQueryItem(name: "base_backup_id", value: base))
            }
            if force {
                query.append(URLQueryItem(name: "force", value: "true"))
            }
            let response = try await NetworkService.shared.requestRawJSON(.put, "/backup/", query: query, json: json)
            let info = try JSONCoding.decode(BackupInfo.self, from: response)
            remember(info)
            store.markBackedUp(revision: revision)
            lastError = nil
        } catch let error as APIError where error.code == "BACKUP_CONFLICT" {
            let conflict = BackupError.conflict(error.localizedDescription)
            lastError = conflict
            throw conflict
        } catch {
            let failed = BackupError.failed(error.localizedDescription)
            lastError = failed
            throw failed
        }
    }

    /// Baja el último respaldo de la cuenta. `nil` si nunca se ha respaldado.
    func downloadLatest() async throws -> KitchenData? {
        do {
            let json = try await NetworkService.shared.requestRawJSON(.get, "/backup/latest")
            return try await Task.detached(priority: .userInitiated) { try KitchenCoding.decode(json) }.value
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    /// Lo que hoy tiene el servidor en sus colecciones (migración, una sola vez).
    func exportCurrentServerData() async throws -> KitchenData {
        let json = try await NetworkService.shared.requestRawJSON(.get, "/backup/export-current")
        return try await Task.detached(priority: .userInitiated) { try KitchenCoding.decode(json) }.value
    }

    /// Reemplaza los datos locales con el último respaldo. Devuelve `false` si no hay respaldo.
    func restoreLatest() async throws -> Bool {
        guard let data = try await downloadLatest() else { return false }
        LocalStore.shared.replaceAll(with: data, backedUp: true)
        if let info = try? await latestInfo() {
            remember(info)
        }
        return true
    }

    func latestInfo() async throws -> BackupInfo? {
        let list: [BackupInfo] = try await NetworkService.shared.request(.get, "/backup/")
        return list.first
    }

    // MARK: Internos

    private var lastBackupId: String? {
        UserDefaults.standard.string(forKey: key("lastId"))
    }

    private func remember(_ info: BackupInfo) {
        UserDefaults.standard.set(info.id, forKey: key("lastId"))
        UserDefaults.standard.set(info.createdAt, forKey: key("lastAt"))
        lastBackupAt = info.createdAt
    }

    private func key(_ name: String) -> String {
        "BackupService.\(name).\(accountId ?? "-")"
    }
}

/// `BackupInfo` del contrato.
nonisolated struct BackupInfo: Decodable, Sendable, Hashable {
    let id: String
    let schemaVersion: Int
    let deviceId: String
    let exportedAt: Date
    let createdAt: Date
    let sizeBytes: Int
}
