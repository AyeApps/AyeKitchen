import KitchenDomain
import SwiftUI

/// "Tu negocio" la primera vez que entra una cuenta nueva (Bloque I28). ESQUELETO de Claude: agy
/// llena el diseño según `docs/agy/I28-onboarding.md`. No cambies la firma: `RootView` la usa así.
struct BusinessSetupView: View {
    let store: LocalStore
    /// Llamar después de guardar o al tocar "Ahora no": `RootView` la marca como hecha y abre la app.
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Tu negocio")
                .font(.title.bold())
            Button("Continuar", action: onFinish)
                .buttonStyle(.kitchenPrimary)
        }
        .padding(Spacing.xxl)
    }
}

#if DEBUG
#Preview {
    BusinessSetupView(store: .preview(KitchenData.empty(deviceId: "preview")), onFinish: {})
}
#endif
