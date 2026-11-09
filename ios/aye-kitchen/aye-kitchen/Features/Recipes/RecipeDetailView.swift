import SwiftUI
import TipKit
import KitchenDomain

/// Extensión para identificar líneas de costo en sheets.
extension RecipeCostLine: Identifiable {
    public var id: String { "\(kind.rawValue)_\(refId)_\(presentationId ?? "")" }
}

/// Detalle y desglose de costo de una receta según Bloque I3/I10 y contrato B6b (Bloque I17 local-first).
struct RecipeDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: RecipeDetailModel
    private let store: LocalStore
    @State private var showingEditSheet = false
    @State private var showingCreateVersionSheet = false
    @State private var showingRenameVersionSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSalePriceSheet = false
    @State private var selectedLineForBrandChoice: RecipeCostLine? = nil

    private let marginOptions = [20, 30, 40, 60]

    init(
        recipeId: String,
        initialVersionId: String? = nil,
        store: LocalStore = .shared
    ) {
        self.store = store
        _model = State(
            initialValue: RecipeDetailModel(
                recipeId: recipeId,
                initialVersionId: initialVersionId,
                store: store
            )
        )
    }

    var body: some View {
        content
            .background(.canvasBackground)
            .navigationTitle(model.recipe?.name ?? "")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if model.selectedVersionId != nil {
                        Menu {
                            Button("Cambiar nombre") {
                                showingRenameVersionSheet = true
                            }
                            Button("Borrar versión", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }

                    Button("Editar") {
                        showingEditSheet = true
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                RecipeEditorView(mode: .edit(recipeId: model.recipeId), store: store)
            }
            .sheet(isPresented: $showingCreateVersionSheet) {
                CostVersionNameSheet(mode: .create) { newName in
                    try model.createVersion(name: newName)
                }
            }
            .sheet(isPresented: $showingRenameVersionSheet) {
                if let versionId = model.selectedVersionId, let currentName = model.selectedVersionName {
                    CostVersionNameSheet(mode: .rename(versionId: versionId, currentName: currentName)) { newName in
                        try model.renameVersion(versionId: versionId, newName: newName)
                    }
                }
            }
            .sheet(item: $selectedLineForBrandChoice) { line in
                BrandChoiceSheet(
                    line: line,
                    isBaseVersion: model.selectedVersionId == nil,
                    store: store,
                    onSelectBrand: { presId in
                        try model.chooseBrand(for: line.refId, presentationId: presId)
                    },
                    onOpenIngredient: {
                        model.openIngredientLine(line)
                    }
                )
            }
            .sheet(isPresented: $showingSalePriceSheet) {
                if let recipe = model.recipe, let cost = model.cost {
                    SalePriceSheet(recipe: recipe, cost: cost, store: store)
                }
            }
            .alert(
                "¿Borrar la versión \(model.selectedVersionName ?? "")? La receta no cambia.",
                isPresented: $showingDeleteConfirmation
            ) {
                Button("Borrar", role: .destructive) {
                    if let versionId = model.selectedVersionId {
                        do {
                            try model.deleteVersion(versionId: versionId)
                        } catch {
                            model.actionErrorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .navigationDestination(item: $model.activeDestination) { destination in
                switch destination {
                case .presentation(let presentationId):
                    BrandDetailView(presentationId: presentationId, store: store)
                case .ingredient(let ingredientId):
                    IngredientDetailView(ingredientId: ingredientId, store: store)
                }
            }
            .navigationDestination(for: String.self) { recipeId in
                RecipeDetailView(recipeId: recipeId, store: store)
            }
            .alert(
                "No se pudo cargar",
                isPresented: Binding(
                    get: { model.lineErrorMessage != nil },
                    set: { if !$0 { model.lineErrorMessage = nil } }
                )
            ) {
                Button("Entendido", role: .cancel) {}
            } message: {
                if let message = model.lineErrorMessage {
                    Text(message)
                }
            }
            .onAppear {
                RecipeVersionsTip.recipeHasIngredientWithSeveralBrands = model.hasIngredientWithSeveralBrands
            }
            .onChange(of: model.hasIngredientWithSeveralBrands) { _, newValue in
                RecipeVersionsTip.recipeHasIngredientWithSeveralBrands = newValue
            }
    }

    @ViewBuilder
    private var content: some View {
        if let recipe = model.recipe, let cost = model.cost {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    headerSection(recipe: recipe)
                    versionSelectorSection
                    creamCostCard(recipe: recipe, cost: cost)
                    warningsSection(cost: cost)
                    costBreakdownSection(recipe: recipe, cost: cost)
                    ReferencesSection(owner: .recipe(recipe.id), store: store)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
        } else {
            ContentUnavailableView(
                "Receta no encontrada",
                systemImage: "fork.knife",
                description: Text("Esta receta ya no existe o fue eliminada.")
            )
        }
    }

    // MARK: - Encabezado

    private func headerSection(recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(yieldDescription(recipe: recipe))
                .font(.subheadline)
                .foregroundStyle(.inkMuted)

            if let description = recipe.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        }
    }

    private func yieldDescription(recipe: Recipe) -> String {
        let qty = Quantity.format(recipe.yieldQuantity)
        let unitWord = yieldUnitWord(quantity: recipe.yieldQuantity, unit: recipe.yieldUnit)
        var text = "Rinde \(qty) \(unitWord)"
        if let servings = recipe.servings {
            let servingsWord = servings == 1 ? "1 porción" : "\(servings) porciones"
            text += " · \(servingsWord)"
        }
        return text
    }

    private func yieldUnitWord(quantity: String, unit: BaseUnit) -> String {
        let clean = quantity.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let isSingular = (clean == "1" || clean == "1.0" || clean == "1.00" || clean == "1.000")
        switch unit {
        case .g:
            return isSingular ? "gramo" : "gramos"
        case .ml:
            return isSingular ? "mililitro" : "mililitros"
        case .pz:
            return isSingular ? "pieza" : "piezas"
        }
    }

    // MARK: - Selector de versión

    @ViewBuilder
    private var versionSelectorSection: some View {
        let hasVersions = model.comparisons.count > 1 || !model.versions.isEmpty

        VStack(alignment: .leading, spacing: Spacing.sm) {
            TipView(RecipeVersionsTip())
                .tipBackground(.surfaceCard)

            if !hasVersions {
                Button("Comparar con otras marcas") {
                    showingCreateVersionSheet = true
                }
                .buttonStyle(.kitchenSecondary)
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        comparisonChipsList
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            comparisonChipsList
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var comparisonChipsList: some View {
        ForEach(model.comparisons, id: \.versionId) { comparison in
            let isSelected = (comparison.versionId == model.selectedVersionId)

            Button {
                model.selectVersion(comparison.versionId)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(comparison.name)
                        .font(.subheadline.weight(.heavy))

                    Text("·")
                        .font(.subheadline.weight(.bold))

                    Text(Money.format(cents: comparison.batchCostCents))
                        .font(.subheadline.weight(.heavy))
                        .monospacedDigit()
                }
                .foregroundStyle(isSelected ? Color.accentInk : Color.inkPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    isSelected ? Color.accentFill : Color.surfaceCard,
                    in: .capsule
                )
                .overlay {
                    if !isSelected {
                        Capsule()
                            .strokeBorder(Color.borderLine, lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
        }

        Button {
            showingCreateVersionSheet = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                Text("Nueva versión")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.surfaceCard, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(Color.borderInput, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tarjeta crema (componente firma)

    private func creamCostCard(recipe: Recipe, cost: RecipeCost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    costColumn(cost: cost)
                    suggestedColumn(cost: cost)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.md) {
                    costColumn(cost: cost)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    suggestedColumn(cost: cost)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Rectangle()
                .fill(.dividerLine)
                .frame(height: 1)

            marginControlSection(cost: cost)

            Rectangle()
                .fill(.dividerLine)
                .frame(height: 1)

            customPriceSection(recipe: recipe, cost: cost)
        }
        .softCard()
    }

    private func costColumn(cost: RecipeCost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Te cuesta")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkSecondary)

            Text(Money.format(cents: cost.batchCostCents))
                .font(.title.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.inkPrimary)

            if let perServing = cost.costPerServingCents {
                Text("\(Money.format(cents: perServing)) por porción")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .monospacedDigit()
            }
        }
    }

    private func suggestedColumn(cost: RecipeCost) -> some View {
        let profit = suggestedProfit(cost: cost)

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Te sugerimos cobrar")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkSecondary)

            Text(Money.format(cents: cost.suggestedPriceCents))
                .font(.title.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.tint)

            let profitText: String = {
                if let pct = profit.percent {
                    return "Ganas \(Money.format(cents: profit.profitCents)) (\(pct) %)"
                } else {
                    return "Ganas \(Money.format(cents: profit.profitCents))"
                }
            }()

            Text(profitText)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .monospacedDigit()
        }
    }

    // MARK: - Bloque "Tu precio"

    @ViewBuilder
    private func customPriceSection(recipe: Recipe, cost: RecipeCost) -> some View {
        if let customPrice = salePrice(of: recipe, cost: cost) {
            customPriceConfiguredView(recipe: recipe, customPrice: customPrice)
        } else {
            customPriceEmptyView
        }
    }

    private var customPriceEmptyView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button("Poner mi precio") {
                showingSalePriceSheet = true
            }
            .buttonStyle(.kitchenSecondary)

            Text("¿Ya cobras otra cosa? Ponla y te decimos cuánto ganas.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
        }
    }

    private func customPriceConfiguredView(recipe: Recipe, customPrice: RecipeSalePrice) -> some View {
        let isBatch = customPrice.soldBy == .batch
        let activeProfit = isBatch ? customPrice.batch : customPrice.perUnit
        let activeUnitLabel = isBatch ? "por tanda" : unitPhrase(for: recipe.yieldUnit)

        let yieldDecimal = Qty.decimal(recipe.yieldQuantity) ?? 1
        let yieldsMultiple = yieldDecimal > 1

        let otherProfit = isBatch ? customPrice.perUnit : customPrice.batch
        let otherUnitLabel = isBatch ? unitPhrase(for: recipe.yieldUnit) : "por tanda"

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    customPriceInfo(
                        activeProfit: activeProfit,
                        activeUnitLabel: activeUnitLabel,
                        yieldsMultiple: yieldsMultiple,
                        otherProfit: otherProfit,
                        otherUnitLabel: otherUnitLabel
                    )

                    Button("Cambiar") {
                        showingSalePriceSheet = true
                    }
                    .buttonStyle(.kitchenSecondary)
                }
            } else {
                HStack(alignment: .top) {
                    customPriceInfo(
                        activeProfit: activeProfit,
                        activeUnitLabel: activeUnitLabel,
                        yieldsMultiple: yieldsMultiple,
                        otherProfit: otherProfit,
                        otherUnitLabel: otherUnitLabel
                    )

                    Spacer()

                    Button("Cambiar") {
                        showingSalePriceSheet = true
                    }
                    .buttonStyle(.kitchenSecondary)
                }
            }
        }
    }

    private func customPriceInfo(
        activeProfit: Profit,
        activeUnitLabel: String,
        yieldsMultiple: Bool,
        otherProfit: Profit,
        otherUnitLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Tu precio \(Money.format(cents: activeProfit.priceCents)) \(activeUnitLabel)")
                .font(.body.weight(.bold))
                .foregroundStyle(.inkPrimary)
                .monospacedDigit()

            if activeProfit.profitCents < 0 {
                Text("Con este precio pierdes \(Money.format(cents: abs(activeProfit.profitCents)))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.warningText)
                    .monospacedDigit()
            } else if let pct = activeProfit.percent {
                Text("Ganas \(Money.format(cents: activeProfit.profitCents)) (\(pct) %)")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .monospacedDigit()
            } else {
                Text("Ganas \(Money.format(cents: activeProfit.profitCents))")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .monospacedDigit()
            }

            if yieldsMultiple {
                let otherGainText: String = {
                    if otherProfit.profitCents < 0 {
                        return "pierdes \(Money.format(cents: abs(otherProfit.profitCents)))"
                    } else {
                        return "ganas \(Money.format(cents: otherProfit.profitCents))"
                    }
                }()

                Text("\(Money.format(cents: otherProfit.priceCents)) \(otherUnitLabel) · \(otherGainText)")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .monospacedDigit()
            }
        }
    }

    private func unitPhrase(for unit: BaseUnit) -> String {
        switch unit {
        case .pz: "por pieza"
        case .g: "por g"
        case .ml: "por ml"
        }
    }

    private func marginControlSection(cost: RecipeCost) -> some View {
        let currentMargin = model.effectiveMargin
        let isStandard = marginOptions.contains(currentMargin)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("¿Cuánto quieres ganar?")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.inkPrimary)

                Spacer()
            }

            if dynamicTypeSize > .accessibility1 {
                Picker("¿Cuánto quieres ganar?", selection: Binding(
                    get: { isStandard ? currentMargin : nil },
                    set: { if let newMargin = $0 { model.updateMargin(percent: newMargin) } }
                )) {
                    ForEach(marginOptions, id: \.self) { margin in
                        Text("\(margin) %").tag(Optional(margin))
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("¿Cuánto quieres ganar?", selection: Binding(
                    get: { isStandard ? currentMargin : nil },
                    set: { if let newMargin = $0 { model.updateMargin(percent: newMargin) } }
                )) {
                    ForEach(marginOptions, id: \.self) { margin in
                        Text("\(margin) %").tag(Optional(margin))
                    }
                }
                .pickerStyle(.segmented)
            }

            if !isStandard {
                Text("Ahora ganas el \(currentMargin) %")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.inkMuted)
            }

            if let errorMsg = model.actionErrorMessage {
                Text(errorMsg)
                    .font(.footnote)
                    .foregroundStyle(.warningText)
            }
        }
    }

    // MARK: - Avisos

    @ViewBuilder
    private func warningsSection(cost: RecipeCost) -> some View {
        if !cost.complete || cost.hasStalePrices {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if !cost.complete {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Chip("Falta precio", tone: .warning)
                        Text("A esta receta le faltan precios: lo que te cuesta puede ser más.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.inkPrimary)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                }

                if cost.hasStalePrices {
                    let staleDays = session.me?.workspace.priceStaleDays ?? 30
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Chip("Precio viejo", tone: .warning)
                        Text("Algunos precios tienen más de \(staleDays) días.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.inkPrimary)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                }
            }
        }
    }

    // MARK: - De dónde sale el costo

    private func costBreakdownSection(recipe: Recipe, cost: RecipeCost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TipView(RecipeChangeBrandTip())
                .tipBackground(.surfaceCard)

            Text("De dónde sale el costo")
                .sectionTitleStyle()

            RowGroup {
                ForEach(cost.lines, id: \.self) { line in
                    if line.kind == .recipe {
                        NavigationLink(value: line.refId) {
                            CostLineRow(line: line, isNavigationLink: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            selectedLineForBrandChoice = line
                        } label: {
                            CostLineRow(
                                line: line,
                                isNavigationLink: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(recipe.extraCosts, id: \.self) { extra in
                    ExtraCostRow(extra: extra)
                }
            }
        }
    }
}

/// Fila individual de línea de costo (ingrediente o subreceta).
struct CostLineRow: View {
    let line: RecipeCostLine
    let isNavigationLink: Bool
    var isLoading: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconBoxSize: CGFloat = 40

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(Spacing.lg)
        .contentShape(Rectangle())
    }

    private var standardLayout: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            iconView

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(line.refName)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.inkPrimary)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)

                if hasChips {
                    chipsLayout
                        .padding(.top, Spacing.xs)
                }
            }

            Spacer()

            trailingView
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                iconView
                Text(line.refName)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.inkPrimary)
            }

            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)

            if hasChips {
                chipsLayout
            }

            trailingView
        }
    }

    private var hasChips: Bool {
        line.priceIsStale || line.brandSource == .version || line.brandSource == .recipe
    }

    @ViewBuilder
    private var chipsLayout: some View {
        HStack(spacing: Spacing.xs) {
            if line.priceIsStale {
                Chip("Precio viejo", tone: .warning)
            }
            brandSourceChip
        }
    }

    @ViewBuilder
    private var brandSourceChip: some View {
        switch line.brandSource {
        case .version:
            Chip("Esta versión", tone: .inProgress)
        case .recipe:
            Chip("Fijada", tone: .neutral)
        case .current, .none:
            EmptyView()
        }
    }

    private var iconView: some View {
        let (iconName, bg) = iconConfig
        return Image(systemName: iconName)
            .font(.body.weight(.bold))
            .foregroundStyle(.accentTextDeep)
            .frame(width: iconBoxSize, height: iconBoxSize)
            .background(bg, in: .rect(cornerRadius: Radius.control))
            .accessibilityHidden(true)
    }

    private var iconConfig: (String, Color) {
        switch line.kind {
        case .ingredient:
            ("basket.fill", .warningSoft)
        case .recipe:
            ("fork.knife", .accentSoftStrong)
        }
    }

    private var detailText: String {
        switch line.kind {
        case .ingredient:
            let qtyUnit = "\(Quantity.format(line.quantity)) \(line.unitName ?? "")".trimmingCharacters(in: .whitespaces)
            if let label = line.presentationLabel, !label.trimmingCharacters(in: .whitespaces).isEmpty {
                return "\(qtyUnit) · \(label)"
            }
            return qtyUnit
        case .recipe:
            let qtyUnit = "\(Quantity.format(line.quantity)) \(line.unitName ?? "")".trimmingCharacters(in: .whitespaces)
            return "Tu receta · \(qtyUnit)"
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        HStack(spacing: Spacing.xs) {
            if line.missingPrice {
                Chip("Falta precio", tone: .warning)
            } else {
                Text(Money.format(cents: line.costCents))
                    .font(.body.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.inkPrimary)
            }

            if isLoading {
                ProgressView()
                    .tint(Color.accentColor)
            } else if isNavigationLink {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.inkMuted)
            }
        }
    }
}

/// Fila para un costo fijo adicional (gas, empaque, etc.).
struct ExtraCostRow: View {
    let extra: ExtraCost

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconBoxSize: CGFloat = 40

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        iconView
                        Text(extra.name)
                            .font(.body.weight(.bold))
                            .foregroundStyle(.inkPrimary)
                    }

                    Text("Costo fijo")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)

                    Text(Money.format(cents: extra.costCents))
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.md) {
                    iconView

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(extra.name)
                            .font(.body.weight(.bold))
                            .foregroundStyle(.inkPrimary)

                        Text("Costo fijo")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }

                    Spacer()

                    Text(Money.format(cents: extra.costCents))
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)
                }
            }
        }
        .padding(Spacing.lg)
    }

    private var iconView: some View {
        Image(systemName: "shippingbox.fill")
            .font(.body.weight(.bold))
            .foregroundStyle(.accentTextDeep)
            .frame(width: iconBoxSize, height: iconBoxSize)
            .background(Color.neutralSoft, in: .rect(cornerRadius: Radius.control))
            .accessibilityHidden(true)
    }
}

#if DEBUG
private enum PreviewRecipeScenario {
    case withoutCustomPrice
    case withCustomPrice
    case withLoss
}

private func makeRecipePreviewStore(scenario: PreviewRecipeScenario) -> (String, LocalStore) {
    var data = KitchenData.previewSample

    switch scenario {
    case .withoutCustomPrice:
        return ("rec-pastel", LocalStore.preview(data))
    case .withCustomPrice:
        if let idx = data.recipes.firstIndex(where: { $0.id == "rec-galletas" }) {
            data.recipes[idx].salePriceCents = 1500
            data.recipes[idx].salePriceSoldBy = .batch
        }
        return ("rec-galletas", LocalStore.preview(data))
    case .withLoss:
        if let idx = data.recipes.firstIndex(where: { $0.id == "rec-pastel" }) {
            data.recipes[idx].salePriceCents = 5000
            data.recipes[idx].salePriceSoldBy = .batch
        }
        return ("rec-pastel", LocalStore.preview(data))
    }
}

#Preview("Receta sin precio propio") {
    let (recipeId, store) = makeRecipePreviewStore(scenario: .withoutCustomPrice)
    NavigationStack {
        RecipeDetailView(recipeId: recipeId, store: store)
    }
}

#Preview("Receta con precio propio") {
    let (recipeId, store) = makeRecipePreviewStore(scenario: .withCustomPrice)
    NavigationStack {
        RecipeDetailView(recipeId: recipeId, store: store)
    }
}

#Preview("Receta con pérdida") {
    let (recipeId, store) = makeRecipePreviewStore(scenario: .withLoss)
    NavigationStack {
        RecipeDetailView(recipeId: recipeId, store: store)
    }
}

#Preview("Receta con precio propio AX3") {
    let (recipeId, store) = makeRecipePreviewStore(scenario: .withCustomPrice)
    NavigationStack {
        RecipeDetailView(recipeId: recipeId, store: store)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
