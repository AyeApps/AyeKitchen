import Foundation
import Observation
import UIKit
import KitchenDomain

/// Modelo de vista para la pantalla principal de Cuenta y ajustes (`SettingsView`, Bloque I21).
@Observable
final class SettingsModel {
    let store: LocalStore
    var isSigningOut = false

    #if DEBUG
    var previewLastBackupAt: Date?
    var previewHasUnbackedChanges: Bool?
    #endif

    init(store: LocalStore = .shared) {
        self.store = store
    }

    var businessName: String {
        store.data.settings.name
    }

    var customUnitsCount: Int {
        store.data.units.filter { $0.isActive }.count
    }

    var hasUnbackedChanges: Bool {
        #if DEBUG
        if let previewHasUnbackedChanges {
            return previewHasUnbackedChanges
        }
        #endif
        return store.hasUnbackedChanges
    }

    var lastBackupAt: Date? {
        #if DEBUG
        if let previewLastBackupAt {
            return previewLastBackupAt
        }
        #endif
        return BackupService.shared.lastBackupAt
    }

    var isBackupWarning: Bool {
        hasUnbackedChanges
    }

    /// Resumen del estado de respaldo:
    /// - "Cambios sin respaldar" (si hay cambios pendientes).
    /// - "Sin respaldo" (si nunca se ha respaldado).
    /// - "Respaldado hace X min" / "hace un momento" (si está al día).
    var backupSummaryText: String {
        if hasUnbackedChanges {
            return "Cambios sin respaldar"
        }
        guard let lastBackupAt else {
            return "Sin respaldo"
        }
        let elapsed = Date().timeIntervalSince(lastBackupAt)
        if elapsed < 60 && elapsed >= -10 {
            return "Respaldado hace un momento"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.unitsStyle = .short
        return "Respaldado \(formatter.localizedString(for: lastBackupAt, relativeTo: Date()))"
    }

    func signOut(session: SessionStore) async {
        isSigningOut = true
        defer { isSigningOut = false }
        if store.hasUnbackedChanges {
            try? await BackupService.shared.backupNow()
        }
        await session.signOut()
    }

    #if DEBUG
    /// Solo desarrollo: copia los tokens de la sesión como JSON (`access_token`, `refresh_token`)
    /// para que los scripts de prueba llamen a la API con esta cuenta. Con el portapapeles
    /// universal llega directo a la Mac (`pbpaste`). Nunca existe en builds de release.
    func copySessionForScripts() {
        guard let tokens = KeychainStore.load() else { return }
        let payload = ["access_token": tokens.accessToken, "refresh_token": tokens.refreshToken]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = json
    }
    #endif
}

#if DEBUG
extension SettingsModel {
    static func preview(
        store: LocalStore = .preview(),
        lastBackupAt: Date? = Calendar.current.date(byAdding: .minute, value: -5, to: Date()),
        hasUnbackedChanges: Bool = false
    ) -> SettingsModel {
        let model = SettingsModel(store: store)
        model.previewLastBackupAt = lastBackupAt
        model.previewHasUnbackedChanges = hasUnbackedChanges
        return model
    }
}
#endif
