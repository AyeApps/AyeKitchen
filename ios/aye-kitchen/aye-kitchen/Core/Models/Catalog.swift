import Foundation

// Respuestas de catálogo según docs/api-contract.md (B1, B2). Cantidades como string decimal,
// dinero en centavos. "Marca" en la interfaz es una `RemotePresentation` en el código.

/// `/units/` (se llama MeasureUnit para no chocar con `Foundation.Unit`)
nonisolated struct MeasureUnit: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let abbreviation: String
    let baseUnit: RemoteBaseUnit
    let factorToBase: String
    let isSystem: Bool
}

/// `/ingredients/`
nonisolated struct RemoteIngredient: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let baseUnit: RemoteBaseUnit
    let group: String?
    let notes: String?
    let conversions: [RemoteIngredientConversion]
    let createdAt: Date
    let updatedAt: Date
    /// B6a. Marcas activas del ingrediente. Opcional para que los previews y servidores viejos sigan funcionando.
    var brandsCount: Int? = nil
    /// B6a. La marca vigente (la que usa el costeo por defecto); nulo si ninguna tiene precio.
    var currentBrand: IngredientCurrentBrand? = nil
}

/// Resumen de la marca vigente de un ingrediente (B6a).
nonisolated struct IngredientCurrentBrand: Decodable, Sendable, Hashable {
    let presentationId: String
    let brand: String
    let supplierName: String?
    /// Centavos por g/ml/pz, 6 decimales, solo para mostrar.
    let costPerBaseUnit: String?
}

/// Equivalencia propia: "1 taza de harina = 125 g".
nonisolated struct RemoteIngredientConversion: Decodable, Sendable, Hashable {
    let unitId: String
    let unitName: String
    let quantityInBase: String
}

/// `/suppliers/`
nonisolated struct RemoteSupplier: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

/// `/presentations/`
nonisolated struct RemotePresentation: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let ingredientId: String
    let ingredientName: String
    let brand: String
    let supplierId: String?
    let supplierName: String?
    let packageQuantity: String
    let baseUnit: RemoteBaseUnit
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

/// Item de `GET /presentations/stale`: una `RemotePresentation` más cuántas recetas la usan.
nonisolated struct StalePresentation: Decodable, Sendable, Hashable, Identifiable {
    let presentation: RemotePresentation
    let usedInRecipes: Int

    var id: String { presentation.id }

    private enum CodingKeys: String, CodingKey {
        case usedInRecipes
    }

    init(from decoder: Decoder) throws {
        presentation = try RemotePresentation(from: decoder)
        usedInRecipes = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .usedInRecipes)
    }
}

/// `/presentations/{id}/prices`
nonisolated struct RemotePriceRecord: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let priceCents: Int
    let recordedAt: Date
    let note: String?
}
