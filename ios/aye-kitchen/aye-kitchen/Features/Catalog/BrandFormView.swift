import SwiftUI
import TipKit
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

// MARK: - Modelo de Formulario

@Observable final class BrandFormModel {
    let mode: BrandFormMode
    let store: LocalStore

    var brandText: String = ""
    var selectedSupplier: SupplierSelection = .none
    var packageSize: PackageSizeInput
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
            self.priceText = ""
            let ingredient = store.data.ingredients.first(where: { $0.id == ingredientId && $0.isActive })
            let bUnit = ingredient?.baseUnit ?? .g
            self.baseUnit = bUnit
            let conversions = ingredient?.conversions ?? []
            self.packageSize = PackageSizeInput(store: store, baseUnit: bUnit, conversions: conversions)

        case .edit(let presentationId):
            let pres = store.data.presentations.first(where: { $0.id == presentationId && $0.isActive })
            let ingredient = pres.flatMap { p in store.data.ingredients.first(where: { $0.id == p.ingredientId && $0.isActive }) }
            let bUnit = ingredient?.baseUnit ?? .g
            self.baseUnit = bUnit
            let conversions = ingredient?.conversions ?? []
            self.packageSize = PackageSizeInput(store: store, baseUnit: bUnit, conversions: conversions)

            if let pres {
                self.brandText = pres.brand
                if let supId = pres.supplierId,
                   let sup = store.data.suppliers.first(where: { $0.id == supId && $0.isActive }) {
                    self.selectedSupplier = .existing(id: sup.id, name: sup.name)
                } else {
                    self.selectedSupplier = .none
                }
                self.packageSize.load(presentation: pres)
            }
            self.priceText = ""
        }
    }

    var suppliers: [Supplier] {
        store.data.activeSuppliers()
    }

    var isValid: Bool {
        let brandValid = !brandText.trimmingCharacters(in: .whitespaces).isEmpty
        let packageValid = packageSize.isValid
        let priceValid: Bool
        if isCreateMode {
            let trimmed = priceText.trimmingCharacters(in: .whitespaces)
            priceValid = !trimmed.isEmpty && RecordPriceModel.parsePriceCents(trimmed) != nil
        } else {
            priceValid = true
        }
        return brandValid && packageValid && priceValid
    }

    var priceCents: Int? {
        guard isCreateMode else { return nil }
        let trimmed = priceText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return RecordPriceModel.parsePriceCents(trimmed)
    }

    var isPriceFormatInvalid: Bool {
        guard isCreateMode else { return false }
        let trimmed = priceText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return RecordPriceModel.parsePriceCents(trimmed) == nil
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
        guard isValid else {
            return nil
        }
        errorMessage = nil

        let brand = brandText.trimmingCharacters(in: .whitespaces)
        let supplierId = selectedSupplier.supplierId

        do {
            switch mode {
            case .create(let ingredientId):
                let trimmedPrice = priceText.trimmingCharacters(in: .whitespaces)
                guard let priceCents = RecordPriceModel.parsePriceCents(trimmedPrice) else {
                    return nil
                }

                let created: Presentation
                if packageSize.isPiecesMode {
                    guard let pieces = packageSize.packCount,
                          let packItemQty = Quantity.parse(packageSize.packItemQuantityText) else {
                        return nil
                    }
                    created = try store.mutate { data, ctx in
                        try data.createPresentation(
                            ingredientId: ingredientId,
                            brand: brand,
                            supplierId: supplierId,
                            packageQuantity: "\(pieces)",
                            packageUnitId: nil,
                            packCount: pieces,
                            packItemQuantity: packItemQty,
                            packItemUnitId: packageSize.selectedPackItemUnit?.id,
                            barcode: nil,
                            priceCents: priceCents,
                            ctx: ctx
                        )
                    }
                } else {
                    guard let parsedQty = Quantity.parse(packageSize.quantityText),
                          let unit = packageSize.selectedUnit else {
                        return nil
                    }
                    created = try store.mutate { data, ctx in
                        try data.createPresentation(
                            ingredientId: ingredientId,
                            brand: brand,
                            supplierId: supplierId,
                            packageQuantity: parsedQty,
                            packageUnitId: unit.id,
                            packCount: nil,
                            packItemQuantity: nil,
                            packItemUnitId: nil,
                            barcode: nil,
                            priceCents: priceCents,
                            ctx: ctx
                        )
                    }
                }
                return created

            case .edit(let presentationId):
                let updated: Presentation
                if packageSize.isPiecesMode {
                    guard let pieces = packageSize.packCount,
                          let packItemQty = Quantity.parse(packageSize.packItemQuantityText) else {
                        return nil
                    }
                    updated = try store.mutate { data, ctx in
                        try data.updatePresentation(
                            id: presentationId,
                            brand: brand,
                            supplierId: .some(supplierId),
                            packageQuantity: "\(pieces)",
                            packageUnitId: nil,
                            packCount: .some(pieces),
                            packItemQuantity: packItemQty,
                            packItemUnitId: packageSize.selectedPackItemUnit?.id,
                            barcode: nil,
                            ctx: ctx
                        )
                    }
                } else {
                    guard let parsedQty = Quantity.parse(packageSize.quantityText),
                          let unit = packageSize.selectedUnit else {
                        return nil
                    }
                    updated = try store.mutate { data, ctx in
                        try data.updatePresentation(
                            id: presentationId,
                            brand: brand,
                            supplierId: .some(supplierId),
                            packageQuantity: parsedQty,
                            packageUnitId: unit.id,
                            packCount: .some(nil),
                            packItemQuantity: nil,
                            packItemUnitId: nil,
                            barcode: nil,
                            ctx: ctx
                        )
                    }
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
                    if model.isCreateMode {
                        TipView(BrandPackageSizeTip())
                            .tipBackground(.surfaceCard)
                    }
                    PackageSizeField(input: model.packageSize)
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
        }
    }

    private var brandField: some View {
        KitchenTextField(
            label: "Marca",
            text: $model.brandText
        )
    }

    private var storePickerField: some View {
        StorePickerField(
            selection: $model.selectedSupplier,
            store: model.store,
            onError: { model.errorMessage = $0 }
        )
    }

    private var priceField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            KitchenTextField(
                label: "Precio",
                text: $model.priceText,
                keyboard: .decimalPad
            )
            if model.isPriceFormatInvalid {
                Text("Escribe el precio que pagaste, por ejemplo 32.50")
                    .font(.footnote)
                    .foregroundStyle(.warningText)
                    .padding(.horizontal, Spacing.xs)
            } else if model.packageSize.isPiecesMode {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Es el precio de todo el paquete.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)

                    if let priceCents = model.priceCents,
                       let pieces = model.packageSize.packCount,
                       pieces > 0 {
                        let perItemCents = CostingMath.roundToCents(Decimal(priceCents) / Decimal(pieces))
                        Text("Sale a \(Money.format(cents: perItemCents)) cada pieza")
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }
        }
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
