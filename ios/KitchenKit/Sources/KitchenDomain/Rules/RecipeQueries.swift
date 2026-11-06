import Foundation

// MARK: - Modelos de Consulta de Recetas (K2b)

/// Detalle de una línea de receta para listas y vistas.
public struct RecipeItemDetail: Codable, Sendable, Hashable {
    public var kind: RecipeItemKind
    public var refId: String
    public var refName: String
    public var quantity: String
    public var unitId: String?
    public var unitName: String?
    public var pinnedPresentationId: String?

    public init(
        kind: RecipeItemKind,
        refId: String,
        refName: String,
        quantity: String,
        unitId: String? = nil,
        unitName: String? = nil,
        pinnedPresentationId: String? = nil
    ) {
        self.kind = kind
        self.refId = refId
        self.refName = refName
        self.quantity = quantity
        self.unitId = unitId
        self.unitName = unitName
        self.pinnedPresentationId = pinnedPresentationId
    }
}

/// Elemento de la lista de recetas, con costo y completitud calculados.
public struct RecipeListItem: Sendable, Hashable, Identifiable {
    public var id: String { recipe.id }
    public var name: String { recipe.name }
    public var description: String? { recipe.description }
    public var items: [RecipeItemDetail]
    public var extraCosts: [ExtraCost] { recipe.extraCosts }
    public var yieldQuantity: String { recipe.yieldQuantity }
    public var yieldUnit: BaseUnit { recipe.yieldUnit }
    public var servings: Int? { recipe.servings }
    public var marginPercent: Int? { recipe.marginPercent }
    public var referenceIds: [String] { recipe.referenceIds ?? [] }
    public var batchCostCents: Int?
    public var complete: Bool
    public var createdAt: Date { recipe.createdAt }
    public var updatedAt: Date { recipe.updatedAt }
    public var recipe: Recipe

    public init(
        recipe: Recipe,
        items: [RecipeItemDetail],
        batchCostCents: Int?,
        complete: Bool
    ) {
        self.recipe = recipe
        self.items = items
        self.batchCostCents = batchCostCents
        self.complete = complete
    }
}

/// Receta que se puede usar como subreceta de otra sin crear ciclo.
public struct RecipeUsableSubrecipe: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var yieldUnit: BaseUnit

    public init(id: String, name: String, yieldUnit: BaseUnit) {
        self.id = id
        self.name = name
        self.yieldUnit = yieldUnit
    }
}

/// Elección de marca en una versión de costeo con nombres resueltos.
public struct RecipeCostVersionChoiceDetail: Sendable, Hashable {
    public var ingredientId: String
    public var ingredientName: String
    public var presentationId: String
    public var brand: String

    public init(
        ingredientId: String,
        ingredientName: String,
        presentationId: String,
        brand: String
    ) {
        self.ingredientId = ingredientId
        self.ingredientName = ingredientName
        self.presentationId = presentationId
        self.brand = brand
    }
}

/// Detalle de una versión de costeo con nombres de ingredientes y marcas.
public struct RecipeCostVersionDetail: Sendable, Hashable, Identifiable {
    public var id: String { version.id }
    public var recipeId: String { version.recipeId }
    public var name: String { version.name }
    public var choices: [RecipeCostVersionChoiceDetail]
    public var createdAt: Date { version.createdAt }
    public var updatedAt: Date { version.updatedAt }
    public var version: CostVersion

    public init(version: CostVersion, choices: [RecipeCostVersionChoiceDetail]) {
        self.version = version
        self.choices = choices
    }
}

// MARK: - Consultas sobre KitchenData

extension KitchenData {

    /// Busca una receta activa por id.
    public func recipe(id: String) -> Recipe? {
        recipes.active(id)
    }

    /// Lista de recetas activas con búsqueda opcional por nombre, ordenadas alfabéticamente por nombre.
    ///
    /// Cada receta incluye `batchCostCents` y `complete` del costeo. Si el cálculo del costo falla
    /// (por ejemplo por unidad no convertible), la receta sale con costo nulo y `complete` en falso,
    /// como hace el backend.
    public func listRecipes(
        query: String? = nil,
        now: Date = Date()
    ) -> [RecipeListItem] {
        let index = costingIndex()
        var costCache: [String: (batchCost: Decimal, isComplete: Bool, hasStalePrices: Bool)] = [:]

        var filtered = recipes.filter { $0.isActive }
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(q) }
        }

        filtered.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Mapeo de nombres para items (incluyendo elementos borrados para conservar historial)
        var ingNames: [String: String] = [:]
        for ing in ingredients {
            ingNames[ing.id] = ing.name
        }
        var recNames: [String: String] = [:]
        for rec in recipes {
            recNames[rec.id] = rec.name
        }
        var unitNames: [String: String] = [:]
        for u in SystemUnits.all {
            unitNames[u.id] = u.name
        }
        for u in units {
            unitNames[u.id] = u.name
        }

        return filtered.map { rec in
            let itemDetails: [RecipeItemDetail] = rec.items.map { it in
                let refName: String
                switch it.kind {
                case .ingredient:
                    refName = ingNames[it.refId] ?? ""
                case .recipe:
                    refName = recNames[it.refId] ?? ""
                }
                let unitName = it.unitId.flatMap { unitNames[$0] }
                return RecipeItemDetail(
                    kind: it.kind,
                    refId: it.refId,
                    refName: refName,
                    quantity: it.quantity,
                    unitId: it.unitId,
                    unitName: unitName,
                    pinnedPresentationId: it.pinnedPresentationId
                )
            }

            let batchCostCents: Int?
            let complete: Bool

            do {
                let cost = try index.calculateRecipeCost(recipe: rec, version: nil, now: now, cache: &costCache)
                batchCostCents = cost.batchCostCents
                complete = cost.complete
            } catch {
                batchCostCents = nil
                complete = false
            }

            return RecipeListItem(
                recipe: rec,
                items: itemDetails,
                batchCostCents: batchCostCents,
                complete: complete
            )
        }
    }

    /// Recetas activas que se pueden agregar como subreceta de `recipeId` sin crear ciclos.
    /// Excluye `recipeId` y a toda receta que directa o indirectamente contenga a `recipeId`.
    public func usableSubrecipes(
        for recipeId: String
    ) throws -> [RecipeUsableSubrecipe] {
        guard recipes.active(recipeId) != nil else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        let activeRecipes = recipes.filter { $0.isActive }
        var parentsMap: [String: [String]] = [:]
        for r in activeRecipes {
            for it in r.items where it.kind == .recipe {
                parentsMap[it.refId, default: []].append(r.id)
            }
        }

        var excluded: Set<String> = [recipeId]
        var queue: [String] = [recipeId]
        while !queue.isEmpty {
            let curr = queue.removeFirst()
            for parentId in parentsMap[curr] ?? [] {
                if !excluded.contains(parentId) {
                    excluded.insert(parentId)
                    queue.append(parentId)
                }
            }
        }

        return activeRecipes
            .filter { !excluded.contains($0.id) }
            .map { RecipeUsableSubrecipe(id: $0.id, name: $0.name, yieldUnit: $0.yieldUnit) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Versiones de costeo activas de una receta, ordenadas por `createdAt` ascendente.
    public func costVersions(
        for recipeId: String
    ) throws -> [RecipeCostVersionDetail] {
        guard recipes.active(recipeId) != nil else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        let activeVersions = costVersions
            .filter { $0.recipeId == recipeId && $0.isActive }
            .sorted { $0.createdAt < $1.createdAt }

        var ingNames: [String: String] = [:]
        for ing in ingredients {
            ingNames[ing.id] = ing.name
        }
        var presBrands: [String: String] = [:]
        for pres in presentations {
            presBrands[pres.id] = pres.brand
        }

        return activeVersions.map { v in
            let choiceDetails = v.choices.map { c in
                RecipeCostVersionChoiceDetail(
                    ingredientId: c.ingredientId,
                    ingredientName: ingNames[c.ingredientId] ?? "",
                    presentationId: c.presentationId,
                    brand: presBrands[c.presentationId] ?? ""
                )
            }
            return RecipeCostVersionDetail(version: v, choices: choiceDetails)
        }
    }

    /// Detalle de una versión de costeo activa por id.
    public func costVersion(
        recipeId: String,
        versionId: String
    ) throws -> RecipeCostVersionDetail {
        guard recipes.active(recipeId) != nil else {
            throw DomainError.notFound(detail: "Receta no encontrada")
        }

        guard let v = costVersions.first(where: { $0.id == versionId && $0.recipeId == recipeId && $0.isActive }) else {
            throw DomainError.notFound(detail: "Versión no encontrada")
        }

        var ingNames: [String: String] = [:]
        for ing in ingredients {
            ingNames[ing.id] = ing.name
        }
        var presBrands: [String: String] = [:]
        for pres in presentations {
            presBrands[pres.id] = pres.brand
        }

        let choiceDetails = v.choices.map { c in
            RecipeCostVersionChoiceDetail(
                ingredientId: c.ingredientId,
                ingredientName: ingNames[c.ingredientId] ?? "",
                presentationId: c.presentationId,
                brand: presBrands[c.presentationId] ?? ""
            )
        }
        return RecipeCostVersionDetail(version: v, choices: choiceDetails)
    }
}
