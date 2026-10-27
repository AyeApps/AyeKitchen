import SwiftUI

/// Pantalla de error con reintento, para cuando una carga falla.
struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No se pudo cargar", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Intentar de nuevo", action: retry)
                .buttonStyle(.kitchenSecondary)
                .padding(.horizontal, Spacing.xxl)
        }
    }
}
