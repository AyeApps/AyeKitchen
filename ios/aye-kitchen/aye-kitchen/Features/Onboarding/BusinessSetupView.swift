import KitchenDomain
import SwiftUI

/// "Tu negocio" la primera vez que entra una cuenta nueva (Bloque I28).
/// Permite capturar el nombre del negocio y su margen por defecto antes de iniciar.
struct BusinessSetupView: View {
    let store: LocalStore
    /// Llamar después de guardar o al tocar "Ahora no": `RootView` la marca como hecha y abre la app.
    let onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var name = ""
    @State private var selectedMargin = 40
    @State private var nameError: String?
    @State private var generalError: String?
    @State private var isSaving = false

    private let marginOptions = [30, 40, 50, 60]

    private var suggestedPriceFor100: Int {
        let cost = 100
        return cost * (100 + selectedMargin) / 100
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                header
                nameSection
                marginSection

                if let generalError {
                    Label(generalError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.warningText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                }

                actionsSection
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.canvasBackground)
    }

    // MARK: - Encabezado

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Cuéntanos de tu negocio")
                .font(.title.weight(.heavy))
                .foregroundStyle(.inkPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Lo puedes cambiar cuando quieras en Cuenta y ajustes.")
                .font(.body)
                .foregroundStyle(.inkMuted)
        }
    }

    // MARK: - Nombre

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            KitchenTextField(
                label: "¿Cómo se llama tu negocio?",
                text: $name,
                capitalization: .words
            )
            .onChange(of: name) { _, _ in
                nameError = nil
            }

            if let nameError {
                Text(nameError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.warningText)
            }

            Text("Por ejemplo: Pasteles de Ana")
                .font(.footnote)
                .foregroundStyle(.inkMuted)
        }
    }

    // MARK: - Margen

    private var marginSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("¿Cuánto quieres ganar?")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.sm) {
                    ForEach(marginOptions, id: \.self) { option in
                        marginChip(option)
                    }
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    ForEach(marginOptions, id: \.self) { option in
                        marginChip(option)
                    }
                }
            }

            Text("Si una receta te cuesta $100, te sugerimos cobrar $\(suggestedPriceFor100).")
                .font(.footnote)
                .foregroundStyle(.inkMuted)
        }
    }

    private func marginChip(_ option: Int) -> some View {
        let isSelected = selectedMargin == option
        return Button {
            selectedMargin = option
        } label: {
            Text("\(option) %")
                .font(.subheadline.weight(isSelected ? .heavy : .bold))
                .foregroundStyle(isSelected ? Color.accentTextDeep : Color.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, Spacing.sm)
                .background(
                    isSelected ? Color.accentSoftStrong : Color.neutralSoft,
                    in: .capsule
                )
                .overlay {
                    if isSelected {
                        Capsule()
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option) por ciento")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Acciones

    private var actionsSection: some View {
        VStack(spacing: Spacing.md) {
            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.accentInk)
                } else {
                    Text("Continuar")
                }
            }
            .buttonStyle(.kitchenPrimary)
            .disabled(isSaving)

            Button("Ahora no") {
                onFinish()
            }
            .font(.body.weight(.bold))
            .foregroundStyle(.tint)
            .frame(minHeight: 44)
            .disabled(isSaving)
        }
    }

    // MARK: - Guardado

    private func save() {
        // Cierra el teclado al tocar Continuar
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        nameError = nil
        generalError = nil

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameToSave: String? = trimmed.isEmpty ? nil : trimmed

        isSaving = true
        defer { isSaving = false }

        do {
            try store.mutate { data, ctx in
                try data.updateSettings(
                    name: nameToSave,
                    defaultMarginPercent: selectedMargin,
                    ctx: ctx
                )
            }
            onFinish()
        } catch let domainError as DomainError {
            if case .invalidValue(let detail) = domainError {
                if detail.localizedCaseInsensitiveContains("nombre") {
                    nameError = detail
                } else {
                    generalError = detail
                }
            } else {
                generalError = domainError.detail
            }
        } catch {
            generalError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Normal") {
    BusinessSetupView(
        store: .preview(KitchenData.empty(deviceId: "preview")),
        onFinish: {}
    )
}

#Preview("Accesibilidad AX3") {
    BusinessSetupView(
        store: .preview(KitchenData.empty(deviceId: "preview")),
        onFinish: {}
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Modo oscuro") {
    BusinessSetupView(
        store: .preview(KitchenData.empty(deviceId: "preview")),
        onFinish: {}
    )
    .preferredColorScheme(.dark)
}
#endif
