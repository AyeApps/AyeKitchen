import Observation
import SwiftUI

/// Las pestañas de la app.
enum AppTab: Hashable {
    case home, orders, recipes, catalog, finance
}

/// Pestaña elegida, para cambiarla desde código (por ejemplo, "Primeros pasos" en Inicio):
/// `AppRouter.shared.selectedTab = .catalog`.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var selectedTab: AppTab = .home
    private init() {}
}

/// Las 5 secciones: Inicio, Pedidos, Recetas, Catálogo y Finanzas.
struct MainTabView: View {
    @Bindable private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Inicio", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Pedidos", systemImage: "list.clipboard", value: AppTab.orders) {
                OrdersView()
            }
            Tab("Recetas", systemImage: "book.closed", value: AppTab.recipes) {
                RecipesView()
            }
            Tab("Catálogo", systemImage: "square.grid.2x2", value: AppTab.catalog) {
                CatalogView()
            }
            Tab("Finanzas", systemImage: "chart.bar", value: AppTab.finance) {
                FinanceView()
            }
        }
    }
}
