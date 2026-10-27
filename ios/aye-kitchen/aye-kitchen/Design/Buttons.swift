import SwiftUI

/// Botón principal: relleno naranja, texto `accentInk`. Uno por pantalla, al final de la hoja o del formulario.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .multilineTextAlignment(.center)
            .foregroundStyle(.accentInk)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, Spacing.lg)
            .background(.accentFill, in: .rect(cornerRadius: Radius.primaryButton))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

/// Botón secundario: fondo de tarjeta con borde.
struct SecondaryButtonStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.inkPrimary)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, Spacing.lg)
            .background(.surfaceCard, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.borderInput, lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var kitchenPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var kitchenSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// El "+" de la barra de navegación para la acción global de la pantalla. Nunca un botón flotante.
struct AddToolbarButton: View {
    let label: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 34

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(.accentInk)
                .frame(width: size, height: size)
                .background(.accentFill, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
