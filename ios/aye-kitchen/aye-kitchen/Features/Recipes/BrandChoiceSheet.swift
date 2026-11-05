import SwiftUI

/// Hoja para elegir la marca de un ingrediente en el costo o en una versión (Bloque I10 / I10.1).
struct BrandChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let line: CostLine
    let isBaseVersion: Bool
    let onSelectBrand: @MainActor @Sendable (String?) async throws -> Void
    let onOpenIngredient: @MainActor @Sendable () -> Void

    @State private var model: BrandChoiceModel
    @State private var isSaving: Bool = false
    @State private var savingPresentationId: String? = nil
    @State private var savingDefault: Bool = false
    @State private var actionErrorMessage: String? = nil

    init(
        line: CostLine,
        isBaseVersion: Bool,
        onSelectBrand: @escaping @MainActor @Sendable (String?) async throws -> Void,
        onOpenIngredient: @escaping @MainActor @Sendable () -> Void,
        mockPresentations: [Presentation]? = nil
    ) {
        self.line = line
        self.isBaseVersion = isBaseVersion
        self.onSelectBrand = onSelectBrand
        self.onOpenIngredient = onOpenIngredient
        _model = State(
            initialValue: BrandChoiceModel(
                ingredientId: line.refId,
                mockPresentations: mockPresentations
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    if isBaseVersion {
                        baseVersionWarning
                    }

                    if let error = actionErrorMessage ?? loadErrorMessage {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.warningText)
                                .accessibilityHidden(true)
                            Text(error)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.warningText)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                    }

                    switch model.state {
                    case .loading where model.presentations.isEmpty:
                        ProgressView()
                            .tint(Color.accentColor)
                            .frame(maxWidth: .infinity, minHeight: 120)

                    case .error where model.presentations.isEmpty:
                        ErrorStateView(message: loadErrorMessage ?? "No se pudieron cargar las marcas") {
                            Task { await model.load() }
                        }

                    default:
                        if model.presentations.isEmpty {
                            emptyStateView
                        } else {
                            brandsList
                        }
                    }

                    footerLink
                }
                .padding(Spacing.xl)
            }
            .background(.canvasBackground)
            .navigationTitle(line.refName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .disabled(isSaving)
                }
            }
            .task {
                if model.state == .loading {
                    await model.load()
                }
            }
        }
    }

    private var loadErrorMessage: String? {
        if case .error(let msg) = model.state {
            return msg
        }
        return nil
    }

    // MARK: - Subvistas

    private var baseVersionWarning: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Esto cambia la marca de la receta.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.inkPrimary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.accentSoft, in: .rect(cornerRadius: Radius.control))
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Todavía no tiene marcas. Agrégalas en Catálogo.")
                .font(.body)
                .foregroundStyle(.inkMuted)
        }
        .padding(.vertical, Spacing.md)
    }

    private var brandsList: some View {
        RowGroup {
            firstChoiceRow

            ForEach(model.presentations) { presentation in
                presentationRow(presentation)
            }
        }
    }

    private var isFirstRowSelected: Bool {
        if isBaseVersion {
            return line.brandSource != .recipe
        } else {
            return line.brandSource != .version
        }
    }

    private var firstRowTitle: String {
        isBaseVersion ? "La que usamos por defecto" : "Como en la base"
    }

    private var firstRowSubtitle: String {
        isBaseVersion ? "Usa la marca vigente del ingrediente" : "Usa la marca que tiene la receta"
    }

    private var firstChoiceRow: some View {
        Button {
            select(presentationId: nil)
        } label: {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(firstRowTitle)
                        .font(.body.weight(.bold))
                        .foregroundStyle(.inkPrimary)

                    Text(firstRowSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }

                Spacer()

                if savingDefault {
                    ProgressView()
                        .tint(Color.accentColor)
                } else if isFirstRowSelected {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Marca seleccionada")
                }
            }
            .padding(Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func isPresentationSelected(_ p: Presentation) -> Bool {
        if isBaseVersion {
            return line.brandSource == .recipe && line.presentationId == p.id
        } else {
            return line.brandSource == .version && line.presentationId == p.id
        }
    }

    private func presentationRow(_ p: Presentation) -> some View {
        let isSelected = isPresentationSelected(p)

        return Button {
            select(presentationId: p.id)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        rowTitle(p)
                        rowSubtitle(p)
                        if isSaving && savingPresentationId == p.id {
                            ProgressView()
                                .tint(Color.accentColor)
                        } else if isSelected {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "checkmark")
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(.tint)
                                Text("Seleccionada")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                } else {
                    HStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            rowTitle(p)
                            rowSubtitle(p)
                        }

                        Spacer()

                        if isSaving && savingPresentationId == p.id {
                            ProgressView()
                                .tint(Color.accentColor)
                        } else if isSelected {
                            Image(systemName: "checkmark")
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Marca seleccionada")
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func rowTitle(_ p: Presentation) -> some View {
        let brandStoreText: String = {
            if let supplier = p.supplierName, !supplier.isEmpty {
                return "\(p.brand) · \(supplier)"
            }
            return p.brand
        }()

        return Text(brandStoreText)
            .font(.body.weight(.bold))
            .foregroundStyle(.inkPrimary)
    }

    private func rowSubtitle(_ p: Presentation) -> some View {
        let packageText: String = {
            let pkgQty = Quantity.format(p.packageQuantity)
            let unitStr = p.baseUnit.rawValue
            if let cents = p.latestPriceCents {
                return "\(Money.format(cents: cents)) por \(pkgQty) \(unitStr)"
            } else {
                return "Sin precio registrado por \(pkgQty) \(unitStr)"
            }
        }()

        let perUnitText: String? = {
            guard let costPerBase = p.costPerBaseUnit else { return nil }
            return Money.formatPerUnit(costPerBaseUnit: costPerBase, baseUnit: p.baseUnit)
        }()

        let fullSubtitle: String = {
            if let perUnitText {
                return "\(packageText) · \(perUnitText)"
            }
            return packageText
        }()

        return Text(fullSubtitle)
            .font(.subheadline)
            .foregroundStyle(.inkMuted)
    }

    private var footerLink: some View {
        Button {
            dismiss()
            onOpenIngredient()
        } label: {
            Text("Ver marcas del ingrediente")
                .font(.body.weight(.bold))
                .foregroundStyle(.tint)
        }
        .padding(.top, Spacing.xs)
    }

    // MARK: - Acciones

    private func select(presentationId: String?) {
        guard !isSaving else { return }
        isSaving = true
        actionErrorMessage = nil
        if let presentationId {
            savingPresentationId = presentationId
            savingDefault = false
        } else {
            savingPresentationId = nil
            savingDefault = true
        }

        Task {
            do {
                try await onSelectBrand(presentationId)
                dismiss()
            } catch {
                actionErrorMessage = error.localizedDescription
                isSaving = false
                savingPresentationId = nil
                savingDefault = false
            }
        }
    }
}

#if DEBUG
#Preview("Elegir marca — En Versión (Como en la base)") {
    let mockLine = CostLine(
        kind: .ingredient,
        refId: "ing_harina",
        refName: "Harina de trigo",
        quantity: "300",
        unitName: "g",
        quantityInBase: "300",
        baseUnit: .g,
        presentationId: "pres_selecta",
        presentationLabel: "Selecta · Walmart · 1000 g",
        pinned: true,
        costCents: 705,
        missingPrice: false,
        priceIsStale: false,
        brandSource: .recipe
    )

    let mockList = [
        Presentation(
            id: "pres_selecta",
            ingredientId: "ing_harina",
            ingredientName: "Harina de trigo",
            brand: "Selecta",
            supplierId: "sup_walmart",
            supplierName: "Walmart",
            packageQuantity: "1000",
            baseUnit: .g,
            barcode: nil,
            latestPriceCents: 2350,
            latestPriceAt: .now,
            costPerBaseUnit: "2.350000",
            isCurrent: true,
            priceAgeDays: 2,
            priceIsStale: false,
            createdAt: .now,
            updatedAt: .now
        ),
        Presentation(
            id: "pres_tres_estrellas",
            ingredientId: "ing_harina",
            ingredientName: "Harina de trigo",
            brand: "Tres Estrellas",
            supplierId: "sup_costco",
            supplierName: "Costco",
            packageQuantity: "1000",
            baseUnit: .g,
            barcode: nil,
            latestPriceCents: 3000,
            latestPriceAt: .now,
            costPerBaseUnit: "3.000000",
            isCurrent: false,
            priceAgeDays: 1,
            priceIsStale: false,
            createdAt: .now,
            updatedAt: .now
        )
    ]

    BrandChoiceSheet(
        line: mockLine,
        isBaseVersion: false,
        onSelectBrand: { _ in },
        onOpenIngredient: {},
        mockPresentations: mockList
    )
}

#Preview("Elegir marca — En Base y Letra AX3") {
    let mockLine = CostLine(
        kind: .ingredient,
        refId: "ing_harina",
        refName: "Harina de trigo",
        quantity: "300",
        unitName: "g",
        quantityInBase: "300",
        baseUnit: .g,
        presentationId: "pres_selecta",
        presentationLabel: "Selecta · Walmart · 1000 g",
        pinned: false,
        costCents: 705,
        missingPrice: false,
        priceIsStale: false,
        brandSource: .current
    )

    let mockList = [
        Presentation(
            id: "pres_selecta",
            ingredientId: "ing_harina",
            ingredientName: "Harina de trigo",
            brand: "Selecta",
            supplierId: "sup_walmart",
            supplierName: "Walmart",
            packageQuantity: "1000",
            baseUnit: .g,
            barcode: nil,
            latestPriceCents: 2350,
            latestPriceAt: .now,
            costPerBaseUnit: "2.350000",
            isCurrent: true,
            priceAgeDays: 2,
            priceIsStale: false,
            createdAt: .now,
            updatedAt: .now
        )
    ]

    BrandChoiceSheet(
        line: mockLine,
        isBaseVersion: true,
        onSelectBrand: { _ in },
        onOpenIngredient: {},
        mockPresentations: mockList
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Elegir marca — Sin marcas") {
    let mockLine = CostLine(
        kind: .ingredient,
        refId: "ing_harina",
        refName: "Harina de trigo",
        quantity: "300",
        unitName: "g",
        quantityInBase: "300",
        baseUnit: .g,
        presentationId: nil,
        presentationLabel: nil,
        pinned: false,
        costCents: 0,
        missingPrice: true,
        priceIsStale: false,
        brandSource: nil
    )

    BrandChoiceSheet(
        line: mockLine,
        isBaseVersion: true,
        onSelectBrand: { _ in },
        onOpenIngredient: {},
        mockPresentations: []
    )
}
#endif
