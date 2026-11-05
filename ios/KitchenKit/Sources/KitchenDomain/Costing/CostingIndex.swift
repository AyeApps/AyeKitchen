import Foundation

/// Índice en memoria de un negocio para costear recetas y convertir unidades.
/// Se construye una vez desde `KitchenData`, ignorando lo borrado (`deletedAt != nil`).
public struct CostingIndex: Sendable {
    public let data: KitchenData
    public let settings: KitchenSettings
    public let unitsById: [String: KitchenUnit]
    public let ingredientsById: [String: Ingredient]
    public let recipesById: [String: Recipe]
    public let presentationsById: [String: Presentation]
    public let presentationsByIngredient: [String: [Presentation]]
    public let latestPriceByPresentation: [String: PriceRecord]
    public let suppliersById: [String: Supplier]
    public let currentPresentationByIngredient: [String: CurrentPresentation]
    public let costVersionsByRecipe: [String: [CostVersion]]
    public let costVersionsById: [String: CostVersion]

    public init(data: KitchenData) {
        self.data = data
        self.settings = data.settings

        var units: [String: KitchenUnit] = [:]
        for u in SystemUnits.all {
            units[u.id] = u
        }
        for u in data.units where u.deletedAt == nil {
            units[u.id] = u
        }
        self.unitsById = units

        var ings: [String: Ingredient] = [:]
        for i in data.ingredients where i.deletedAt == nil {
            ings[i.id] = i
        }
        self.ingredientsById = ings

        var recs: [String: Recipe] = [:]
        for r in data.recipes where r.deletedAt == nil {
            recs[r.id] = r
        }
        self.recipesById = recs

        var supps: [String: Supplier] = [:]
        for s in data.suppliers where s.deletedAt == nil {
            supps[s.id] = s
        }
        self.suppliersById = supps

        var presById: [String: Presentation] = [:]
        var presByIng: [String: [Presentation]] = [:]
        for p in data.presentations where p.deletedAt == nil {
            presById[p.id] = p
            presByIng[p.ingredientId, default: []].append(p)
        }
        self.presentationsById = presById
        self.presentationsByIngredient = presByIng

        // Último precio por presentación: activo, más reciente por recordedAt y luego createdAt.
        let activePrices = data.priceRecords.filter { $0.deletedAt == nil }
        let sortedPrices = activePrices.sorted { a, b in
            if a.recordedAt != b.recordedAt {
                return a.recordedAt > b.recordedAt
            }
            return a.createdAt > b.createdAt
        }
        var latestPrices: [String: PriceRecord] = [:]
        for pr in sortedPrices {
            if latestPrices[pr.presentationId] == nil {
                latestPrices[pr.presentationId] = pr
            }
        }
        self.latestPriceByPresentation = latestPrices

        // Marca vigente de cada ingrediente: la presentación activa con precio cuyo PriceRecord más reciente
        // (recordedAt) es el más nuevo. Desempate: la presentación creada más recientemente (createdAt).
        var currentByIng: [String: CurrentPresentation] = [:]
        for (ingId, presList) in presByIng {
            var candidates: [(presentation: Presentation, priceRecord: PriceRecord)] = []
            for p in presList {
                if let pr = latestPrices[p.id] {
                    candidates.append((presentation: p, priceRecord: pr))
                }
            }
            if !candidates.isEmpty {
                candidates.sort { a, b in
                    if a.priceRecord.recordedAt != b.priceRecord.recordedAt {
                        return a.priceRecord.recordedAt > b.priceRecord.recordedAt
                    }
                    return a.presentation.createdAt > b.presentation.createdAt
                }
                let winner = candidates[0]
                currentByIng[ingId] = CurrentPresentation(
                    presentation: winner.presentation,
                    priceRecord: winner.priceRecord
                )
            }
        }
        self.currentPresentationByIngredient = currentByIng

        var versionsByRec: [String: [CostVersion]] = [:]
        var versionsById: [String: CostVersion] = [:]
        let activeVersions = data.costVersions.filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
        for v in activeVersions {
            versionsById[v.id] = v
            versionsByRec[v.recipeId, default: []].append(v)
        }
        self.costVersionsByRecipe = versionsByRec
        self.costVersionsById = versionsById
    }

    public func latestPrice(for presentationId: String) -> PriceRecord? {
        latestPriceByPresentation[presentationId]
    }

    public func currentPresentation(for ingredientId: String) -> CurrentPresentation? {
        currentPresentationByIngredient[ingredientId]
    }

    // MARK: - Precios viejos (staleness)

    public func computePriceStaleness(
        priceAt: Date?,
        now: Date
    ) -> (ageDays: Int?, isStale: Bool) {
        guard let priceAt = priceAt else {
            return (nil, false)
        }

        let tz = TimeZone(identifier: settings.timezone) ?? TimeZone(identifier: "America/Mexico_City") ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let startOfPriceDay = calendar.startOfDay(for: priceAt)
        let startOfNowDay = calendar.startOfDay(for: now)
        let components = calendar.dateComponents([.day], from: startOfPriceDay, to: startOfNowDay)
        let ageDays = max(0, components.day ?? 0)
        let isStale = ageDays > settings.priceStaleDays
        return (ageDays, isStale)
    }

    // MARK: - Conversión

    /// Lleva una cantidad en `unitId` a la unidad base del ingrediente según las 4 reglas del contrato:
    /// 1. `unitId` vacío -> la cantidad ya está en la unidad base.
    /// 2. El ingrediente tiene una conversión propia para ese `unitId` -> quantity * quantity_in_base.
    /// 3. La unidad tiene la misma `baseUnit` que el ingrediente -> quantity * factor_to_base.
    /// 4. Si no -> `UNIT_NOT_CONVERTIBLE` ("Define cuántos g tiene 1 taza de Harina de trigo").
    public func convertToBase(
        quantity: Decimal,
        unitId: String?,
        ingredient: Ingredient
    ) throws -> Decimal {
        guard let unitId = unitId, !unitId.isEmpty else {
            return quantity
        }

        // 2. Conversión propia del ingrediente
        if let conv = ingredient.conversions.first(where: { $0.unitId == unitId }) {
            guard let qtyInBase = Qty.decimal(conv.quantityInBase) else {
                throw DomainError.invalidReference(detail: "Cantidad en base inválida en conversión de ingrediente: \(conv.quantityInBase)")
            }
            return quantity * qtyInBase
        }

        // 3 y 4. Buscar en unidades
        guard let unit = unitsById[unitId] else {
            throw DomainError.invalidReference(detail: "Unidad no encontrada: \(unitId)")
        }

        if unit.baseUnit == ingredient.baseUnit {
            guard let factor = Qty.decimal(unit.factorToBase) else {
                throw DomainError.invalidReference(detail: "Factor a base inválido en unidad: \(unit.factorToBase)")
            }
            return quantity * factor
        }

        // 4. No convertible
        throw DomainError.unitNotConvertible(
            detail: "Define cuántos \(ingredient.baseUnit.rawValue) tiene 1 \(unit.name) de \(ingredient.name)"
        )
    }

    /// Convierte una cantidad en `unitId` a una `BaseUnit` destino usando solo la tabla general de unidades.
    /// Mismo `baseUnit` multiplica por `factor_to_base`; distinto lanza `UNIT_NOT_CONVERTIBLE`.
    public func convertBetweenBaseUnits(
        quantity: Decimal,
        unitId: String?,
        targetBaseUnit: BaseUnit
    ) throws -> Decimal {
        guard let unitId = unitId, !unitId.isEmpty else {
            return quantity
        }

        guard let unit = unitsById[unitId] else {
            throw DomainError.invalidReference(detail: "Unidad no encontrada: \(unitId)")
        }

        if unit.baseUnit == targetBaseUnit {
            guard let factor = Qty.decimal(unit.factorToBase) else {
                throw DomainError.invalidReference(detail: "Factor a base inválido en unidad: \(unit.factorToBase)")
            }
            return quantity * factor
        }

        throw DomainError.unitNotConvertible(
            detail: "No se puede convertir '\(unit.name)' (\(unit.baseUnit.rawValue)) a '\(targetBaseUnit.rawValue)'"
        )
    }

    // MARK: - Costeo

    private struct IngredientCostResult {
        var quantityInBase: Decimal
        var presentation: Presentation?
        var pinned: Bool
        var priceCents: Int?
        var unroundedCost: Decimal
        var priceIsStale: Bool
        var brandSource: BrandSource?
    }

    private func computeIngredientLineCost(
        item: RecipeItem,
        ingredient: Ingredient,
        chosenPresentationId: String?,
        now: Date
    ) throws -> IngredientCostResult {
        let qty = Qty.decimal(item.quantity) ?? 0
        let qtyInBase = try convertToBase(quantity: qty, unitId: item.unitId, ingredient: ingredient)

        var pinned = false
        var brandSource: BrandSource? = nil
        var pres: Presentation? = nil
        var priceRecord: PriceRecord? = nil
        var priceCents: Int? = nil

        // i. La elegida por la versión, si está activa y es de ese ingrediente
        if let chosenId = chosenPresentationId,
           let chosenP = presentationsById[chosenId],
           chosenP.ingredientId == ingredient.id {
            pres = chosenP
            brandSource = .version
            pinned = true
            if let pr = latestPriceByPresentation[chosenP.id] {
                priceRecord = pr
                priceCents = pr.priceCents
            }
        }

        // ii. Si no, la fijada en la línea
        if pres == nil,
           let pinnedId = item.pinnedPresentationId,
           let pinnedP = presentationsById[pinnedId],
           pinnedP.ingredientId == ingredient.id {
            pres = pinnedP
            brandSource = .recipe
            pinned = true
            if let pr = latestPriceByPresentation[pinnedP.id] {
                priceRecord = pr
                priceCents = pr.priceCents
            }
        }

        // iii. Si no, la vigente
        if pres == nil {
            if let curr = currentPresentationByIngredient[ingredient.id] {
                pres = curr.presentation
                brandSource = .current
                pinned = false
                priceRecord = curr.priceRecord
                priceCents = curr.priceRecord.priceCents
            } else {
                pres = nil
                brandSource = nil
                pinned = false
                priceRecord = nil
                priceCents = nil
            }
        }

        let unroundedCost: Decimal
        if let pres = pres, let priceCents = priceCents {
            let pkgQty = Qty.decimal(pres.packageQuantity) ?? 0
            if pkgQty > 0 {
                unroundedCost = (qtyInBase * Decimal(priceCents)) / pkgQty
            } else {
                unroundedCost = 0
            }
        } else {
            unroundedCost = 0
        }

        let priceIsStale: Bool
        if pres != nil, let pr = priceRecord, priceCents != nil {
            priceIsStale = computePriceStaleness(priceAt: pr.recordedAt, now: now).isStale
        } else {
            priceIsStale = false
        }

        return IngredientCostResult(
            quantityInBase: qtyInBase,
            presentation: pres,
            pinned: pinned,
            priceCents: priceCents,
            unroundedCost: unroundedCost,
            priceIsStale: priceIsStale,
            brandSource: brandSource
        )
    }

    private func computeSubrecipeUnroundedCost(
        recipeId: String,
        cache: inout [String: (batchCost: Decimal, isComplete: Bool, hasStalePrices: Bool)],
        depth: Int,
        now: Date
    ) throws -> (batchCost: Decimal, isComplete: Bool, hasStalePrices: Bool) {
        if depth > 10 {
            return (0, false, false)
        }

        if let cached = cache[recipeId] {
            return cached
        }

        guard let subrecipe = recipesById[recipeId] else {
            cache[recipeId] = (0, false, false)
            return (0, false, false)
        }

        var isComplete = true
        var hasStalePrices = false
        var linesUnroundedCost: Decimal = 0

        for item in subrecipe.items {
            switch item.kind {
            case .ingredient:
                guard let ingredient = ingredientsById[item.refId] else {
                    isComplete = false
                    continue
                }
                let costRes = try computeIngredientLineCost(
                    item: item,
                    ingredient: ingredient,
                    chosenPresentationId: nil,
                    now: now
                )
                linesUnroundedCost += costRes.unroundedCost
                if costRes.priceCents == nil || costRes.presentation == nil {
                    isComplete = false
                }
                if costRes.priceIsStale {
                    hasStalePrices = true
                }

            case .recipe:
                let (subCost, subComp, subStale) = try computeSubrecipeUnroundedCost(
                    recipeId: item.refId,
                    cache: &cache,
                    depth: depth + 1,
                    now: now
                )
                if !subComp {
                    isComplete = false
                }
                if subStale {
                    hasStalePrices = true
                }

                if let nestedRec = recipesById[item.refId] {
                    let qtyInYield = try convertBetweenBaseUnits(
                        quantity: Qty.decimal(item.quantity) ?? 0,
                        unitId: item.unitId,
                        targetBaseUnit: nestedRec.yieldUnit
                    )
                    let yieldQty = Qty.decimal(nestedRec.yieldQuantity) ?? 0
                    if yieldQty > 0 {
                        let lineCost = (qtyInYield * subCost) / yieldQty
                        linesUnroundedCost += lineCost
                    } else {
                        isComplete = false
                    }
                } else {
                    isComplete = false
                }
            }
        }

        let extrasCost: Decimal = subrecipe.extraCosts.reduce(0) { $0 + Decimal($1.costCents) }
        let batchCost = linesUnroundedCost + extrasCost
        cache[recipeId] = (batchCost, isComplete, hasStalePrices)
        return (batchCost, isComplete, hasStalePrices)
    }

    public func calculateRecipeCost(
        recipe: Recipe,
        version: CostVersion? = nil,
        now: Date = Date()
    ) throws -> RecipeCost {
        var cache: [String: (batchCost: Decimal, isComplete: Bool, hasStalePrices: Bool)] = [:]
        return try calculateRecipeCost(recipe: recipe, version: version, now: now, cache: &cache)
    }

    public func calculateRecipeCost(
        recipe: Recipe,
        version: CostVersion? = nil,
        now: Date = Date(),
        cache: inout [String: (batchCost: Decimal, isComplete: Bool, hasStalePrices: Bool)]
    ) throws -> RecipeCost {
        let versionChoices: [String: String] = {
            guard let version = version else { return [:] }
            return Dictionary(version.choices.map { ($0.ingredientId, $0.presentationId) }, uniquingKeysWith: { _, last in last })
        }()

        var lines: [RecipeCostLine] = []
        var unroundedLineCosts: [Decimal] = []

        for item in recipe.items {
            let unitName: String?
            if let unitId = item.unitId {
                unitName = unitsById[unitId]?.name
            } else {
                unitName = nil
            }

            switch item.kind {
            case .ingredient:
                guard let ingredient = ingredientsById[item.refId] else {
                    lines.append(
                        RecipeCostLine(
                            kind: .ingredient,
                            refId: item.refId,
                            refName: "",
                            quantity: item.quantity,
                            unitName: unitName,
                            quantityInBase: "0",
                            baseUnit: recipe.yieldUnit,
                            presentationId: nil,
                            presentationLabel: nil,
                            pinned: false,
                            brandSource: nil,
                            costCents: 0,
                            missingPrice: true,
                            priceIsStale: false
                        )
                    )
                    unroundedLineCosts.append(0)
                    continue
                }

                let chosenPresId = versionChoices[item.refId]
                let costRes = try computeIngredientLineCost(
                    item: item,
                    ingredient: ingredient,
                    chosenPresentationId: chosenPresId,
                    now: now
                )

                var presentationLabel: String? = nil
                var presentationId: String? = nil

                if let pres = costRes.presentation {
                    presentationId = pres.id
                    let supplierName = pres.supplierId.flatMap { suppliersById[$0]?.name }
                    let baseUnitStr = ingredient.baseUnit.rawValue

                    if let supplierName = supplierName {
                        presentationLabel = "\(pres.brand) · \(supplierName) · \(pres.packageQuantity) \(baseUnitStr)"
                    } else {
                        presentationLabel = "\(pres.brand) · \(pres.packageQuantity) \(baseUnitStr)"
                    }
                }

                let missingPrice = (costRes.presentation == nil || costRes.priceCents == nil)
                unroundedLineCosts.append(costRes.unroundedCost)

                lines.append(
                    RecipeCostLine(
                        kind: .ingredient,
                        refId: ingredient.id,
                        refName: ingredient.name,
                        quantity: item.quantity,
                        unitName: unitName,
                        quantityInBase: Qty.text(costRes.quantityInBase),
                        baseUnit: ingredient.baseUnit,
                        presentationId: presentationId,
                        presentationLabel: presentationLabel,
                        pinned: costRes.pinned,
                        brandSource: costRes.brandSource,
                        costCents: CostingMath.roundToCents(costRes.unroundedCost),
                        missingPrice: missingPrice,
                        priceIsStale: costRes.priceIsStale
                    )
                )

            case .recipe:
                guard let subrecipe = recipesById[item.refId] else {
                    lines.append(
                        RecipeCostLine(
                            kind: .recipe,
                            refId: item.refId,
                            refName: "",
                            quantity: item.quantity,
                            unitName: unitName,
                            quantityInBase: "0",
                            baseUnit: recipe.yieldUnit,
                            presentationId: nil,
                            presentationLabel: nil,
                            pinned: false,
                            brandSource: nil,
                            costCents: 0,
                            missingPrice: true,
                            priceIsStale: false
                        )
                    )
                    unroundedLineCosts.append(0)
                    continue
                }

                let qtyInYield = try convertBetweenBaseUnits(
                    quantity: Qty.decimal(item.quantity) ?? 0,
                    unitId: item.unitId,
                    targetBaseUnit: subrecipe.yieldUnit
                )

                let (subBatchCost, subComplete, subStale) = try computeSubrecipeUnroundedCost(
                    recipeId: item.refId,
                    cache: &cache,
                    depth: 2,
                    now: now
                )

                let yieldQty = Qty.decimal(subrecipe.yieldQuantity) ?? 0
                let lineUnroundedCost: Decimal
                if yieldQty > 0 {
                    lineUnroundedCost = (qtyInYield * subBatchCost) / yieldQty
                } else {
                    lineUnroundedCost = 0
                }

                let missingPrice = !subComplete
                unroundedLineCosts.append(lineUnroundedCost)

                lines.append(
                    RecipeCostLine(
                        kind: .recipe,
                        refId: subrecipe.id,
                        refName: subrecipe.name,
                        quantity: item.quantity,
                        unitName: unitName,
                        quantityInBase: Qty.text(qtyInYield),
                        baseUnit: subrecipe.yieldUnit,
                        presentationId: nil,
                        presentationLabel: nil,
                        pinned: false,
                        brandSource: nil,
                        costCents: CostingMath.roundToCents(lineUnroundedCost),
                        missingPrice: missingPrice,
                        priceIsStale: subStale
                    )
                )
            }
        }

        let unroundedLinesCost = unroundedLineCosts.reduce(0, +)
        let unroundedExtrasCost: Decimal = recipe.extraCosts.reduce(0) { $0 + Decimal($1.costCents) }
        let unroundedBatchCost = unroundedLinesCost + unroundedExtrasCost

        let ingredientsCostCents = CostingMath.roundToCents(unroundedLinesCost)
        let extrasCostCents = CostingMath.roundToCents(unroundedExtrasCost)
        let batchCostCents = CostingMath.roundToCents(unroundedBatchCost)

        let yieldQty = Qty.decimal(recipe.yieldQuantity) ?? 0
        let costPerYieldUnit: String
        if yieldQty > 0 {
            costPerYieldUnit = CostingMath.formatSixDecimals(unroundedBatchCost / yieldQty)
        } else {
            costPerYieldUnit = "0.000000"
        }

        let costPerServingCents: Int?
        if let servings = recipe.servings, servings > 0 {
            costPerServingCents = CostingMath.roundToCents(unroundedBatchCost / Decimal(servings))
        } else {
            costPerServingCents = nil
        }

        let marginPercent = recipe.marginPercent ?? settings.defaultMarginPercent

        let unroundedSuggestedPrice = unroundedBatchCost * (Decimal(1) + Decimal(marginPercent) / Decimal(100))
        let suggestedPriceCents = CostingMath.roundToCents(unroundedSuggestedPrice)

        let suggestedPricePerYieldUnitCents: Int
        if yieldQty > 0 {
            let unroundedSuggestedPerYield = (unroundedBatchCost / yieldQty) * (Decimal(1) + Decimal(marginPercent) / Decimal(100))
            suggestedPricePerYieldUnitCents = CostingMath.roundToCents(unroundedSuggestedPerYield)
        } else {
            suggestedPricePerYieldUnitCents = 0
        }

        let complete = lines.allSatisfy { !$0.missingPrice }
        let hasStalePrices = lines.contains { $0.priceIsStale }

        if !recipe.id.isEmpty && version == nil {
            cache[recipe.id] = (unroundedBatchCost, complete, hasStalePrices)
        }

        return RecipeCost(
            recipeId: recipe.id,
            lines: lines,
            ingredientsCostCents: ingredientsCostCents,
            extrasCostCents: extrasCostCents,
            batchCostCents: batchCostCents,
            costPerYieldUnit: costPerYieldUnit,
            costPerServingCents: costPerServingCents,
            marginPercent: marginPercent,
            suggestedPriceCents: suggestedPriceCents,
            suggestedPricePerYieldUnitCents: suggestedPricePerYieldUnitCents,
            complete: complete,
            hasStalePrices: hasStalePrices,
            versionId: version?.id,
            versionName: version?.name
        )
    }

    public func calculateRecipeCost(
        recipeId: String,
        versionId: String? = nil,
        now: Date = Date()
    ) throws -> RecipeCost {
        guard let recipe = recipesById[recipeId] else {
            throw DomainError.notFound(detail: "Receta no encontrada: \(recipeId)")
        }
        var version: CostVersion? = nil
        if let versionId = versionId {
            guard let v = costVersionsById[versionId], v.recipeId == recipeId else {
                throw DomainError.notFound(detail: "Versión no encontrada: \(versionId)")
            }
            version = v
        }
        return try calculateRecipeCost(recipe: recipe, version: version, now: now)
    }

    // MARK: - Comparación de versiones

    public func compareVersions(
        recipe: Recipe,
        now: Date = Date()
    ) throws -> [CostVersionComparison] {
        var cache: [String: (batchCost: Decimal, isComplete: Bool, hasStalePrices: Bool)] = [:]

        let baseCost = try calculateRecipeCost(recipe: recipe, version: nil, now: now, cache: &cache)

        var results: [CostVersionComparison] = [
            CostVersionComparison(
                versionId: nil,
                name: "Base",
                batchCostCents: baseCost.batchCostCents,
                costPerServingCents: baseCost.costPerServingCents,
                suggestedPriceCents: baseCost.suggestedPriceCents,
                complete: baseCost.complete,
                hasStalePrices: baseCost.hasStalePrices
            )
        ]

        let versions = (costVersionsByRecipe[recipe.id] ?? []).sorted { $0.createdAt < $1.createdAt }
        for v in versions {
            let vCost = try calculateRecipeCost(recipe: recipe, version: v, now: now, cache: &cache)
            results.append(
                CostVersionComparison(
                    versionId: v.id,
                    name: v.name,
                    batchCostCents: vCost.batchCostCents,
                    costPerServingCents: vCost.costPerServingCents,
                    suggestedPriceCents: vCost.suggestedPriceCents,
                    complete: vCost.complete,
                    hasStalePrices: vCost.hasStalePrices
                )
            )
        }

        return results
    }

    public func compareVersions(
        recipeId: String,
        now: Date = Date()
    ) throws -> [CostVersionComparison] {
        guard let recipe = recipesById[recipeId] else {
            throw DomainError.notFound(detail: "Receta no encontrada: \(recipeId)")
        }
        return try compareVersions(recipe: recipe, now: now)
    }
}

extension KitchenData {
    public func costingIndex() -> CostingIndex {
        CostingIndex(data: self)
    }

    public func calculateRecipeCost(
        recipeId: String,
        versionId: String? = nil,
        now: Date = Date()
    ) throws -> RecipeCost {
        try costingIndex().calculateRecipeCost(recipeId: recipeId, versionId: versionId, now: now)
    }

    public func compareVersions(
        recipeId: String,
        now: Date = Date()
    ) throws -> [CostVersionComparison] {
        try costingIndex().compareVersions(recipeId: recipeId, now: now)
    }
}
