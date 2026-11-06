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
    private var isSyncingReferences = false

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
        await syncReferences()
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
        await syncReferences()
        return true
    }

    /// Sincroniza las imágenes de referencia con el servidor:
    /// - Pide `GET /backup/references/`.
    /// - Sube (`PUT`) las referencias activas que el servidor no tiene o tiene con otra huella.
    /// - Borra en el servidor (`DELETE`) las de `deletedReferenceIds()`.
    /// - Baja las activas que faltan como archivo local.
    /// Una a la vez, sin detener todo si una falla.
    func syncReferences() async {
        guard !isSyncingReferences else { return }
        let store = LocalStore.shared
        guard store.state == .ready else { return }
        isSyncingReferences = true
        defer { isSyncingReferences = false }

        let serverList: [RemoteReferenceInfo]
        do {
            serverList = try await NetworkService.shared.request(.get, "/backup/references/")
        } catch {
            return
        }

        let serverMap = Dictionary(uniqueKeysWithValues: serverList.map { ($0.id, $0) })
        let activeRefs = store.data.activeReferences()
        let refStore = ReferenceStore.shared

        // Sube referencias activas que falten en el servidor o tengan huella distinta
        for ref in activeRefs {
            let serverRef = serverMap[ref.id]
            if serverRef == nil || serverRef?.sha256 != ref.sha256 {
                guard let url = refStore.fileURL(for: ref.id),
                      let data = try? Data(contentsOf: url) else {
                    continue
                }
                do {
                    let query = [URLQueryItem(name: "sha256", value: ref.sha256)]
                    _ = try await NetworkService.shared.requestRawData(
                        .put,
                        "/backup/references/\(ref.id)",
                        query: query,
                        data: data,
                        contentType: ref.contentType
                    )
                } catch {
                    // Continúa si falla una
                }
            }
        }

        // Borra en el servidor las referencias eliminadas
        for deletedId in store.data.deletedReferenceIds() {
            refStore.deleteLocalFile(for: deletedId)
            guard serverMap[deletedId] != nil else { continue }
            do {
                try await NetworkService.shared.requestNoContent(.delete, "/backup/references/\(deletedId)")
            } catch {
                // Continúa si falla una
            }
        }

        // Baja las referencias activas que falten como archivo local
        for ref in activeRefs {
            guard !refStore.hasLocalFile(ref.id) else { continue }
            guard serverMap[ref.id] != nil else { continue }
            do {
                let data = try await NetworkService.shared.requestRawData(.get, "/backup/references/\(ref.id)")
                try refStore.saveDownloaded(id: ref.id, data: data, contentType: ref.contentType)
            } catch {
                // Continúa si falla una
            }
        }
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

/// `ReferenceImageInfo` del contrato para /backup/references/.
nonisolated struct RemoteReferenceInfo: Decodable, Sendable, Hashable {
    let id: String
    let sha256: String
    let sizeBytes: Int
    let contentType: String
    let updatedAt: Date
}
