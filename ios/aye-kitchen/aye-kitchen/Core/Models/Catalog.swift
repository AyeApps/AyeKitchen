import Foundation

// Respuestas de catálogo según docs/api-contract.md (B1, B2). Cantidades como string decimal,
// dinero en centavos. "Marca" en la interfaz es una `Presentation` en el código.

/// `/units/` (se llama MeasureUnit para no chocar con `Foundation.Unit`)
nonisolated struct MeasureUnit: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let abbreviation: String
    let baseUnit: BaseUnit
    let factorToBase: String
    let isSystem: Bool
}

/// `/ingredients/`
nonisolated struct Ingredient: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let baseUnit: BaseUnit
    let group: String?
    let notes: String?
    let conversions: [IngredientConversion]
    let createdAt: Date
    let updatedAt: Date
}

/// Equivalencia propia: "1 taza de harina = 125 g".
nonisolated struct IngredientConversion: Decodable, Sendable, Hashable {
    let unitId: String
    let unitName: String
    let quantityInBase: String
}

/// `/suppliers/`
nonisolated struct Supplier: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

/// `/presentations/`
nonisolated struct Presentation: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let ingredientId: String
    let ingredientName: String
    let brand: String
    let supplierId: String?
    let supplierName: String?
    let packageQuantity: String
    let baseUnit: BaseUnit
    let barcode: String?
    let latestPriceCents: Int?
    let latestPriceAt: Date?
    /// Centavos por g/ml/pz, solo para mostrar.
    let costPerBaseUnit: String?
    /// Es la que usa el costeo por defecto para su ingrediente.
    let isCurrent: Bool
    let priceAgeDays: Int?
    let priceIsStale: Bool
    let createdAt: Date
    let updatedAt: Date
}

/// Item de `GET /presentations/stale`: una `Presentation` más cuántas recetas la usan.
nonisolated struct StalePresentation: Decodable, Sendable, Hashable, Identifiable {
    let presentation: Presentation
    let usedInRecipes: Int

    var id: String { presentation.id }

    private enum CodingKeys: String, CodingKey {
        case usedInRecipes
    }

    init(from decoder: Decoder) throws {
        presentation = try Presentation(from: decoder)
        usedInRecipes = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .usedInRecipes)
    }
}

/// `/presentations/{id}/prices`
nonisolated struct PriceRecord: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let priceCents: Int
    let recordedAt: Date
    let note: String?
}
