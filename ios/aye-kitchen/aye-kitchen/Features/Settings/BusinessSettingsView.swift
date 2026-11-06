import SwiftUI
import KitchenDomain

/// Pantalla de ajustes del negocio (Bloque I21).
struct BusinessSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let store: LocalStore

    @State private var name: String
    @State private var marginText: String
    @State private var priceStaleDaysText: String
    @State private var staleDaysValue: Int

    @State private var nameError: String?
    @State private var marginError: String?
    @State private var staleDaysError: String?
    @State private var generalError: String?
    @State private var isSaving = false

    @FocusState private var focusedField: Field?
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 56

    private enum Field: Hashable {
        case name
        case margin
        case staleDays
    }

    init(store: LocalStore = .shared) {
        self.store = store
        let currentSettings = store.data.settings
        self._name = State(initialValue: currentSettings.name)
        self._marginText = State(initialValue: "\(currentSettings.defaultMarginPercent)")
        self._priceStaleDaysText = State(initialValue: "\(currentSettings.priceStaleDays)")
        self._staleDaysValue = State(initialValue: currentSettings.priceStaleDays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                fieldsSection

                if let generalError {
                    Label(generalError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.warningText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                }

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.accentInk)
                    } else {
                        Text("Guardar")
                    }
                }
                .buttonStyle(.kitchenPrimary)
                .disabled(isSaving)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.canvasBackground)
        .navigationTitle("Tu negocio")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Campos de entrada

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            nameField
            marginField
            staleDaysField
            currencyField
        }
    }

    // 1. Nombre del negocio
    private var nameField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Nombre del negocio")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            TextField("", text: $name)
                .font(.body)
                .foregroundStyle(.inkPrimary)
                .focused($focusedField, equals: .name)
                .padding(.horizontal, 18)
                .frame(minHeight: minHeight)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(
                            nameError != nil ? Color.warningText : (focusedField == .name ? Color.accentColor : Color.borderInput),
                            lineWidth: (focusedField == .name || nameError != nil) ? 2 : 1.5
                        )
                }
                .onChange(of: name) { _, _ in
                    nameError = nil
                }

            if let nameError {
                Text(nameError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.warningText)
            }
        }
    }

    // 2. Margen por defecto
    private var marginField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Margen por defecto")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            HStack {
                TextField("", text: $marginText)
                    .keyboardType(.numberPad)
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                    .focused($focusedField, equals: .margin)

                Text("%")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: minHeight)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(
                        marginError != nil ? Color.warningText : (focusedField == .margin ? Color.accentColor : Color.borderInput),
                        lineWidth: (focusedField == .margin || marginError != nil) ? 2 : 1.5
                    )
            }
            .onChange(of: marginText) { _, _ in
                marginError = nil
            }

            Text("Se usa en las recetas que no tienen su propio margen")
                .font(.footnote)
                .foregroundStyle(.inkMuted)

            if let marginError {
                Text(marginError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.warningText)
            }
        }
    }

    // 3. Días para que un precio sea viejo
    private var staleDaysField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Días para considerar un precio viejo")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        TextField("", text: $priceStaleDaysText)
                            .keyboardType(.numberPad)
                            .font(.body)
                            .foregroundStyle(.inkPrimary)
                            .focused($focusedField, equals: .staleDays)

                        Text("días")
                            .font(.body)
                            .foregroundStyle(.inkMuted)
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: minHeight)
                    .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(
                                staleDaysError != nil ? Color.warningText : (focusedField == .staleDays ? Color.accentColor : Color.borderInput),
                                lineWidth: (focusedField == .staleDays || staleDaysError != nil) ? 2 : 1.5
                            )
                    }

                    Stepper("Días: \(staleDaysValue)", value: $staleDaysValue, in: 1...3650)
                        .onChange(of: staleDaysValue) { _, newValue in
                            priceStaleDaysText = "\(newValue)"
                            staleDaysError = nil
                        }
                }
            } else {
                HStack {
                    TextField("", text: $priceStaleDaysText)
                        .keyboardType(.numberPad)
                        .font(.body)
                        .foregroundStyle(.inkPrimary)
                        .focused($focusedField, equals: .staleDays)
                        .onChange(of: priceStaleDaysText) { _, newValue in
                            if let val = Int(newValue) {
                                staleDaysValue = val
                            }
                            staleDaysError = nil
                        }

                    Text("días")
                        .font(.body)
                        .foregroundStyle(.inkMuted)

                    Stepper("", value: $staleDaysValue, in: 1...3650)
                        .labelsHidden()
                        .onChange(of: staleDaysValue) { _, newValue in
                            priceStaleDaysText = "\(newValue)"
                            staleDaysError = nil
                        }
                }
                .padding(.horizontal, 18)
                .frame(minHeight: minHeight)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(
                            staleDaysError != nil ? Color.warningText : (focusedField == .staleDays ? Color.accentColor : Color.borderInput),
                            lineWidth: (focusedField == .staleDays || staleDaysError != nil) ? 2 : 1.5
                        )
                }
            }

            Text("Después de estos días te avisamos que conviene actualizar el precio")
                .font(.footnote)
                .foregroundStyle(.inkMuted)

            if let staleDaysError {
                Text(staleDaysError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.warningText)
            }
        }
    }

    // 4. Moneda (solo lectura por ahora)
    private var currencyField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Moneda")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            HStack {
                Text(store.data.settings.currency)
                    .font(.body)
                    .foregroundStyle(.inkMuted)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(minHeight: minHeight)
            .background(.surfaceInput.opacity(0.6), in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Color.borderInput, lineWidth: 1.5)
            }
        }
    }

    // MARK: - Guardar

    private func save() {
        nameError = nil
        marginError = nil
        staleDaysError = nil
        generalError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            nameError = "El nombre del negocio no puede estar vacío"
            return
        }
        guard trimmedName.count <= 80 else {
            nameError = "El nombre del negocio no puede tener más de 80 caracteres"
            return
        }

        let trimmedMargin = marginText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marginInt = Int(trimmedMargin), (0...1000).contains(marginInt) else {
            marginError = "El margen va de 0 % a 1000 %"
            return
        }

        let trimmedDays = priceStaleDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let daysInt = Int(trimmedDays), (1...3650).contains(daysInt) else {
            staleDaysError = "Los días para considerar un precio viejo van de 1 a 3650"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try store.mutate { data, ctx in
                try data.updateSettings(
                    name: trimmedName,
                    currency: "MXN",
                    defaultMarginPercent: marginInt,
                    priceStaleDays: daysInt,
                    ctx: ctx
                )
            }
            dismiss()
        } catch let domainError as DomainError {
            if case .invalidValue(let detail) = domainError {
                if detail.localizedCaseInsensitiveContains("nombre") {
                    nameError = detail
                } else if detail.localizedCaseInsensitiveContains("margen") {
                    marginError = detail
                } else if detail.localizedCaseInsensitiveContains("días") || detail.localizedCaseInsensitiveContains("precio") {
                    staleDaysError = detail
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

// MARK: - Previews

#if DEBUG
#Preview("Tu negocio - Normal") {
    NavigationStack {
        BusinessSettingsView(store: .preview())
    }
}

#Preview("Tu negocio - Accesibilidad") {
    NavigationStack {
        BusinessSettingsView(store: .preview())
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
