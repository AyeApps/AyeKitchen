import SwiftUI

/// Modo del formulario de ingrediente.
enum IngredientFormMode: Sendable {
    case create
    case edit(Ingredient)

    var title: String {
        switch self {
        case .create: "Nuevo ingrediente"
        case .edit: "Editar ingrediente"
        }
    }
}

/// Equivalencia en edición dentro del formulario.
struct FormConversion: Identifiable, Hashable, Sendable {
    let id: String
    let unitId: String
    let unitName: String
    var quantityText: String
    var isInvalid: Bool = false
}

// MARK: - Cuerpos de petición (docs/api-contract.md)
// Deben ser nonisolated y Sendable según reglas de iOS.

nonisolated struct IngredientConversionInput: Encodable, Sendable {
    let unitId: String
    let quantityInBase: String
}

nonisolated struct IngredientCreateRequest: Encodable, Sendable {
    let name: String
    let baseUnit: BaseUnit
    let group: String?
    let notes: String?
    let conversions: [IngredientConversionInput]

    enum CodingKeys: String, CodingKey {
        case name
        case baseUnit
        case group
        case notes
        case conversions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(baseUnit, forKey: .baseUnit)
        if let group {
            try container.encode(group, forKey: .group)
        } else {
            try container.encodeNil(forKey: .group)
        }
        if let notes {
            try container.encode(notes, forKey: .notes)
        } else {
            try container.encodeNil(forKey: .notes)
        }
        try container.encode(conversions, forKey: .conversions)
    }
}

nonisolated struct IngredientUpdateRequest: Encodable, Sendable {
    let name: String
    let baseUnit: BaseUnit
    let group: String?
    let notes: String?
    let conversions: [IngredientConversionInput]

    enum CodingKeys: String, CodingKey {
        case name
        case baseUnit
        case group
        case notes
        case conversions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(baseUnit, forKey: .baseUnit)
        if let group {
            try container.encode(group, forKey: .group)
        } else {
            try container.encodeNil(forKey: .group)
        }
        if let notes {
            try container.encode(notes, forKey: .notes)
        } else {
            try container.encodeNil(forKey: .notes)
        }
        try container.encode(conversions, forKey: .conversions)
    }
}

// MARK: - ViewModel

@Observable final class IngredientFormModel {
    let mode: IngredientFormMode
    var name: String = ""
    var baseUnit: BaseUnit = .g
    var group: String = ""
    var notes: String = ""
    var conversions: [FormConversion] = []
    var allUnits: [MeasureUnit] = []
    var unitsLoaded: Bool = false
    var isLoadingUnits: Bool = false
    var isSaving: Bool = false
    var errorMessage: String? = nil
    private(set) var isMock: Bool = false

    init(mode: IngredientFormMode, mockUnits: [MeasureUnit]? = nil) {
        self.mode = mode
        if let mockUnits {
            self.allUnits = mockUnits
            self.unitsLoaded = true
            self.isMock = true
        }

        switch mode {
        case .create:
            self.baseUnit = .g
        case .edit(let ingredient):
            self.name = ingredient.name
            self.baseUnit = ingredient.baseUnit
            self.group = ingredient.group ?? ""
            self.notes = ingredient.notes ?? ""
            self.conversions = ingredient.conversions.map {
                FormConversion(
                    id: $0.unitId,
                    unitId: $0.unitId,
                    unitName: $0.unitName,
                    quantityText: Quantity.format($0.quantityInBase),
                    isInvalid: false
                )
            }
        }
    }

    /// Solo unidades con baseUnit distinta a la del ingrediente y que aún no estén agregadas.
    var availableUnits: [MeasureUnit] {
        let usedIds = Set(conversions.map(\.unitId))
        return allUnits.filter { unit in
            unit.baseUnit != baseUnit && !usedIds.contains(unit.id)
        }
    }

    var baseUnitHelpText: String {
        switch baseUnit {
        case .g:
            "Todo se lleva a gramos"
        case .ml:
            "Todo se lleva a mililitros"
        case .pz:
            "Todo se lleva a piezas"
        }
    }

    var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
    }

    func onBaseUnitChanged(to newBaseUnit: BaseUnit) {
        self.baseUnit = newBaseUnit
        // Se descartan equivalencias cuya unidad base ahora coincide con la nueva baseUnit
        let matchingIds = Set(allUnits.filter { $0.baseUnit == newBaseUnit }.map(\.id))
        conversions.removeAll { matchingIds.contains($0.unitId) }
    }

    func loadUnitsIfNeeded() async {
        guard !unitsLoaded && !isMock else { return }
        isLoadingUnits = true
        defer { isLoadingUnits = false }
        do {
            let units: [MeasureUnit] = try await NetworkService.shared.request(.get, "/units/")
            self.allUnits = units
            self.unitsLoaded = true
        } catch {
            // Si falla la carga de unidades, no bloquea el formulario; se podrá reintentar al tocar agregar
        }
    }

    func addConversion(for unit: MeasureUnit) {
        guard !conversions.contains(where: { $0.unitId == unit.id }) else { return }
        conversions.append(
            FormConversion(
                id: unit.id,
                unitId: unit.id,
                unitName: unit.name,
                quantityText: "",
                isInvalid: false
            )
        )
    }

    func removeConversion(id: String) {
        conversions.removeAll { $0.id == id }
    }

    func save() async -> Ingredient? {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        // Validar cada cantidad con Quantity.parse
        var hasInvalidQuantity = false
        for index in conversions.indices {
            if Quantity.parse(conversions[index].quantityText) == nil {
                conversions[index].isInvalid = true
                hasInvalidQuantity = true
            } else {
                conversions[index].isInvalid = false
            }
        }

        if hasInvalidQuantity {
            errorMessage = "Revisa las cantidades marcadas en las equivalencias."
            return nil
        }

        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalGroup: String? = trimmedGroup.isEmpty ? nil : trimmedGroup

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes: String? = trimmedNotes.isEmpty ? nil : trimmedNotes

        let conversionInputs = conversions.compactMap { conv -> IngredientConversionInput? in
            guard let qty = Quantity.parse(conv.quantityText) else { return nil }
            return IngredientConversionInput(unitId: conv.unitId, quantityInBase: qty)
        }

        if isMock {
            let mockId: String
            switch mode {
            case .create: mockId = "mock_\(UUID().uuidString.prefix(6))"
            case .edit(let existing): mockId = existing.id
            }
            return Ingredient(
                id: mockId,
                name: trimmedName,
                baseUnit: baseUnit,
                group: finalGroup,
                notes: finalNotes,
                conversions: conversionInputs.map { input in
                    let name = allUnits.first(where: { $0.id == input.unitId })?.name ?? "unidad"
                    return IngredientConversion(
                        unitId: input.unitId,
                        unitName: name,
                        quantityInBase: input.quantityInBase
                    )
                },
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .create:
                let body = IngredientCreateRequest(
                    name: trimmedName,
                    baseUnit: baseUnit,
                    group: finalGroup,
                    notes: finalNotes,
                    conversions: conversionInputs
                )
                let response: Ingredient = try await NetworkService.shared.request(
                    .post,
                    "/ingredients/",
                    body: body
                )
                return response

            case .edit(let existing):
                let body = IngredientUpdateRequest(
                    name: trimmedName,
                    baseUnit: baseUnit,
                    group: finalGroup,
                    notes: finalNotes,
                    conversions: conversionInputs
                )
                let response: Ingredient = try await NetworkService.shared.request(
                    .patch,
                    "/ingredients/\(existing.id)",
                    body: body
                )
                return response
            }
        } catch let apiError as APIError {
            handleAPIError(apiError)
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func handleAPIError(_ error: APIError) {
        guard let code = error.code else {
            errorMessage = error.localizedDescription
            return
        }

        switch code {
        case "DUPLICATE_NAME":
            errorMessage = "Ya tienes un ingrediente con ese nombre."
        case "IN_USE":
            errorMessage = "No se puede: ya tiene marcas o una receta lo usa con esa medida."
        case "INVALID_REFERENCE":
            errorMessage = "Una de las unidades ya no existe. Vuelve a abrir el formulario."
        default:
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Vista del formulario

struct IngredientFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: IngredientFormModel
    var onSave: ((Ingredient) -> Void)?

    @State private var showingUnitPicker = false

    init(mode: IngredientFormMode, mockUnits: [MeasureUnit]? = nil, onSave: ((Ingredient) -> Void)? = nil) {
        self._model = State(initialValue: IngredientFormModel(mode: mode, mockUnits: mockUnits))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KitchenTextField(label: "Nombre", text: $model.name)
                        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    buyingUnitField
                        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        KitchenTextField(label: "Grupo", text: $model.group)
                        Text("Ejemplo: Lácteos, Harinas…")
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                            .padding(.horizontal, Spacing.xs)
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    notesField
                        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("Equivalencias") {
                    if model.conversions.isEmpty {
                        Text("Aún no agregas equivalencias.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    } else {
                        ForEach($model.conversions) { $conversion in
                            conversionRow(for: $conversion)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        model.removeConversion(id: conversion.id)
                                    } label: {
                                        Label("Quitar", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    Button {
                        showingUnitPicker = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "plus.circle.fill")
                            Text("Agregar equivalencia")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .disabled(model.availableUnits.isEmpty)
                }

                Section {
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.warningText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xs)
                    }

                    Button(model.isSaving ? "Guardando…" : "Guardar") {
                        Task {
                            if let saved = await model.save() {
                                onSave?(saved)
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(model.isSaveDisabled)
                }
                .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.xxl, trailing: Spacing.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.canvasBackground)
            .navigationTitle(model.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingUnitPicker) {
                UnitPickerSheet(units: model.availableUnits) { unit in
                    model.addConversion(for: unit)
                }
            }
            .task {
                await model.loadUnitsIfNeeded()
            }
        }
    }

    // MARK: - Subvistas

    private var buyingUnitField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("¿Cómo lo compras?")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            if dynamicTypeSize.isAccessibilitySize {
                Picker("¿Cómo lo compras?", selection: Binding(
                    get: { model.baseUnit },
                    set: { model.onBaseUnitChanged(to: $0) }
                )) {
                    Text("Peso (g)").tag(BaseUnit.g)
                    Text("Volumen (ml)").tag(BaseUnit.ml)
                    Text("Pieza (pz)").tag(BaseUnit.pz)
                }
                .pickerStyle(.menu)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 48)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(Color.borderInput, lineWidth: 1.5)
                }
            } else {
                Picker("¿Cómo lo compras?", selection: Binding(
                    get: { model.baseUnit },
                    set: { model.onBaseUnitChanged(to: $0) }
                )) {
                    Text("Peso").tag(BaseUnit.g)
                    Text("Volumen").tag(BaseUnit.ml)
                    Text("Pieza").tag(BaseUnit.pz)
                }
                .pickerStyle(.segmented)
            }

            Text(model.baseUnitHelpText)
                .font(.footnote)
                .foregroundStyle(.inkMuted)
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Notas")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            TextField("", text: $model.notes, axis: .vertical)
                .font(.body)
                .foregroundStyle(.inkPrimary)
                .lineLimit(3...6)
                .padding(14)
                .frame(minHeight: 88, alignment: .topLeading)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Color.borderInput, lineWidth: 1.5)
                }
        }
    }

    @ViewBuilder
    private func conversionRow(for conversion: Binding<FormConversion>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("1 \(conversion.wrappedValue.unitName) =")
                    .font(.body)
                    .foregroundStyle(.inkPrimary)

                HStack(spacing: Spacing.xs) {
                    TextField("0", text: conversion.quantityText)
                        .font(.body)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: 44)
                        .background(.surfaceInput, in: .rect(cornerRadius: Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.control)
                                .strokeBorder(
                                    conversion.wrappedValue.isInvalid ? Color.warningText : Color.borderInput,
                                    lineWidth: conversion.wrappedValue.isInvalid ? 2 : 1
                                )
                        }

                    Text(model.baseUnit.rawValue)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.inkPrimary)
                }
            }
            .padding(.vertical, Spacing.xs)
        } else {
            HStack(spacing: Spacing.sm) {
                Text("1 \(conversion.wrappedValue.unitName) =")
                    .font(.body)
                    .foregroundStyle(.inkPrimary)

                Spacer()

                TextField("0", text: conversion.quantityText)
                    .font(.body)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, Spacing.md)
                    .frame(width: 90, height: 44)
                    .background(.surfaceInput, in: .rect(cornerRadius: Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.control)
                            .strokeBorder(
                                conversion.wrappedValue.isInvalid ? Color.warningText : Color.borderInput,
                                lineWidth: conversion.wrappedValue.isInvalid ? 2 : 1
                            )
                    }

                Text(model.baseUnit.rawValue)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.inkPrimary)
            }
            .padding(.vertical, Spacing.xs)
        }
    }
}

// MARK: - Hoja para elegir unidad

struct UnitPickerSheet: View {
    let units: [MeasureUnit]
    let onSelect: (MeasureUnit) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if units.isEmpty {
                    ContentUnavailableView(
                        "No hay más unidades",
                        systemImage: "scalemass",
                        description: Text("Ya agregaste todas las unidades disponibles para este tipo de ingrediente.")
                    )
                } else {
                    List(units) { unit in
                        Button {
                            onSelect(unit)
                            dismiss()
                        } label: {
                            HStack {
                                Text(unit.name)
                                    .font(.body)
                                    .foregroundStyle(.inkPrimary)
                                Spacer()
                                Text(unit.abbreviation)
                                    .font(.subheadline)
                                    .foregroundStyle(.inkMuted)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(.canvasBackground)
            .navigationTitle("Elegir unidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
private let previewUnits: [MeasureUnit] = [
    MeasureUnit(id: "u_tz", name: "taza", abbreviation: "tz", baseUnit: .ml, factorToBase: "240", isSystem: true),
    MeasureUnit(id: "u_cda", name: "cucharada", abbreviation: "cda", baseUnit: .ml, factorToBase: "15", isSystem: true),
    MeasureUnit(id: "u_cdta", name: "cucharadita", abbreviation: "cdta", baseUnit: .ml, factorToBase: "5", isSystem: true),
    MeasureUnit(id: "u_ml", name: "mililitro", abbreviation: "ml", baseUnit: .ml, factorToBase: "1", isSystem: true),
    MeasureUnit(id: "u_pz", name: "pieza", abbreviation: "pz", baseUnit: .pz, factorToBase: "1", isSystem: true)
]

private let previewIngredient = Ingredient(
    id: "ing_preview_1",
    name: "Harina de trigo",
    baseUnit: .g,
    group: "Harinas",
    notes: "Comprar en bulto de 25 kg para mejor precio en la central de abastos.",
    conversions: [
        IngredientConversion(unitId: "u_tz", unitName: "taza", quantityInBase: "125")
    ],
    createdAt: Date(),
    updatedAt: Date()
)

#Preview("Nuevo ingrediente") {
    IngredientFormView(mode: .create, mockUnits: previewUnits)
}

#Preview("Editar ingrediente") {
    IngredientFormView(mode: .edit(previewIngredient), mockUnits: previewUnits)
}

#Preview("Letra AX3") {
    IngredientFormView(mode: .edit(previewIngredient), mockUnits: previewUnits)
        .dynamicTypeSize(.accessibility3)
}
#endif
