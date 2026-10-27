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
}
