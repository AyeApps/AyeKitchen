import SwiftUI

/// Decide entre entrar, la preparación de los datos locales, la app o el aviso de sin conexión.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    private var bootstrap: LocalBootstrap { .shared }

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                ProgressView()
                    .controlSize(.large)
            case .signedOut:
                LoginView()
            case .signedIn(let me):
                localContent
                    .task(id: me.id) {
                        await bootstrap.prepare(accountId: me.id)
                    }
            case .unavailable(let message):
                unavailable(title: "No pudimos conectarnos", message: message) {
                    Task { await session.start() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.canvasBackground)
        .task { await session.start() }
        .onChange(of: session.state) { _, newState in
            if case .signedOut = newState {
                LocalStore.shared.close()
                bootstrap.reset()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackupScheduler.shared.appDidEnterBackground()
            }
        }
    }

    @ViewBuilder
    private var localContent: some View {
        switch bootstrap.state {
        case .ready:
            MainTabView()
        case .idle, .downloading:
            VStack(spacing: Spacing.lg) {
                ProgressView()
                    .controlSize(.large)
                Text("Preparando tus datos…")
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)
                Text("La primera vez traemos todo a tu teléfono. Después funciona sin internet.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xxl)
        case .failed(let message):
            unavailable(title: "No pudimos preparar tus datos", message: message) {
                if let me = session.me {
                    Task { await bootstrap.prepare(accountId: me.id) }
                }
            }
        }
    }

    private func unavailable(title: String, message: String, retry: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Intentar de nuevo", action: retry)
                .buttonStyle(.kitchenPrimary)
                .padding(.horizontal, Spacing.xxl)
        }
    }
}
