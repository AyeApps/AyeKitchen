import SwiftUI

/// Bienvenida antes de Entrar (Bloque I28). ESQUELETO de Claude: agy llena el diseño según
/// `docs/agy/I28-onboarding.md`. No cambies la firma: `RootView` la usa así.
struct WelcomeView: View {
    /// Llamar al terminar o al tocar "Saltar": `RootView` marca la bienvenida como vista y muestra Entrar.
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Bienvenida")
                .font(.title.bold())
            Button("Empezar", action: onFinish)
                .buttonStyle(.kitchenPrimary)
        }
        .padding(Spacing.xxl)
    }
}

#if DEBUG
#Preview {
    WelcomeView(onFinish: {})
}
#endif
