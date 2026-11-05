import Foundation

// MARK: - Reglas de Recetas y Versiones de Costeo (K2b)

extension KitchenData {

    // MARK: - Recetas (Escrituras)

    /// Crea una nueva receta activa.
    ///
    /// Valida en el orden del contrato:
    /// 1. Nombre no vacío y no repetido entre recetas activas (`duplicateName`).
    /// 2. Referencias activas, `pinnedPresentationId` válido, unidades existentes, cantidades > 0, convertibilidad y rendimiento (`validateRecipeItemsAndYield`).
    /// 3. Ciclos (`recipeCycle`) y profundidad máxima de 10 niveles (`recipeTooDeep`).
    @discardableResult
    public mutating func createRecipe(
        name: String,
        description: String? = nil,
        items: [RecipeItem] = [],
        extraCosts: [ExtraCost] = [],
        yieldQuantity: String,
        yieldUnit: BaseUnit,
        servings: Int? = nil,
        marginPercent: Int? = nil,
        photoId: String? = nil,
        ctx: MutationContext
    ) throws -> Recipe {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw DomainError.invalidValue(detail: "El nombre no puede estar vacío")
        }

        if recipes.contains(where: { $0.isActive && $0.name.normalizedName == cleanName.normalizedName }) {
            throw DomainError.duplicateName(detail: "Ya existe una receta con ese nombre")
        }

        guard let yieldQty = Qty.decimal(yieldQuantity) else {
            throw DomainError.invalidReference(detail: "La cantidad de rendimiento debe ser mayor que cero")
        }

        try validateRecipeItemsAndYield(items: items, yieldQuantity: yieldQty)

        let subrecipeIds = items.filter { $0.kind == .recipe }.map { $0.refId }
        try validateCyclesAndDepth(targetRecipeId: nil, newSubrecipeIds: subrecipeIds)

        if let servings = servings, servings < 1 {
            throw DomainError.invalidValue(detail: "Las porciones deben ser al menos 1")
        }
        if let marginPercent = marginPercent, marginPercent < 0 || marginPercent > 1000 {
            throw DomainError.invalidValue(detail: "El margen debe estar entre 0 y 1000")
        }

        let cleanDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDescription = (cleanDescription?.isEmpty == false) ? cleanDescription : nil

        let cleanExtraCosts = extraCosts.map {
            ExtraCost(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), costCents: $0.costCents)
        }

        let id = ctx.newId()
        let newRecipe = Recipe(
            id: id,
            name: cleanName,
            description: finalDescription,
            items: items,
            extraCosts: cleanExtraCosts,
            yieldQuantity: yieldQuantity,
            yieldUnit: yieldUnit,
            servings: servings,
            marginPercent: marginPercent,
            photoId: photoId,
            createdAt: ctx.now,
            updatedAt: ctx.now,
            deletedAt: nil
        )

        recipes.append(newRecipe)
        return newRecipe
    }

    /// Edita parcialmente una receta activa.
    ///
    /// Si `items` o `extraCosts` vienen en la edición, reemplazan por completo la lista previa.
    /// Al cambiar `items`, quita de sus versiones activas las elecciones de ingredientes que ya no están.
    @discardableResult
    public mutating func updateRecipe(
        id: String,
        name: String? = nil,
        description: String?? = nil,
        items: [RecipeItem]? = nil,
        extraCosts: [ExtraCost]? = nil,
        yieldQuantity: String? = nil,
        yieldUnit: BaseUnit? = nil,
        servings: Int?? = nil,
        marginPercent: Int?? = nil,
        photoId: String?? = nil,
        ctx: MutationContext
    ) throws -> Recipe {
        guard let idx = recipes.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        var recipe = recipes[idx]

        // 1. Validar nombre si cambia
        var cleanName: String? = nil
        if let newName = name {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidValue(detail: "El nombre no puede estar vacío")
            }
            if recipes.contains(where: { $0.isActive && $0.id != id && $0.name.normalizedName == trimmed.normalizedName }) {
                throw DomainError.duplicateName(detail: "Ya existe una receta con ese nombre")
            }
            cleanName = trimmed
        }

        // 2. Rendimiento efectivo para validaciones
        let effectiveYieldQty: Decimal
        if let yq = yieldQuantity {
            guard let parsed = Qty.decimal(yq), parsed > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad de rendimiento debe ser mayor que cero")
            }
            effectiveYieldQty = parsed
        } else {
            effectiveYieldQty = Qty.decimal(recipe.yieldQuantity) ?? 0
        }

        // 3. Validar items y ciclos si cambian
        if let newItems = items {
            try validateRecipeItemsAndYield(items: newItems, yieldQuantity: effectiveYieldQty)
            let subrecipeIds = newItems.filter { $0.kind == .recipe }.map { $0.refId }
            try validateCyclesAndDepth(targetRecipeId: id, newSubrecipeIds: subrecipeIds)
        } else if yieldQuantity != nil {
            if effectiveYieldQty <= 0 {
                throw DomainError.invalidReference(detail: "La cantidad de rendimiento debe ser mayor que cero")
            }
        }

        // 4. Validar servings y marginPercent si cambian
        if let s = servings, let servingsVal = s, servingsVal < 1 {
            throw DomainError.invalidValue(detail: "Las porciones deben ser al menos 1")
        }
        if let m = marginPercent, let marginVal = m, marginVal < 0 || marginVal > 1000 {
            throw DomainError.invalidValue(detail: "El margen debe estar entre 0 y 1000")
        }

        // --- Todas las validaciones pasaron, aplicar mutaciones ---

        if let cleanName = cleanName {
            recipe.name = cleanName
        }
        if let yq = yieldQuantity {
            recipe.yieldQuantity = yq
        }
        if let yu = yieldUnit {
            recipe.yieldUnit = yu
        }
        if let newDesc = description {
            if let text = newDesc?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                recipe.description = text
            } else {
                recipe.description = nil
            }
        }
        if let s = servings {
            recipe.servings = s
        }
        if let m = marginPercent {
            recipe.marginPercent = m
        }
        if let p = photoId {
            recipe.photoId = p
        }
        if let extraCosts = extraCosts {
            recipe.extraCosts = extraCosts.map {
                ExtraCost(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), costCents: $0.costCents)
            }
        }

        if let newItems = items {
            recipe.items = newItems
            // Quitar de sus versiones activas las elecciones de ingredientes que ya no están
            let activeIngIds = Set(newItems.filter { $0.kind == .ingredient }.map { $0.refId })
            for vIdx in costVersions.indices {
                if costVersions[vIdx].recipeId == id && costVersions[vIdx].isActive {
                    let filtered = costVersions[vIdx].choices.filter { activeIngIds.contains($0.ingredientId) }
                    if filtered.count != costVersions[vIdx].choices.count {
                        costVersions[vIdx].choices = filtered
                        costVersions[vIdx].updatedAt = ctx.now
                    }
                }
            }
        }

        recipe.updatedAt = ctx.now
        recipes[idx] = recipe
        return recipe
    }

    /// Borrado lógico de una receta activa y de sus versiones de costeo asociadas.
    ///
    /// Si la receta se usa como subreceta en alguna otra receta activa, lanza `DomainError.inUse`.
    public mutating func deleteRecipe(
        id: String,
        ctx: MutationContext
    ) throws {
        guard let idx = recipes.activeIndex(of: id) else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        let isUsed = recipes.contains { r in
            r.isActive && r.items.contains { it in
                it.kind == .recipe && it.refId == id
            }
        }
        if isUsed {
            throw DomainError.inUse(detail: "La receta está en uso como subreceta en recetas activas")
        }

        recipes[idx].deletedAt = ctx.now
        recipes[idx].updatedAt = ctx.now

        for vIdx in costVersions.indices {
            if costVersions[vIdx].recipeId == id && costVersions[vIdx].isActive {
                costVersions[vIdx].deletedAt = ctx.now
                costVersions[vIdx].updatedAt = ctx.now
            }
        }
    }

    // MARK: - Versiones de Costeo (Escrituras)

    /// Crea una nueva versión de costeo para una receta activa.
    @discardableResult
    public mutating func createCostVersion(
        recipeId: String,
        name: String,
        choices: [CostVersionChoice] = [],
        ctx: MutationContext
    ) throws -> CostVersion {
        guard let recipe = recipes.active(recipeId) else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw DomainError.invalidValue(detail: "El nombre no puede estar vacío")
        }
        if cleanName.lowercased() == "base" {
            throw DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")
        }
        if costVersions.contains(where: { $0.isActive && $0.recipeId == recipeId && $0.name.normalizedName == cleanName.normalizedName }) {
            throw DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")
        }

        try validateCostVersionChoices(recipe: recipe, choices: choices)

        let id = ctx.newId()
        let version = CostVersion(
            id: id,
            recipeId: recipeId,
            name: cleanName,
            choices: choices,
            createdAt: ctx.now,
            updatedAt: ctx.now,
            deletedAt: nil
        )

        costVersions.append(version)
        return version
    }

    /// Edita parcialmente una versión de costeo activa. Si se pasa `choices`, reemplaza la lista completa.
    @discardableResult
    public mutating func updateCostVersion(
        recipeId: String,
        versionId: String,
        name: String? = nil,
        choices: [CostVersionChoice]? = nil,
        ctx: MutationContext
    ) throws -> CostVersion {
        guard let recipe = recipes.active(recipeId) else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        guard let vIdx = costVersions.firstIndex(where: { $0.id == versionId && $0.recipeId == recipeId && $0.isActive }) else {
            throw DomainError.notFound(detail: "Versión no encontrada")
        }

        var version = costVersions[vIdx]

        if let newName = name {
            let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                throw DomainError.invalidValue(detail: "El nombre no puede estar vacío")
            }
            if clean.lowercased() == "base" {
                throw DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")
            }
            if costVersions.contains(where: { $0.isActive && $0.recipeId == recipeId && $0.id != versionId && $0.name.normalizedName == clean.normalizedName }) {
                throw DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")
            }
            version.name = clean
        }

        if let newChoices = choices {
            try validateCostVersionChoices(recipe: recipe, choices: newChoices)
            version.choices = newChoices
        }

        version.updatedAt = ctx.now
        costVersions[vIdx] = version
        return version
    }

    /// Borrado lógico de una versión de costeo activa.
    public mutating func deleteCostVersion(
        recipeId: String,
        versionId: String,
        ctx: MutationContext
    ) throws {
        guard recipes.active(recipeId) != nil else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        guard let vIdx = costVersions.firstIndex(where: { $0.id == versionId && $0.recipeId == recipeId && $0.isActive }) else {
            throw DomainError.notFound(detail: "Versión no encontrada")
        }

        costVersions[vIdx].deletedAt = ctx.now
        costVersions[vIdx].updatedAt = ctx.now
    }

    // MARK: - Validaciones privadas

    private func validateRecipeItemsAndYield(
        items: [RecipeItem],
        yieldQuantity: Decimal
    ) throws {
        let index = costingIndex()

        for item in items {
            // Paso 1: Referencias activas
            let ing: Ingredient?
            let subrec: Recipe?

            switch item.kind {
            case .ingredient:
                guard let found = ingredients.active(item.refId) else {
                    throw DomainError.invalidReference(detail: "Ingrediente no encontrado: \(item.refId)")
                }
                ing = found
                subrec = nil
            case .recipe:
                guard let found = recipes.active(item.refId) else {
                    throw DomainError.invalidReference(detail: "Receta no encontrada: \(item.refId)")
                }
                subrec = found
                ing = nil
            }

            // Paso 2: pinnedPresentationId solo en ingredientes y de ese ingrediente
            if let pinnedId = item.pinnedPresentationId, !pinnedId.isEmpty {
                if item.kind != .ingredient {
                    throw DomainError.invalidReference(detail: "pinned_presentation_id solo se permite en líneas de ingrediente")
                }
                guard let pres = presentations.active(pinnedId) else {
                    throw DomainError.invalidReference(detail: "Presentación fijada no encontrada")
                }
                if pres.ingredientId != item.refId {
                    throw DomainError.invalidReference(detail: "La presentación no pertenece a este ingrediente o no existe")
                }
            }

            // Paso 3: unitId si viene debe existir
            if let unitId = item.unitId, !unitId.isEmpty {
                guard index.unitsById[unitId] != nil else {
                    throw DomainError.invalidReference(detail: "Unidad no encontrada: \(unitId)")
                }
            }

            // Paso 4: Cantidad mayor que cero
            guard let qty = Qty.decimal(item.quantity), qty > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }

            // Paso 5: Convertibilidad
            if let ing = ing {
                _ = try index.convertToBase(quantity: qty, unitId: item.unitId, ingredient: ing)
            } else if let subrec = subrec {
                _ = try index.convertBetweenBaseUnits(quantity: qty, unitId: item.unitId, targetBaseUnit: subrec.yieldUnit)
            }
        }

        // Rendimiento mayor que cero
        guard yieldQuantity > 0 else {
            throw DomainError.invalidReference(detail: "La cantidad de rendimiento debe ser mayor que cero")
        }
    }

    private func validateCyclesAndDepth(
        targetRecipeId: String?,
        newSubrecipeIds: [String]
    ) throws {
        if let target = targetRecipeId, newSubrecipeIds.contains(target) {
            throw DomainError.recipeCycle(detail: "La receta se usaría a sí misma directa o indirectamente")
        }

        var adj: [String: [String]] = [:]
        for r in recipes where r.isActive {
            adj[r.id] = r.items.filter { $0.kind == .recipe }.map { $0.refId }
        }

        let rootKey = targetRecipeId ?? "__new__"
        adj[rootKey] = newSubrecipeIds

        func dfsCycle(nodeId: String, currentPath: [String]) throws {
            if let target = targetRecipeId, nodeId == target {
                throw DomainError.recipeCycle(detail: "La receta se usaría a sí misma directa o indirectamente")
            }
            if currentPath.contains(nodeId) {
                throw DomainError.recipeCycle(detail: "Se detectó un ciclo en las subrecetas")
            }
            let nextPath = currentPath + [nodeId]
            for child in adj[nodeId] ?? [] {
                try dfsCycle(nodeId: child, currentPath: nextPath)
            }
        }

        let initialPath = [rootKey]
        for child in newSubrecipeIds {
            try dfsCycle(nodeId: child, currentPath: initialPath)
        }

        var depthMemo: [String: Int] = [:]

        func getMaxDepth(node: String, currentDepth: Int = 1) -> Int {
            if currentDepth > 11 {
                return 11
            }
            if let cached = depthMemo[node] {
                return cached
            }
            let children = adj[node] ?? []
            if children.isEmpty {
                depthMemo[node] = 1
                return 1
            }
            let maxChild = children.map { getMaxDepth(node: $0, currentDepth: currentDepth + 1) }.max() ?? 0
            let res = 1 + maxChild
            depthMemo[node] = res
            return res
        }

        for node in adj.keys {
            if getMaxDepth(node: node) > 10 {
                throw DomainError.recipeTooDeep(detail: "La receta excede la profundidad máxima permitida de 10 niveles")
            }
        }
    }

    private func validateCostVersionChoices(
        recipe: Recipe,
        choices: [CostVersionChoice]
    ) throws {
        let recipeIngredientIds = Set(recipe.items.filter { $0.kind == .ingredient }.map { $0.refId })
        var seenIngredients: Set<String> = []

        for ch in choices {
            if seenIngredients.contains(ch.ingredientId) {
                throw DomainError.invalidReference(detail: "Ingrediente repetido en las elecciones")
            }
            seenIngredients.insert(ch.ingredientId)

            if !recipeIngredientIds.contains(ch.ingredientId) {
                throw DomainError.invalidReference(detail: "El ingrediente no pertenece a la receta")
            }

            guard let pres = presentations.active(ch.presentationId) else {
                throw DomainError.invalidReference(detail: "Presentación no encontrada")
            }

            if pres.ingredientId != ch.ingredientId {
                let ing = ingredients.active(ch.ingredientId)
                let detail = (ing != nil) ? "Esa marca no es de \(ing!.name)" : "Esa marca no es de este ingrediente"
                throw DomainError.invalidReference(detail: detail)
            }
        }
    }
}
