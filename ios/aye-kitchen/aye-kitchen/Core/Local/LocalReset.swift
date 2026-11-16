import Foundation
import Observation
import KitchenDomain

/// Reinicio en vivo de la app. `RootView` le pone `.id(generation)` al contenido, así que al
/// cambiar se descarta todo (pestañas, pantallas abiertas, hojas, modelos) y se arma de cero,
/// como si se abriera la app por primera vez.
@Observable
final class AppReset {
    static let shared = AppReset()
    private(set) var generation = 0
    private init() {}

    func restart() {
        AppRouter.shared.selectedTab = .home
        generation += 1
    }
}

/// "Borrar todos los datos": deja la cuenta como nueva en este teléfono.
///
/// - Datos vacíos (ajustes de fábrica incluidos) e imágenes de referencia borradas.
/// - La app se reinicia en vivo (`AppReset`) y se repite el onboarding completo: bienvenida,
///   "Tu negocio", "Primeros pasos" en Inicio y los consejos. TipKit solo se puede reiniciar antes
///   de configurarse, así que los consejos vuelven la próxima vez que se abra la app.
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
        OnboardingFlags.resetWelcome()
        FirstSteps.reset()
        KitchenTips.requestResetOnNextLaunch()
        BackupScheduler.shared.noteChange()
        AppReset.shared.restart()
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
