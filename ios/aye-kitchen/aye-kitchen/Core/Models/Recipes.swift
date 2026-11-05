import Foundation

// Recetas y costo según docs/api-contract.md (B3).

nonisolated enum RecipeItemKind: String, Codable, Sendable, Hashable {
    case ingredient
    case recipe
}

/// `/recipes/{id}`
nonisolated struct Recipe: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let items: [RecipeItem]
    let extraCosts: [ExtraCost]
    let yieldQuantity: String
    let yieldUnit: BaseUnit
    let servings: Int?
    /// Nulo = usa el margen del workspace.
    let marginPercent: Int?
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct RecipeItem: Decodable, Sendable, Hashable {
    let kind: RecipeItemKind
    let refId: String
    let refName: String
    let quantity: String
    let unitId: String?
    let unitName: String?
    let pinnedPresentationId: String?
}

/// Costos fijos de la receta (caja, gas).
nonisolated struct ExtraCost: Decodable, Sendable, Hashable {
    let name: String
    let costCents: Int
}

/// Item de `GET /recipes/`: la receta más su costo de tanda.
nonisolated struct RecipeListItem: Decodable, Sendable, Hashable, Identifiable {
    let recipe: Recipe
    /// Nulo si el costo no se pudo calcular.
    let batchCostCents: Int?
    let complete: Bool

    var id: String { recipe.id }

    private enum CodingKeys: String, CodingKey {
        case batchCostCents, complete
    }

    init(from decoder: Decoder) throws {
        recipe = try Recipe(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        batchCostCents = try container.decodeIfPresent(Int.self, forKey: .batchCostCents)
        complete = try container.decode(Bool.self, forKey: .complete)
    }
}

/// `GET /recipes/{id}/usable-as-subrecipe`
nonisolated struct UsableSubrecipe: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let yieldUnit: BaseUnit
}

/// `GET /recipes/{id}/cost`
nonisolated struct RecipeCost: Decodable, Sendable, Hashable {
    let recipeId: String
    let lines: [CostLine]
    let ingredientsCostCents: Int
    let extrasCostCents: Int
    let batchCostCents: Int
    let costPerYieldUnit: String
    let costPerServingCents: Int?
    /// El efectivo: el de la receta o el del workspace.
    let marginPercent: Int
    let suggestedPriceCents: Int
    /// Falso si alguna línea, incluso dentro de una subreceta, no tiene precio.
    let complete: Bool
    let hasStalePrices: Bool
    /// B6b. Versión con la que se costeó; nulo = base.
    var versionId: String? = nil
    var versionName: String? = nil
}

/// B6b. De dónde salió la marca de una línea de costo.
nonisolated enum BrandSource: String, Decodable, Sendable, Hashable {
    /// La eligió la versión de costeo.
    case version
    /// Fijada en la línea de la receta.
    case recipe
    /// La vigente del ingrediente.
    case current
}

nonisolated struct CostLine: Decodable, Sendable, Hashable {
    let kind: RecipeItemKind
    let refId: String
    let refName: String
    let quantity: String
    let unitName: String?
    let quantityInBase: String
    let baseUnit: BaseUnit
    let presentationId: String?
    /// "Marca X · Walmart · 1000 g"
    let presentationLabel: String?
    let pinned: Bool
    let costCents: Int
    let missingPrice: Bool
    let priceIsStale: Bool
    /// B6b. Nulo en subrecetas y en líneas sin marca.
    var brandSource: BrandSource? = nil
}

/// `GET/POST/PATCH /recipes/{id}/versions/` (B6b)
nonisolated struct CostVersion: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let recipeId: String
    let name: String
    let choices: [CostVersionChoice]
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct CostVersionChoice: Decodable, Sendable, Hashable {
    let ingredientId: String
    let ingredientName: String
    let presentationId: String
    let brand: String
}

/// Fila de `GET /recipes/{id}/versions/compare` (B6b). `versionId` nulo = la base.
nonisolated struct CostVersionComparison: Decodable, Sendable, Hashable {
    let versionId: String?
    let name: String
    let batchCostCents: Int
    let costPerServingCents: Int?
    let suggestedPriceCents: Int
    let complete: Bool
    let hasStalePrices: Bool
}
