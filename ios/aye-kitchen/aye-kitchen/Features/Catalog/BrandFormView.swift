import SwiftUI

// MARK: - Modos del formulario

enum BrandFormMode: Sendable {
    case create(ingredient: Ingredient)
    case edit(presentation: Presentation)

    var title: String {
        switch self {
        case .create: "Nueva marca"
        case .edit: "Editar marca"
        }
    }

    var baseUnit: BaseUnit {
        switch self {
        case .create(let ingredient): ingredient.baseUnit
        case .edit(let presentation): presentation.baseUnit
        }
    }

    var ingredientId: String {
        switch self {
        case .create(let ingredient): ingredient.id
        case .edit(let presentation): presentation.ingredientId
        }
    }
}

// MARK: - Selección de Tienda

enum SupplierSelection: Hashable {
    case none
    case existing(id: String, name: String)

    var displayName: String {
        switch self {
        case .none: "Sin tienda"
        case .existing(_, let name): name
        }
    }

    var supplierId: String? {
        switch self {
        case .none: nil
        case .existing(let id, _): id
        }
    }
}

// MARK: - Cuerpos de petición (docs/api-contract.md)

nonisolated struct PresentationCreateRequest: Encodable, Sendable {
    let ingredientId: String
    let brand: String
    let supplierId: String?
    let packageQuantity: String
    let packageUnitId: String?
    let priceCents: Int?

    enum CodingKeys: String, CodingKey {
        case ingredientId
        case brand
        case supplierId
        case packageQuantity
        case packageUnitId
        case priceCents
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ingredientId, forKey: .ingredientId)
        try container.encode(brand, forKey: .brand)
        if let supplierId {
            try container.encode(supplierId, forKey: .supplierId)
        } else {
            try container.encodeNil(forKey: .supplierId)
        }
        try container.encode(packageQuantity, forKey: .packageQuantity)
        if let packageUnitId {
            try container.encode(packageUnitId, forKey: .packageUnitId)
        } else {
            try container.encodeNil(forKey: .packageUnitId)
        }
        if let priceCents {
            try container.encode(priceCents, forKey: .priceCents)
        } else {
            try container.encodeNil(forKey: .priceCents)
        }
    }
}

nonisolated struct PresentationUpdateRequest: Encodable, Sendable {
    let brand: String
    let supplierId: String?
    let packageQuantity: String
    let packageUnitId: String?

    enum CodingKeys: String, CodingKey {
        case brand
        case supplierId
        case packageQuantity
        case packageUnitId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(brand, forKey: .brand)
        if let supplierId {
            try container.encode(supplierId, forKey: .supplierId)
        } else {
            try container.encodeNil(forKey: .supplierId)
        }
        try container.encode(packageQuantity, forKey: .packageQuantity)
        if let packageUnitId {
            try container.encode(packageUnitId, forKey: .packageUnitId)
        } else {
            try container.encodeNil(forKey: .packageUnitId)
        }
    }
}

// MARK: - Modelo de Formulario

@Observable final class BrandFormModel: @unchecked Sendable {
    let mode: BrandFormMode

    var brandText: String = ""
    var selectedSupplier: SupplierSelection = .none
    var packageQuantityText: String = "1"
    var selectedUnit: MeasureUnit?
    var priceText: String = ""

    var suppliers: [Supplier] = []
    var availableUnits: [MeasureUnit] = []
    var isLoadingOptions = false
    var isSaving = false
    var errorMessage: String?

    var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    init(
        mode: BrandFormMode,
        mockSuppliers: [Supplier]? = nil,
        mockUnits: [MeasureUnit]? = nil
    ) {
        self.mode = mode

        switch mode {
        case .create:
            self.brandText = ""
            self.selectedSupplier = .none
            self.packageQuantityText = "1"
            self.priceText = ""
        case .edit(let pres):
            self.brandText = pres.brand
            if let supId = pres.supplierId, let supName = pres.supplierName {
                self.selectedSupplier = .existing(id: supId, name: supName)
            } else {
                self.selectedSupplier = .none
            }
            self.packageQuantityText = Quantity.format(pres.packageQuantity).replacingOccurrences(of: ",", with: "")
            self.priceText = ""
        }

        if let mockSuppliers {
            self.suppliers = mockSuppliers
        }
        if let mockUnits {
            self.availableUnits = mockUnits.filter { $0.baseUnit == mode.baseUnit }
            self.selectDefaultUnit()
        }
    }

    var isValid: Bool {
        let brandValid = !brandText.trimmingCharacters(in: .whitespaces).isEmpty
        let quantityValid = Quantity.parse(packageQuantityText) != nil
        let unitValid = selectedUnit != nil
        let priceValid: Bool
        if isCreateMode && !priceText.trimmingCharacters(in: .whitespaces).isEmpty {
            priceValid = Self.parsePriceCents(priceText) != nil
        } else {
            priceValid = true
        }
        return brandValid && quantityValid && unitValid && priceValid
    }

    func loadOptions() async {
        isLoadingOptions = true
        errorMessage = nil
        do {
            async let suppliersTask: [Supplier] = NetworkService.shared.request(.get, "/suppliers/")
            async let unitsTask: [MeasureUnit] = NetworkService.shared.request(.get, "/units/")

            let (fetchedSuppliers, fetchedUnits) = try await (suppliersTask, unitsTask)
            self.suppliers = fetchedSuppliers
            self.availableUnits = fetchedUnits.filter { $0.baseUnit == self.mode.baseUnit }
            selectDefaultUnit()
            self.isLoadingOptions = false
        } catch {
            self.isLoadingOptions = false
            self.errorMessage = mapError(error)
        }
    }

    private func selectDefaultUnit() {
        if selectedUnit == nil {
            // Prefer base unit factor 1
            if let base = availableUnits.first(where: { $0.factorToBase == "1" }) {
                selectedUnit = base
            } else {
                selectedUnit = availableUnits.first
            }
        }
    }

    func createSupplier(name: String) async -> Supplier? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            let body = SupplierCreateRequest(name: trimmed, notes: nil)
            let created: Supplier = try await NetworkService.shared.request(.post, "/suppliers/", body: body)
            suppliers.append(created)
            suppliers.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            selectedSupplier = .existing(id: created.id, name: created.name)
            return created
        } catch {
            errorMessage = mapError(error)
            return nil
        }
    }

    func save() async -> Presentation? {
        guard isValid, let unit = selectedUnit, let parsedQty = Quantity.parse(packageQuantityText) else {
            return nil
        }
        isSaving = true
        errorMessage = nil

        let brand = brandText.trimmingCharacters(in: .whitespaces)
        let supplierId = selectedSupplier.supplierId

        do {
            switch mode {
            case .create(let ingredient):
                let priceCents: Int?
                if !priceText.trimmingCharacters(in: .whitespaces).isEmpty {
                    priceCents = Self.parsePriceCents(priceText)
                } else {
                    priceCents = nil
                }

                let body = PresentationCreateRequest(
                    ingredientId: ingredient.id,
                    brand: brand,
                    supplierId: supplierId,
                    packageQuantity: parsedQty,
                    packageUnitId: unit.id,
                    priceCents: priceCents
                )

                let created: Presentation = try await NetworkService.shared.request(.post, "/presentations/", body: body)
                isSaving = false
                return created

            case .edit(let presentation):
                let body = PresentationUpdateRequest(
                    brand: brand,
                    supplierId: supplierId,
                    packageQuantity: parsedQty,
                    packageUnitId: unit.id
                )

                let updated: Presentation = try await NetworkService.shared.request(.patch, "/presentations/\(presentation.id)", body: body)
                isSaving = false
                return updated
            }
        } catch {
            isSaving = false
            errorMessage = mapError(error)
            return nil
        }
    }

    func mapError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.code == "INVALID_REFERENCE" {
                return "Esa tienda o unidad ya no existe. Vuelve a abrir el formulario."
            }
            if apiError.code == "UNIT_NOT_CONVERTIBLE" {
                return apiError.errorDescription ?? apiError.localizedDescription
            }
            return apiError.localizedDescription
        }
        return error.localizedDescription
    }

    static func parsePriceCents(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0 else {
            return nil
        }
        var centsDecimal = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &centsDecimal, 0, .plain)
        return (rounded as NSDecimalNumber).intValue
    }
}

// MARK: - Vista de Formulario de Marca

/// Formulario para crear o editar marcas (presentaciones) de un ingrediente.
struct BrandFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: BrandFormModel
    @State private var showingNewSupplierAlert = false
    @State private var newSupplierName = ""

    let onSave: (Presentation) -> Void

    init(
        mode: BrandFormMode,
        mockSuppliers: [Supplier]? = nil,
        mockUnits: [MeasureUnit]? = nil,
        onSave: @escaping (Presentation) -> Void
    ) {
        self._model = State(initialValue: BrandFormModel(
            mode: mode,
            mockSuppliers: mockSuppliers,
            mockUnits: mockUnits
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    brandField
                    storePickerField
                    packageSizeField
                    if model.isCreateMode {
                        priceField
                    }

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.warningText)
                            .padding(.horizontal, Spacing.xs)
                    }

                    Spacer(minLength: Spacing.lg)

                    Button("Guardar marca") {
                        Task {
                            if let saved = await model.save() {
                                onSave(saved)
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!model.isValid || model.isSaving)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }
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
            .alert("Nueva tienda", isPresented: $showingNewSupplierAlert) {
                TextField("Nombre de la tienda", text: $newSupplierName)
                Button("Guardar") {
                    Task {
                        _ = await model.createSupplier(name: newSupplierName)
                        newSupplierName = ""
                    }
                }
                Button("Cancelar", role: .cancel) {
                    newSupplierName = ""
                }
            }
            .task {
                if model.availableUnits.isEmpty {
                    await model.loadOptions()
                }
            }
        }
    }

    private var brandField: some View {
        KitchenTextField(
            label: "Marca",
            text: $model.brandText
        )
    }

    private var storePickerField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tienda")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            Menu {
                Button("Sin tienda") {
                    model.selectedSupplier = .none
                }
                ForEach(model.suppliers) { supplier in
                    Button(supplier.name) {
                        model.selectedSupplier = .existing(id: supplier.id, name: supplier.name)
                    }
                }
                Divider()
                Button("Nueva tienda…") {
                    newSupplierName = ""
                    showingNewSupplierAlert = true
                }
            } label: {
                HStack {
                    Text(model.selectedSupplier.displayName)
                        .font(.body)
                        .foregroundStyle(.inkPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 56)
                .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(.borderInput, lineWidth: 1.5)
                }
            }
            .accessibilityLabel("Tienda: \(model.selectedSupplier.displayName)")
        }
    }

    private var packageSizeField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tamaño del paquete")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkPrimary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.sm) {
                    quantityInput
                    unitMenu
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    quantityInput
                    unitMenu
                        .frame(minWidth: 100)
                }
            }
        }
    }

    private var quantityInput: some View {
        TextField("1", text: $model.packageQuantityText)
            .keyboardType(.decimalPad)
            .font(.body)
            .foregroundStyle(.inkPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.borderInput, lineWidth: 1.5)
            }
            .accessibilityLabel("Cantidad del paquete")
    }

    private var unitMenu: some View {
        Menu {
            ForEach(model.availableUnits) { unit in
                Button("\(unit.name) (\(unit.abbreviation))") {
                    model.selectedUnit = unit
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(model.selectedUnit?.abbreviation ?? "Unidad")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.inkPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(.surfaceInput, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.borderInput, lineWidth: 1.5)
            }
        }
        .accessibilityLabel("Unidad: \(model.selectedUnit?.abbreviation ?? "")")
    }

    private var priceField: some View {
        KitchenTextField(
            label: "Precio (opcional)",
            text: $model.priceText,
            keyboard: .decimalPad
        )
    }
}

// MARK: - Previews

#if DEBUG
private let mockIngredientPreview = Ingredient(
    id: "ing_prev",
    name: "Harina de trigo",
    baseUnit: .g,
    group: "Harinas",
    notes: nil,
    conversions: [],
    createdAt: Date(),
    updatedAt: Date()
)

private let mockPresentationPreview = Presentation(
    id: "pres_prev",
    ingredientId: "ing_prev",
    ingredientName: "Harina de trigo",
    brand: "Selecta",
    supplierId: "sup_1",
    supplierName: "Walmart",
    packageQuantity: "1000",
    baseUnit: .g,
    barcode: nil,
    latestPriceCents: 2350,
    latestPriceAt: Date(),
    costPerBaseUnit: "2.350000",
    isCurrent: true,
    priceAgeDays: 0,
    priceIsStale: false,
    createdAt: Date(),
    updatedAt: Date()
)

private let mockSuppliersPreview: [Supplier] = [
    Supplier(id: "sup_1", name: "Walmart", notes: nil, createdAt: Date(), updatedAt: Date()),
    Supplier(id: "sup_2", name: "Costco", notes: nil, createdAt: Date(), updatedAt: Date())
]

private let mockUnitsPreview: [MeasureUnit] = [
    MeasureUnit(id: "u_g", name: "gramo", abbreviation: "g", baseUnit: .g, factorToBase: "1", isSystem: true),
    MeasureUnit(id: "u_kg", name: "kilogramo", abbreviation: "kg", baseUnit: .g, factorToBase: "1000", isSystem: true),
    MeasureUnit(id: "u_lb", name: "libra", abbreviation: "lb", baseUnit: .g, factorToBase: "453.592", isSystem: true),
    MeasureUnit(id: "u_oz", name: "onza", abbreviation: "oz", baseUnit: .g, factorToBase: "28.3495", isSystem: true)
]

#Preview("Crear - Claro") {
    BrandFormView(
        mode: .create(ingredient: mockIngredientPreview),
        mockSuppliers: mockSuppliersPreview,
        mockUnits: mockUnitsPreview,
        onSave: { _ in }
    )
}

#Preview("Editar - Claro") {
    BrandFormView(
        mode: .edit(presentation: mockPresentationPreview),
        mockSuppliers: mockSuppliersPreview,
        mockUnits: mockUnitsPreview,
        onSave: { _ in }
    )
}

#Preview("Crear - Letra AX3") {
    BrandFormView(
        mode: .create(ingredient: mockIngredientPreview),
        mockSuppliers: mockSuppliersPreview,
        mockUnits: mockUnitsPreview,
        onSave: { _ in }
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
