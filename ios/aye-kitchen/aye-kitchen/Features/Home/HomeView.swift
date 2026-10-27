import SwiftUI

/// Inicio (artboard "Inicio — iPhone"). No muestra dinero: eso es de Finanzas.
/// Pendiente (agy): "Lo que sigue", "Esta semana" y "Recetas por revisar".
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var showingNewOrder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    header

                    ContentUnavailableView(
                        "Aquí verás tus entregas",
                        systemImage: "calendar",
                        description: Text("Lo que sigue y los pedidos de la semana.")
                    )
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
            .background(.canvasBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AddToolbarButton(label: "Nuevo pedido") { showingNewOrder = true }
                }
            }
            .sheet(isPresented: $showingNewOrder) {
                ComingSoonSheet(title: "Nuevo pedido")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_MX"))).capitalized(with: Locale(identifier: "es_MX")))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.inkMuted)
            Text("Hola, \(session.me?.firstName ?? "")")
                .font(.largeTitle.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Cuenta y cerrar sesión.
private struct AccountMenu: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Menu {
            if let me = session.me {
                Text(me.email)
            }
            Button("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await session.signOut() }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.title3)
        }
        .accessibilityLabel("Tu cuenta")
    }
}
