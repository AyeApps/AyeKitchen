#if DEBUG
import Foundation

extension Recipe {
    /// Receta de ejemplo del contrato: Harina 1000 g a $23.50, línea de 300 g -> $7.05.
    static let mockContractExample = Recipe(
        id: "recipe-contract-1",
        name: "Pastel clásico de vainilla",
        description: "Receta base para pasteles de cumpleaños.",
        items: [
            RecipeItem(
                kind: .ingredient,
                refId: "ing-harina",
                refName: "Harina de trigo",
                quantity: "300",
                unitId: "unit-g",
                unitName: "g",
                pinnedPresentationId: "pres-harina-1"
            )
        ],
        extraCosts: [
            ExtraCost(name: "Caja para pastel", costCents: 1500)
        ],
        yieldQuantity: "1",
        yieldUnit: .pz,
        servings: 12,
        marginPercent: 30,
        createdAt: Date.now.addingTimeInterval(-86400 * 5),
        updatedAt: Date.now
    )

    static let mockIncomplete = Recipe(
        id: "recipe-incomplete-1",
        name: "Pastel de zanahoria con nuez",
        description: "Pastel húmedo con betún de queso crema.",
        items: [
            RecipeItem(
                kind: .ingredient,
                refId: "ing-nuez",
                refName: "Nuez picada",
                quantity: "150",
                unitId: "unit-g",
                unitName: "g",
                pinnedPresentationId: nil
            )
        ],
        extraCosts: [],
        yieldQuantity: "1",
        yieldUnit: .pz,
        servings: 10,
        marginPercent: 30,
        createdAt: Date.now.addingTimeInterval(-86400 * 3),
        updatedAt: Date.now
    )
}

extension RecipeCost {
    /// Desglose de costo del contrato: Harina 300 g cuesta $7.05 (705 cents) + Caja $15.00 (1500 cents).
    /// Total tanda: $22.05 (2205 cents). Con margen 30%: $28.67 (2867 cents).
    static let mockContractExample = RecipeCost(
        recipeId: "recipe-contract-1",
        lines: [
            CostLine(
                kind: .ingredient,
                refId: "ing-harina",
                refName: "Harina de trigo",
                quantity: "300",
                unitName: "g",
                quantityInBase: "300",
                baseUnit: .g,
                presentationId: "pres-harina-1",
                presentationLabel: "Marca X · Walmart · 1000 g",
                pinned: true,
                costCents: 705,
                missingPrice: false,
                priceIsStale: false
            )
        ],
        ingredientsCostCents: 705,
        extrasCostCents: 1500,
        batchCostCents: 2205,
        costPerYieldUnit: "22.050000",
        costPerServingCents: 184,
        marginPercent: 30,
        suggestedPriceCents: 2867,
        complete: true,
        hasStalePrices: false
    )

    /// Desglose con línea sin precio (missingPrice) y línea con precio viejo (priceIsStale),
    /// además de una subreceta.
    static let mockWithWarnings = RecipeCost(
        recipeId: "recipe-warnings-1",
        lines: [
            CostLine(
                kind: .ingredient,
                refId: "ing-harina",
                refName: "Harina de trigo",
                quantity: "300",
                unitName: "g",
                quantityInBase: "300",
                baseUnit: .g,
                presentationId: "pres-harina-1",
                presentationLabel: "San Antonio · Chedraui · 1000 g",
                pinned: false,
                costCents: 705,
                missingPrice: false,
                priceIsStale: true
            ),
            CostLine(
                kind: .recipe,
                refId: "recipe-contract-1",
                refName: "Bizcocho básico",
                quantity: "300",
                unitName: "g",
                quantityInBase: "300",
                baseUnit: .g,
                presentationId: nil,
                presentationLabel: nil,
                pinned: false,
                costCents: 2100,
                missingPrice: false,
                priceIsStale: false
            ),
            CostLine(
                kind: .ingredient,
                refId: "ing-nuez",
                refName: "Nuez de castilla",
                quantity: "150",
                unitName: "g",
                quantityInBase: "150",
                baseUnit: .g,
                presentationId: nil,
                presentationLabel: nil,
                pinned: false,
                costCents: 0,
                missingPrice: true,
                priceIsStale: false
            )
        ],
        ingredientsCostCents: 705,
        extrasCostCents: 1500,
        batchCostCents: 4305,
        costPerYieldUnit: "43.050000",
        costPerServingCents: 359,
        marginPercent: 30,
        suggestedPriceCents: 5597,
        complete: false,
        hasStalePrices: true
    )
}

extension RecipeListItem {
    static let mockListItems: [RecipeListItem] = [
        makeMock(
            id: "recipe-contract-1",
            name: "Pastel clásico de vainilla",
            batchCostCents: 2205,
            complete: true
        ),
        makeMock(
            id: "recipe-incomplete-1",
            name: "Pastel de zanahoria con nuez",
            batchCostCents: nil,
            complete: false
        ),
        makeMock(
            id: "recipe-chocolate-1",
            name: "Pastel de tres leches chocolate",
            batchCostCents: 18450,
            complete: true
        ),
        makeMock(
            id: "recipe-cheesecake-1",
            name: "Cheesecake de frutos rojos",
            batchCostCents: 21000,
            complete: false
        )
    ]

    private static func makeMock(id: String, name: String, batchCostCents: Int?, complete: Bool) -> RecipeListItem {
        let json = """
        {
            "id": "\(id)",
            "name": "\(name)",
            "description": null,
            "items": [],
            "extra_costs": [],
            "yield_quantity": "1",
            "yield_unit": "pz",
            "servings": 12,
            "margin_percent": 30,
            "created_at": "2026-10-01T12:00:00Z",
            "updated_at": "2026-10-01T12:00:00Z",
            "batch_cost_cents": \(batchCostCents.map { String($0) } ?? "null"),
            "complete": \(complete)
        }
        """.data(using: .utf8)!
        return try! JSONCoding.decode(RecipeListItem.self, from: json)
    }
}
#endif
