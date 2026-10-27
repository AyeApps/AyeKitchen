import SwiftUI

/// Las 4 secciones de DESIGN.md. Finanzas entrará como quinta.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Inicio", systemImage: "house") {
                HomeView()
            }
            Tab("Pedidos", systemImage: "list.clipboard") {
                OrdersView()
            }
            Tab("Recetas", systemImage: "book.closed") {
                RecipesView()
            }
            Tab("Catálogo", systemImage: "square.grid.2x2") {
                CatalogView()
            }
        }
    }
}
