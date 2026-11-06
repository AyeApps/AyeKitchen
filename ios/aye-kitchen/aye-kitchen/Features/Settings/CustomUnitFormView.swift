import SwiftUI
import KitchenDomain

/// Formulario para crear o editar una unidad de medida propia del negocio (Bloque I21).
struct CustomUnitFormView: View {
    @Environment(\.dismiss) private var dismiss

    private let unit: KitchenUnit?
    private let store: LocalStore

    @State private var name: String
    @State private var abbreviation: String
    @State private var baseUnit: BaseUnit
    @State private var factorText: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    @FocusState private var isFactorFocused: Bool
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 56

    init(unit: KitchenUnit? = nil, store: LocalStore = .shared) {
        self.unit = unit
        self.store = store
        if let unit {
            self._name = State(initialValue: unit.name)
            self._abbreviation = State(initialValue: unit.abbreviation)
            self._baseUnit = State(initialValue: unit.baseUnit)
            self._factorText = State(initialValue: Quantity.format(unit.factorToBase))
        } else {
            self._name = State(initialValue: "")
            self._abbreviation = State(initialValue: "")
            self._baseUnit = State(initialValue: .g)
            self._factorText = State(initialValue: "")
        }
    }

    private var isEditing: Bool {
        unit != nil
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbr = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Quantity.parse(factorText)
        return !trimmedName.isEmpty && trimmedName.count <= 50
            && !trimmedAbbr.isEmpty && trimmedAbbr.count <= 12
            && parsed != nil
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    inputFields

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
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
                            Text(isEditing ? "Guardar cambios" : "Guardar unidad")
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!canSave)
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle(isEditing ? "Editar unidad" : "Nueva unidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .font(.body)
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    // MARK: - Campos

    private var inputFields: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            KitchenTextField(
                label: "Nombre",
                text: $name,
                capitalization: .sentences
            )

            KitchenTextField(
                label: "Abreviatura",
                text: $abbreviation,
                capitalization: .never,
                autocorrection: false
            )

            typePicker

            factorField
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tipo de medida")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            Picker("Tipo de medida", selection: $baseUnit) {
                Text("Se pesa").tag(BaseUnit.g)
                Text("Es líquido").tag(BaseUnit.ml)
                Text("Se cuenta").tag(BaseUnit.pz)
            }
            .pickerStyle(.segmented)
        }
    }

    private var factorField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Equivalencia")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            let cleanAbbr = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
            Text("1 \(cleanAbbr.isEmpty ? "unidad" : cleanAbbr) equivale a:")
                .font(.footnote)
                .foregroundStyle(.inkMuted)

            HStack {
                TextField("Ej. 500", text: $factorText)
                    .keyboardType(.decimalPad)
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                    .focused($isFactorFocused)

                Text(baseUnitSuffix)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: minHeight)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(isFactorFocused ? Color.accentColor : Color.borderInput, lineWidth: isFactorFocused ? 2 : 1.5)
            }

            if let parsed = Quantity.parse(factorText) {
                let formatted = Quantity.format(parsed)
                Text("1 \(cleanAbbr.isEmpty ? "unidad" : cleanAbbr) = \(formatted) \(baseUnit.rawValue)")
                    .font(.footnote)
                    .foregroundStyle(.inkSecondary)
            }
        }
    }

    private var baseUnitSuffix: String {
        switch baseUnit {
        case .g: "g"
        case .ml: "ml"
        case .pz: "pz"
        }
    }

    // MARK: - Guardar

    private func save() {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbr = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsedFactor = Quantity.parse(factorText) else {
            errorMessage = "La equivalencia debe ser un número mayor a cero"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if let existing = unit {
                try store.mutate { data, ctx in
                    try data.updateUnit(
                        id: existing.id,
                        name: trimmedName,
                        abbreviation: trimmedAbbr,
                        baseUnit: baseUnit,
                        factorToBase: parsedFactor,
                        ctx: ctx
                    )
                }
            } else {
                try store.mutate { data, ctx in
                    try data.createUnit(
                        name: trimmedName,
                        abbreviation: trimmedAbbr,
                        baseUnit: baseUnit,
                        factorToBase: parsedFactor,
                        ctx: ctx
                    )
                }
            }
            dismiss()
        } catch let domainError as DomainError {
            switch domainError {
            case .duplicateName:
                errorMessage = "Ya existe una unidad con ese nombre o abreviatura."
            case .inUse(let detail):
                errorMessage = "No se puede cambiar el tipo de medida porque esta unidad ya está en uso en ingredientes o recetas: \(detail)"
            case .invalidValue(let detail):
                errorMessage = detail
            default:
                errorMessage = domainError.detail
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Crear unidad - Normal") {
    CustomUnitFormView(store: .preview())
}

#Preview("Crear unidad - Accesibilidad") {
    CustomUnitFormView(store: .preview())
        .dynamicTypeSize(.accessibility3)
}

#Preview("Editar unidad - Normal") {
    let sampleUnit = KitchenUnit(
        id: "unit-preview",
        name: "Bolsa chica",
        abbreviation: "bolsa",
        baseUnit: .g,
        factorToBase: "500",
        createdAt: Date(),
        updatedAt: Date()
    )
    return CustomUnitFormView(unit: sampleUnit, store: .preview())
}
#endif
