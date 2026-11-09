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
/// El botón es `SettingsView.eraseDataSection` ("Borrar mis datos de AyeKitchen" en Ajustes).
enum LocalReset {
    static func eraseAllData(accountId: String) {
        LocalStore.shared.replaceAll(with: KitchenData.empty(deviceId: LocalStore.deviceId), backedUp: false)
        ReferenceStore.shared.deleteAllLocalFiles()
        OnboardingFlags.resetBusinessSetup(accountId: accountId)
        KitchenTips.requestResetOnNextLaunch()
        BackupScheduler.shared.noteChange()
    }

    /// Después de eliminar la cuenta: no queda nada de ella en el teléfono (datos, fotos, marcas).
    /// La carpeta de imágenes vive dentro de la de la cuenta, así que se va con ella.
    /// Luego hay que llamar `SessionStore.signOut()` para volver a Entrar.
    static func forgetAccountOnThisPhone(accountId: String) {
        ReferenceStore.shared.deleteAllLocalFiles()
        ReferenceStore.shared.close()
        LocalStore.shared.discardAccount()
        OnboardingFlags.resetBusinessSetup(accountId: accountId)
    }
}
