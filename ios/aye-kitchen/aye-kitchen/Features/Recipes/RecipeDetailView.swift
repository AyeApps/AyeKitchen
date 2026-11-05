import SwiftUI

/// Extensión para permitir usar Chip("Texto") con tono neutral por defecto.
extension Chip {
    init(_ text: String) {
        self.init(text, tone: .neutral)
    }
}

/// Extensión para identificar líneas de costo en sheets.
extension CostLine: Identifiable {
    public var id: String { "\(kind.rawValue)_\(refId)_\(presentationId ?? "")" }
}

/// Detalle y desglose de costo de una receta según Bloque I3/I10 y contrato B6b.
struct RecipeDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: RecipeDetailModel
    @State private var showingEditSheet = false
    @State private var showingCreateVersionSheet = false
    @State private var showingRenameVersionSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedLineForBrandChoice: CostLine? = nil

    private let marginOptions = [20, 30, 40, 60]

    init(
        recipeId: String,
        mockRecipe: Recipe? = nil,
        mockCost: RecipeCost? = nil,
        mockComparisons: [CostVersionComparison]? = nil,
        mockVersions: [CostVersion]? = nil,
        initialVersionId: String? = nil
    ) {
        _model = State(
            initialValue: RecipeDetailModel(
                recipeId: recipeId,
                mockRecipe: mockRecipe,
                mockCost: mockCost,
                mockComparisons: mockComparisons,
                mockVersions: mockVersions,
                initialVersionId: initialVersionId
            )
        )
    }

    var body: some View {
        content
            .background(.canvasBackground)
            .navigationTitle(model.recipe?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
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
                if let recipe = model.recipe {
                    RecipeEditorView(recipe: recipe) { _ in
                        Task {
                            await model.load()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateVersionSheet) {
                CostVersionNameSheet(mode: .create) { newName in
                    try await model.createVersion(name: newName)
                }
            }
            .sheet(isPresented: $showingRenameVersionSheet) {
                if let versionId = model.selectedVersionId, let currentName = model.selectedVersionName {
                    CostVersionNameSheet(mode: .rename(versionId: versionId, currentName: currentName)) { newName in
                        try await model.renameVersion(versionId: versionId, newName: newName)
                    }
                }
            }
            .sheet(item: $selectedLineForBrandChoice) { line in
                BrandChoiceSheet(
                    line: line,
                    isBaseVersion: model.selectedVersionId == nil,
                    onSelectBrand: { presId in
                        try await model.chooseBrand(for: line.refId, presentationId: presId)
                    },
                    onOpenIngredient: {
                        Task {
                            await model.openIngredientLine(line)
                        }
                    }
                )
            }
            .alert(
                "¿Borrar la versión \(model.selectedVersionName ?? "")? La receta no cambia.",
                isPresented: $showingDeleteConfirmation
            ) {
                Button("Borrar", role: .destructive) {
                    if let versionId = model.selectedVersionId {
                        Task {
                            do {
                                try await model.deleteVersion(versionId: versionId)
                            } catch {
                                model.actionErrorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .navigationDestination(item: $model.activeDestination) { destination in
                switch destination {
                case .presentation(let presentation):
                    BrandDetailView(presentation: presentation) {
                        Task {
                            await model.load()
                        }
                    }
                case .ingredient(let ingredient):
                    IngredientDetailView(
                        ingredient: ingredient,
                        onUpdate: { _ in
                            Task { await model.load() }
                        },
                        onDelete: { _ in
                            Task { await model.load() }
                        }
                    )
                }
            }
            .onChange(of: model.activeDestination) { oldValue, newValue in
                if oldValue != nil && newValue == nil {
                    Task {
                        await model.load()
                    }
                }
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
            .task {
                if model.state == .loading {
                    await model.load()
                }
            }
            .refreshable {
                await model.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading where model.recipe == nil:
            ProgressView()
                .tint(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message) where model.recipe == nil:
            ErrorStateView(message: message) {
                Task { await model.load() }
            }

        default:
            if let recipe = model.recipe, let cost = model.cost {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        headerSection(recipe: recipe)
                        versionSelectorSection
                        creamCostCard(recipe: recipe, cost: cost)
                        warningsSection(cost: cost)
                        costBreakdownSection(recipe: recipe, cost: cost)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                }
            }
        }
    }

    // MARK: - Encabezado

    private func headerSection(recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(recipe.name)
                .font(.title.weight(.heavy))
                .foregroundStyle(.inkPrimary)

            Text(yieldDescription(recipe: recipe))
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
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
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var comparisonChipsList: some View {
        ForEach(model.comparisons, id: \.versionId) { comparison in
            let isSelected = (comparison.versionId == model.selectedVersionId)

            Button {
                Task {
                    await model.selectVersion(comparison.versionId)
                }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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
        let profit = cost.suggestedPriceCents - cost.batchCostCents

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Te sugerimos cobrar")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.inkSecondary)

            Text(Money.format(cents: cost.suggestedPriceCents))
                .font(.title.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.tint)

            Text("Ganas \(Money.format(cents: profit))")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .monospacedDigit()
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

                if model.isUpdatingMargin {
                    ProgressView()
                        .tint(Color.accentColor)
                        .scaleEffect(0.8)
                }
            }

            if dynamicTypeSize > .accessibility1 {
                Picker("¿Cuánto quieres ganar?", selection: Binding(
                    get: { isStandard ? currentMargin : nil },
                    set: { if let newMargin = $0 { Task { await model.updateMargin(percent: newMargin) } } }
                )) {
                    ForEach(marginOptions, id: \.self) { margin in
                        Text("\(margin) %").tag(Optional(margin))
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("¿Cuánto quieres ganar?", selection: Binding(
                    get: { isStandard ? currentMargin : nil },
                    set: { if let newMargin = $0 { Task { await model.updateMargin(percent: newMargin) } } }
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
                                isNavigationLink: true,
                                isLoading: model.loadingLine == line
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.loadingLine != nil)
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
    let line: CostLine
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
                        .padding(.top, 2)
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
            Chip("Fijada")
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
#Preview("Receta contrato — Claro") {
    NavigationStack {
        RecipeDetailView(
            recipeId: "recipe-contract-1",
            mockRecipe: .mockContractExample,
            mockCost: .mockContractExample
        )
    }
}

#Preview("Receta contrato — Letra AX3") {
    NavigationStack {
        RecipeDetailView(
            recipeId: "recipe-contract-1",
            mockRecipe: .mockContractExample,
            mockCost: .mockContractExample
        )
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Con dos versiones — Claro") {
    let mockComparisons = [
        CostVersionComparison(
            versionId: nil,
            name: "Base",
            batchCostCents: 705,
            costPerServingCents: 705,
            suggestedPriceCents: 917,
            complete: true,
            hasStalePrices: false
        ),
        CostVersionComparison(
            versionId: "ver_tres_estrellas",
            name: "Con Tres Estrellas",
            batchCostCents: 900,
            costPerServingCents: 900,
            suggestedPriceCents: 1170,
            complete: true,
            hasStalePrices: false
        )
    ]

    let mockVersions = [
        CostVersion(
            id: "ver_tres_estrellas",
            recipeId: "recipe-contract-1",
            name: "Con Tres Estrellas",
            choices: [
                CostVersionChoice(
                    ingredientId: "ing-1",
                    ingredientName: "Harina de trigo",
                    presentationId: "pres-2",
                    brand: "Tres Estrellas"
                )
            ],
            createdAt: .now,
            updatedAt: .now
        )
    ]

    NavigationStack {
        RecipeDetailView(
            recipeId: "recipe-contract-1",
            mockRecipe: .mockContractExample,
            mockCost: .mockContractExample,
            mockComparisons: mockComparisons,
            mockVersions: mockVersions
        )
    }
}

#Preview("Con dos versiones — Letra AX3") {
    let mockComparisons = [
        CostVersionComparison(
            versionId: nil,
            name: "Base",
            batchCostCents: 705,
            costPerServingCents: 705,
            suggestedPriceCents: 917,
            complete: true,
            hasStalePrices: false
        ),
        CostVersionComparison(
            versionId: "ver_tres_estrellas",
            name: "Con Tres Estrellas",
            batchCostCents: 900,
            costPerServingCents: 900,
            suggestedPriceCents: 1170,
            complete: true,
            hasStalePrices: false
        )
    ]

    let mockVersions = [
        CostVersion(
            id: "ver_tres_estrellas",
            recipeId: "recipe-contract-1",
            name: "Con Tres Estrellas",
            choices: [
                CostVersionChoice(
                    ingredientId: "ing-1",
                    ingredientName: "Harina de trigo",
                    presentationId: "pres-2",
                    brand: "Tres Estrellas"
                )
            ],
            createdAt: .now,
            updatedAt: .now
        )
    ]

    NavigationStack {
        RecipeDetailView(
            recipeId: "recipe-contract-1",
            mockRecipe: .mockContractExample,
            mockCost: .mockContractExample,
            mockComparisons: mockComparisons,
            mockVersions: mockVersions
        )
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Con avisos y subreceta — Claro") {
    NavigationStack {
        RecipeDetailView(
            recipeId: "recipe-warnings-1",
            mockRecipe: .mockContractExample,
            mockCost: .mockWithWarnings
        )
    }
}

#Preview("Con avisos y subreceta — Letra AX3") {
    NavigationStack {
        RecipeDetailView(
            recipeId: "recipe-warnings-1",
            mockRecipe: .mockContractExample,
            mockCost: .mockWithWarnings
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
