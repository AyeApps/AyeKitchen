import SwiftUI

/// Decide entre entrar, la app o el aviso de sin conexión, según la sesión.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                ProgressView()
                    .controlSize(.large)
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            case .unavailable(let message):
                ContentUnavailableView {
                    Label("No pudimos conectarnos", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Intentar de nuevo") {
                        Task { await session.start() }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .padding(.horizontal, Spacing.xxl)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.canvasBackground)
        .task { await session.start() }
    }
}
