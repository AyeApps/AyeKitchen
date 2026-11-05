import SwiftUI
import KitchenDomain

// MARK: - Modos del formulario

enum BrandFormMode: Sendable, Equatable {
    case create(ingredientId: String)
    case edit(presentationId: String)

    var title: String {
        switch self {
        case .create: "Nueva marca"
        case .edit: "Editar marca"
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

// MARK: - Modelo de Formulario

@Observable final class BrandFormModel {
    let mode: BrandFormMode
    private let store: LocalStore

    var brandText: String = ""
    var selectedSupplier: SupplierSelection = .none
    var packageQuantityText: String = "1"
    var selectedUnit: KitchenUnit?
    var priceText: String = ""
    var baseUnit: BaseUnit = .g
    var errorMessage: String?

    var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    init(mode: BrandFormMode, store: LocalStore = .shared) {
        self.mode = mode
        self.store = store

        switch mode {
        case .create(let ingredientId):
            self.brandText = ""
            self.selectedSupplier = .none
            self.packageQuantityText = "1"
            self.priceText = ""
            let ingredient = store.data.ingredients.first(where: { $0.id == ingredientId && $0.isActive })
            self.baseUnit = ingredient?.baseUnit ?? .g

        case .edit(let presentationId):
            if let pres = store.data.presentations.first(where: { $0.id == presentationId && $0.isActive }) {
                self.brandText = pres.brand
                if let supId = pres.supplierId,
                   let sup = store.data.suppliers.first(where: { $0.id == supId && $0.isActive }) {
                    self.selectedSupplier = .existing(id: sup.id, name: sup.name)
                } else {
                    self.selectedSupplier = .none
                }
                self.packageQuantityText = Quantity.format(pres.packageQuantity).replacingOccurrences(of: ",", with: "")
                let ingredient = store.data.ingredients.first(where: { $0.id == pres.ingredientId && $0.isActive })
                self.baseUnit = ingredient?.baseUnit ?? .g
            }
            self.priceText = ""
        }

        selectDefaultUnit()
    }

    var suppliers: [Supplier] {
        store.data.activeSuppliers()
    }

    var availableUnits: [KitchenUnit] {
        store.data.availableKitchenUnits().filter { $0.baseUnit == self.baseUnit }
    }

    private func selectDefaultUnit() {
        if let base = availableUnits.first(where: { $0.factorToBase == "1" }) {
            selectedUnit = base
        } else {
            selectedUnit = availableUnits.first
        }
    }

    var isValid: Bool {
        let brandValid = !brandText.trimmingCharacters(in: .whitespaces).isEmpty
        let quantityValid = Quantity.parse(packageQuantityText) != nil
        let unitValid = selectedUnit != nil
        let priceValid: Bool
        if isCreateMode && !priceText.trimmingCharacters(in: .whitespaces).isEmpty {
            priceValid = RecordPriceModel.parsePriceCents(priceText) != nil
        } else {
            priceValid = true
        }
        return brandValid && quantityValid && unitValid && priceValid
    }

    func createSupplier(name: String) -> Supplier? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            let created = try store.mutate { data, ctx in
                try data.createSupplier(name: trimmed, ctx: ctx)
            }
            selectedSupplier = .existing(id: created.id, name: created.name)
            return created
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func save() -> Presentation? {
        guard isValid, let unit = selectedUnit, let parsedQty = Quantity.parse(packageQuantityText) else {
            return nil
        }
        errorMessage = nil

        let brand = brandText.trimmingCharacters(in: .whitespaces)
        let supplierId = selectedSupplier.supplierId

        do {
            switch mode {
            case .create(let ingredientId):
                let priceCents: Int?
                if !priceText.trimmingCharacters(in: .whitespaces).isEmpty {
                    priceCents = RecordPriceModel.parsePriceCents(priceText)
                } else {
                    priceCents = nil
                }

                let created = try store.mutate { data, ctx in
                    try data.createPresentation(
                        ingredientId: ingredientId,
                        brand: brand,
                        supplierId: supplierId,
                        packageQuantity: parsedQty,
                        packageUnitId: unit.id,
                        barcode: nil,
                        priceCents: priceCents,
                        ctx: ctx
                    )
                }
                return created

            case .edit(let presentationId):
                let updated = try store.mutate { data, ctx in
                    try data.updatePresentation(
                        id: presentationId,
                        brand: brand,
                        supplierId: .some(supplierId),
                        packageQuantity: parsedQty,
                        packageUnitId: unit.id,
                        barcode: nil,
                        ctx: ctx
                    )
                }
                return updated
            }
        } catch let domainError as DomainError {
            if domainError.code == "INVALID_REFERENCE" {
                errorMessage = "Esa tienda o unidad ya no existe. Vuelve a abrir el formulario."
            } else {
                errorMessage = domainError.detail
            }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
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

    var onSave: ((Presentation) -> Void)?

    init(
        mode: BrandFormMode,
        store: LocalStore = .shared,
        onSave: ((Presentation) -> Void)? = nil
    ) {
        self._model = State(initialValue: BrandFormModel(mode: mode, store: store))
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
                        if let saved = model.save() {
                            onSave?(saved)
                            dismiss()
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!model.isValid)
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
                    _ = model.createSupplier(name: newSupplierName)
                    newSupplierName = ""
                }
                Button("Cancelar", role: .cancel) {
                    newSupplierName = ""
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
#Preview("Crear - Claro") {
    BrandFormView(
        mode: .create(ingredientId: "ing-harina"),
        store: .preview()
    )
}

#Preview("Editar - Claro") {
    BrandFormView(
        mode: .edit(presentationId: "pres-selecta"),
        store: .preview()
    )
}

#Preview("Crear - Letra AX3") {
    BrandFormView(
        mode: .create(ingredientId: "ing-harina"),
        store: .preview()
    )
    .dynamicTypeSize(.accessibility3)
}
#endif
