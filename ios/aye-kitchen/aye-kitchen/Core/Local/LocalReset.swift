import Foundation
import KitchenDomain

/// "Borrar todos los datos": deja la cuenta como nueva en este teléfono.
///
/// - Datos vacíos (ajustes de fábrica incluidos) e imágenes de referencia borradas.
/// - Vuelve a salir "Tu negocio" (RootView lo muestra en cuanto se borran) y los consejos.
/// - Queda como cambio sin respaldar: el siguiente respaldo sube los datos vacíos, así que restaurar
///   ya no los trae de vuelta. El servidor conserva los últimos 5 respaldos (B11) hasta que se
///   reemplazan; borrar también esos es parte de "Eliminar cuenta", no de esto.
///
/// Hoy el botón vive en la sección de Desarrollo (DEBUG). Para producción basta con mover
/// `SettingsView.eraseDataSection` fuera del `#if DEBUG`: la lógica ya es la definitiva.
enum LocalReset {
    static func eraseAllData(accountId: String) {
        LocalStore.shared.replaceAll(with: KitchenData.empty(deviceId: LocalStore.deviceId), backedUp: false)
        ReferenceStore.shared.deleteAllLocalFiles()
        OnboardingFlags.resetBusinessSetup(accountId: accountId)
        KitchenTips.requestResetOnNextLaunch()
        BackupScheduler.shared.noteChange()
    }
}
