import SwiftUI

/// Campo con la etiqueta visible arriba, fondo `surfaceInput` y borde que se vuelve naranja al enfocar.
struct KitchenTextField: View {
    let label: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrection = true

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)
                .accessibilityHidden(true)

            field
                .font(.body)
                .foregroundStyle(.inkPrimary)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(!autocorrection)
                .focused($isFocused)
                .padding(.horizontal, 18)
                .frame(minHeight: minHeight)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(isFocused ? Color.accentColor : Color.borderInput, lineWidth: isFocused ? 2 : 1.5)
                }
                .accessibilityLabel(label)
        }
    }

    @ViewBuilder private var field: some View {
        if isSecure {
            SecureField("", text: $text)
        } else {
            TextField("", text: $text)
        }
    }
}
