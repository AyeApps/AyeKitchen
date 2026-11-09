import Foundation
import Observation
import SwiftUI

/// Formateo de fechas y horas para la pantalla de respaldo en español de México (es_MX).
nonisolated enum BackupDateFormatter {
    private static let mxLocale = Locale(identifier: "es_MX")

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = mxLocale
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = mxLocale
        formatter.timeZone = .current
        formatter.dateFormat = "d 'de' MMMM"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = mxLocale
        formatter.timeZone = .current
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter
    }()

    static func timeString(for date: Date) -> String {
        let str = timeFormatter.string(from: date).lowercased()
        return str.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Formato relativo: "hoy, 4:32 pm", "ayer, 4:32 pm", "24 de octubre, 4:32 pm".
    static func relativeDateTime(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeString(for: date)
        if calendar.isDateInToday(date) {
            return "hoy, \(time)"
        } else if calendar.isDateInYesterday(date) {
            return "ayer, \(time)"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            let dayMonth = dayMonthFormatter.string(from: date).lowercased()
            return "\(dayMonth), \(time)"
        } else {
            let full = fullDateFormatter.string(from: date).lowercased()
            return "\(full), \(time)"
        }
    }

    /// Formato para frases de confirmación: "de hoy a las 4:32 pm", "del 24 de octubre a las 4:32 pm".
    static func restoreReference(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeString(for: date)
        if calendar.isDateInToday(date) {
            return "de hoy a las \(time)"
        } else if calendar.isDateInYesterday(date) {
            return "de ayer a las \(time)"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            let dayMonth = dayMonthFormatter.string(from: date).lowercased()
            return "del \(dayMonth) a las \(time)"
        } else {
            let full = fullDateFormatter.string(from: date).lowercased()
            return "del \(full) a las \(time)"
        }
    }
}

/// Modelo de vista para la pantalla de Respaldo (`BackupView`, Bloque I20).
@Observable
final class BackupModel {
    private let backupService: BackupService?
    private let localStore: LocalStore?

    var previewLastBackupAt: Date?
    var previewHasUnbackedChanges: Bool?
    var previewLastError: BackupService.BackupError?
    var previewLatestBackupDate: Date?

    private(set) var latestBackupInfo: BackupInfo?
    private(set) var isBackingUp = false
    private(set) var isRestoring = false
    private(set) var conflictResolvedLocally = false
    var restoreErrorMessage: String?

    init(
        backupService: BackupService? = .shared,
        localStore: LocalStore? = .shared
    ) {
        self.backupService = backupService
        self.localStore = localStore
    }

    #if DEBUG
    /// Constructor para vistas previas sin tocar red ni archivos en disco.
    static func preview(
        lastBackupAt: Date? = Date(),
        hasUnbackedChanges: Bool = false,
        lastError: BackupService.BackupError? = nil,
        latestServerBackupDate: Date? = Date()
    ) -> BackupModel {
        let model = BackupModel(backupService: nil, localStore: nil)
        model.previewLastBackupAt = lastBackupAt
        model.previewHasUnbackedChanges = hasUnbackedChanges
        model.previewLastError = lastError
        model.previewLatestBackupDate = latestServerBackupDate
        return model
    }
    #endif

    // MARK: Estado observable

    var isBackingUpEffective: Bool {
        isBackingUp || (backupService?.isBackingUp ?? false)
    }

    var isBusy: Bool {
        isBackingUpEffective || isRestoring
    }

    var lastBackupAt: Date? {
        previewLastBackupAt ?? backupService?.lastBackupAt
    }

    var hasUnbackedChanges: Bool {
        previewHasUnbackedChanges ?? localStore?.hasUnbackedChanges ?? false
    }

    var lastError: BackupService.BackupError? {
        if conflictResolvedLocally {
            return nil
        }
        return previewLastError ?? backupService?.lastError
    }

    var hasConflict: Bool {
        if case .conflict = lastError {
            return true
        }
        return false
    }

    var conflictDetail: String? {
        if case .conflict(let detail) = lastError {
            return detail
        }
        return nil
    }

    var failedDetail: String? {
        if case .failed(let detail) = lastError {
            return detail
        }
        return nil
    }

    // MARK: Textos de estado

    /// "Último respaldo: hoy, 4:32 pm" (o "Todavía no has respaldado").
    var lastBackupSummary: String {
        if let date = lastBackupAt {
            return "Último respaldo: \(BackupDateFormatter.relativeDateTime(for: date))"
        } else {
            return "Todavía no has respaldado"
        }
    }

    /// Mensaje si el último intento falló: el texto del error y que se reintentará solo.
    var failedErrorText: String? {
        guard let detail = failedDetail else { return nil }
        return "\(detail). Se reintentará solo."
    }

    /// Fecha objetivo para restaurar (la fecha de `latestInfo()`).
    var targetRestoreDate: Date? {
        previewLatestBackupDate ?? latestBackupInfo?.createdAt ?? lastBackupAt
    }

    /// Texto base de confirmación de restauración:
    /// "Esto reemplaza lo que hay en este teléfono por tu último respaldo del <fecha>. Lo que no se haya respaldado se pierde."
    var restoreConfirmationDetail: String {
        if let date = targetRestoreDate {
            return "Esto reemplaza lo que hay en este teléfono por tu último respaldo \(BackupDateFormatter.restoreReference(for: date)). Lo que no se haya respaldado se pierde."
        } else {
            return "Esto reemplaza lo que hay en este teléfono por tu último respaldo guardado en el servidor. Lo que no se haya respaldado se pierde."
        }
    }

    /// Mensaje atribuido para el diálogo de confirmación: si `hasUnbackedChanges`, lo dice primero en `.warningText`.
    var restoreConfirmationAttributedString: AttributedString {
        var result = AttributedString()
        if hasUnbackedChanges {
            var warning = AttributedString("Tienes cambios sin respaldar.\n\n")
            warning.foregroundColor = Color.warningText
            result.append(warning)
        }
        result.append(AttributedString(restoreConfirmationDetail))
        return result
    }

    /// Mensaje atribuido para confirmar traer datos del otro respaldo ante un conflicto.
    var bringRemoteConfirmationAttributedString: AttributedString {
        var result = AttributedString()
        if hasUnbackedChanges {
            var warning = AttributedString("Tienes cambios sin respaldar.\n\n")
            warning.foregroundColor = Color.warningText
            result.append(warning)
        }
        let body = "Esto reemplaza lo que hay en este teléfono por el respaldo más nuevo del servidor. Lo que no se haya respaldado se pierde."
        result.append(AttributedString(body))
        return result
    }

    // MARK: Acciones

    /// Carga la información del respaldo más reciente en el servidor.
    func loadLatestInfo() async {
        guard let backupService else { return }
        do {
            latestBackupInfo = try await backupService.latestInfo()
        } catch {
            // Falla no crítica (p. ej. sin conexión); se usa lastBackupAt
        }
    }

    func refresh() async {
        await loadLatestInfo()
    }

    /// Respalda ahora mismo en el servidor.
    func backupNow() async {
        guard let backupService else {
            previewLastError = nil
            previewHasUnbackedChanges = false
            previewLastBackupAt = Date()
            return
        }

        isBackingUp = true
        defer { isBackingUp = false }
        do {
            try await backupService.backupNow(force: false)
            conflictResolvedLocally = false
            await loadLatestInfo()
        } catch {
            // BackupService ya guarda lastError (.conflict o .failed)
        }
    }

    /// Restaura el último respaldo reemplazando los datos locales.
    func restoreLatest() async {
        guard let backupService else {
            conflictResolvedLocally = true
            previewLastError = nil
            previewHasUnbackedChanges = false
            return
        }

        isRestoring = true
        defer { isRestoring = false }
        do {
            let restored = try await backupService.restoreLatest()
            if restored {
                conflictResolvedLocally = true
                await loadLatestInfo()
            } else {
                restoreErrorMessage = "No hay ningún respaldo guardado en el servidor."
            }
        } catch {
            restoreErrorMessage = error.localizedDescription
        }
    }

    /// Resuelve el conflicto usando los datos de este teléfono (force: true).
    func resolveConflictUsingLocal() async {
        guard let backupService else {
            previewLastError = nil
            conflictResolvedLocally = true
            return
        }

        isBackingUp = true
        defer { isBackingUp = false }
        do {
            try await backupService.backupNow(force: true)
            conflictResolvedLocally = false
            await loadLatestInfo()
        } catch {
            // BackupService actualiza lastError si falla
        }
    }

    /// Resuelve el conflicto trayendo los datos del servidor (restoreLatest).
    func resolveConflictRestoringRemote() async {
        await restoreLatest()
    }
}
