import Foundation
import KitchenDomain

/// Cuándo se muestra el onboarding (Bloque I28). Lo mantiene Claude; las pantallas viven en
/// `Features/Onboarding/`.
///
/// - Bienvenida: una vez por instalación, antes de Entrar.
/// - "Tu negocio": una vez por cuenta, solo si la cuenta llega vacía (nueva). Una cuenta que ya
///   trae datos (restaurada o migrada) no la ve y queda marcada al llegar a la app.
enum OnboardingFlags {
    /// Clave de `@AppStorage` para la bienvenida.
    static let welcomeSeenKey = "onboarding.welcomeSeen"

    private static func setupKey(_ accountId: String) -> String {
        "onboarding.businessSetupDone.\(accountId)"
    }

    static func isBusinessSetupDone(accountId: String) -> Bool {
        UserDefaults.standard.bool(forKey: setupKey(accountId))
    }

    static func markBusinessSetupDone(accountId: String) {
        UserDefaults.standard.set(true, forKey: setupKey(accountId))
    }

    /// Al borrar todos los datos, la cuenta vuelve a ver "Tu negocio".
    static func resetBusinessSetup(accountId: String) {
        UserDefaults.standard.removeObject(forKey: setupKey(accountId))
    }

    /// Cuenta nueva: sin nada capturado y con el nombre de fábrica.
    static func looksNew(_ data: KitchenData) -> Bool {
        data.settings.name == KitchenSettings().name
            && data.ingredients.isEmpty
            && data.presentations.isEmpty
            && data.recipes.isEmpty
            && data.customers.isEmpty
            && data.orders.isEmpty
            && data.expenses.isEmpty
    }
}
