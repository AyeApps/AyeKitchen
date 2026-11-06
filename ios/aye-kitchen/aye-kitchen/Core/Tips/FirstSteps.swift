import Foundation
import KitchenDomain

/// "Primeros pasos" de Inicio (bloque I24). Los pasos se palomean solos con los datos del negocio;
/// solo "Finanzas" se recuerda con una bandera (abrir la pestaña o registrar un gasto).
/// Los textos los aprobó el usuario (2026-11-06).
enum FirstSteps {
    struct Step: Identifiable, Hashable {
        let id: String
        let title: String
        let isDone: Bool
        /// A dónde lleva al tocarlo.
        let tab: AppTab
    }

    static func steps(for data: KitchenData) -> [Step] {
        let pricedPresentationIds = Set(data.priceRecords.filter(\.isActive).map(\.presentationId))
        let hasPricedBrand = data.presentations.contains { $0.isActive && pricedPresentationIds.contains($0.id) }
        let hasRecipe = data.recipes.contains(where: \.isActive)
        let hasOrder = data.orders.contains(where: \.isActive)
        let financeDone = financeVisited || data.expenses.contains(where: \.isActive)
        return [
            Step(id: "ingredient", title: "Agrega un ingrediente con su marca y precio", isDone: hasPricedBrand, tab: .catalog),
            Step(id: "recipe", title: "Arma tu primera receta", isDone: hasRecipe, tab: .recipes),
            Step(id: "order", title: "Registra tu primer pedido", isDone: hasOrder, tab: .orders),
            Step(id: "finance", title: "Revisa cuánto te queda en Finanzas", isDone: financeDone, tab: .finance),
        ]
    }

    /// La tarjeta se muestra si falta algún paso y la persona no la cerró.
    static func shouldShow(for data: KitchenData) -> Bool {
        !dismissed && steps(for: data).contains { !$0.isDone }
    }

    /// "Cerrar" en la tarjeta.
    static func dismiss() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    /// Llamar al abrir la pestaña Finanzas.
    static func markFinanceVisited() {
        UserDefaults.standard.set(true, forKey: financeKey)
    }

    private static let dismissedKey = "FirstSteps.dismissed"
    private static let financeKey = "FirstSteps.financeVisited"
    private static var dismissed: Bool { UserDefaults.standard.bool(forKey: dismissedKey) }
    private static var financeVisited: Bool { UserDefaults.standard.bool(forKey: financeKey) }
}
