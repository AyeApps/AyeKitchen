import Foundation
import Testing
@testable import KitchenDomain

@Suite("Casos de prueba del costeo (Fixtures)")
struct CostingFixtureTests {
    private static var fixtureURL: URL? {
        Bundle.module.url(forResource: "costing_cases", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "costing_cases", withExtension: "json")
    }

    @Test("Casos generados por el backend (costing_cases.json)",
          .enabled(if: fixtureURL != nil, "Saltada: Fixtures/costing_cases.json no existe aún"))
    func testCostingCases() throws {
        guard let url = Self.fixtureURL else {
            return
        }
        let fileData = try Data(contentsOf: url)
        try executeFixtureData(fileData)
    }

    @Test("Verificación del flujo de fixture en memoria")
    func testInMemoryFixtureFlow() throws {
        let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!
        let harina = Ingredient(id: "ing-1", name: "Harina de trigo", baseUnit: .g, createdAt: now, updatedAt: now)
        let selecta = Presentation(id: "pres-1", ingredientId: harina.id, brand: "Selecta", packageQuantity: "1000",
                                   createdAt: now, updatedAt: now)
        let pr = PriceRecord(id: "pr-1", presentationId: selecta.id, priceCents: 2350,
                             recordedAt: now, createdAt: now, updatedAt: now)
        let receta = Recipe(id: "rec-1", name: "Galletas",
                            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "300")],
                            yieldQuantity: "12", yieldUnit: .pz, createdAt: now, updatedAt: now)
        let data = KitchenData(deviceId: "dev-test", ingredients: [harina], presentations: [selecta],
                               priceRecords: [pr], recipes: [receta])

        let index = CostingIndex(data: data)
        let cost = try index.calculateRecipeCost(recipe: receta, now: now)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let costData = try encoder.encode(cost)
        let costObj = try JSONSerialization.jsonObject(with: costData)

        let kdData = try KitchenCoding.encode(data)
        let kdObj = try JSONSerialization.jsonObject(with: kdData)

        let root: [String: Any] = [
            "generated_at": "2026-11-05T12:00:00.000Z",
            "cases": [
                [
                    "name": "Caso prueba memoria",
                    "now": "2026-11-05T12:00:00.000Z",
                    "data": kdObj,
                    "recipe_costs": [
                        [
                            "recipe_id": "rec-1",
                            "version_id": NSNull(),
                            "expected": costObj
                        ]
                    ]
                ]
            ]
        ]

        let fixtureData = try JSONSerialization.data(withJSONObject: root)
        try executeFixtureData(fixtureData)
    }

    private func executeFixtureData(_ fileData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: fileData) as? [String: Any],
              let cases = root["cases"] as? [[String: Any]] else {
            Issue.record("El archivo costing_cases.json no tiene el formato esperado (llave 'cases')")
            return
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        for caseDict in cases {
            let caseName = caseDict["name"] as? String ?? "Caso sin nombre"

            guard let nowStr = caseDict["now"] as? String,
                  let caseNow = KitchenCoding.parseDate(nowStr) else {
                Issue.record("\(caseName): fecha 'now' ausente o inválida")
                continue
            }

            guard let dataObj = caseDict["data"] else {
                Issue.record("\(caseName): llave 'data' ausente")
                continue
            }

            let dataBytes: Data
            if let dict = dataObj as? [String: Any] {
                dataBytes = try JSONSerialization.data(withJSONObject: dict)
            } else if let str = dataObj as? String {
                dataBytes = Data(str.utf8)
            } else {
                Issue.record("\(caseName): 'data' no es objeto ni string")
                continue
            }

            let kitchenData = try KitchenCoding.decode(dataBytes)
            let index = CostingIndex(data: kitchenData)

            guard let recipeCosts = caseDict["recipe_costs"] as? [[String: Any]] else {
                Issue.record("\(caseName): llave 'recipe_costs' ausente")
                continue
            }

            for rcDict in recipeCosts {
                guard let recipeId = rcDict["recipe_id"] as? String else {
                    Issue.record("\(caseName): 'recipe_id' ausente")
                    continue
                }
                let versionId = rcDict["version_id"] as? String

                guard let expectedObj = rcDict["expected"] as? [String: Any] else {
                    Issue.record("\(caseName) [receta: \(recipeId)]: 'expected' ausente")
                    continue
                }

                let expectedBytes = try JSONSerialization.data(withJSONObject: expectedObj)
                let expected = try decoder.decode(RecipeCost.self, from: expectedBytes)

                let actual = try index.calculateRecipeCost(recipeId: recipeId, versionId: versionId, now: caseNow)

                compareCosts(
                    actual: actual,
                    expected: expected,
                    caseName: caseName,
                    recipeId: recipeId,
                    versionId: versionId
                )
            }
        }
    }

    private func compareCosts(
        actual: RecipeCost,
        expected: RecipeCost,
        caseName: String,
        recipeId: String,
        versionId: String?
    ) {
        let ctx = "\(caseName) [receta: \(recipeId), versión: \(versionId ?? "base")]"

        #expect(actual.recipeId == expected.recipeId, "\(ctx) campo: recipe_id (\(actual.recipeId) != \(expected.recipeId))")
        #expect(actual.ingredientsCostCents == expected.ingredientsCostCents, "\(ctx) campo: ingredients_cost_cents (\(actual.ingredientsCostCents) != \(expected.ingredientsCostCents))")
        #expect(actual.extrasCostCents == expected.extrasCostCents, "\(ctx) campo: extras_cost_cents (\(actual.extrasCostCents) != \(expected.extrasCostCents))")
        #expect(actual.batchCostCents == expected.batchCostCents, "\(ctx) campo: batch_cost_cents (\(actual.batchCostCents) != \(expected.batchCostCents))")

        // Decimales comparados por valor (Qty.decimal)
        let actualYieldCost = Qty.decimal(actual.costPerYieldUnit)
        let expectedYieldCost = Qty.decimal(expected.costPerYieldUnit)
        #expect(actualYieldCost == expectedYieldCost, "\(ctx) campo: cost_per_yield_unit (\(actual.costPerYieldUnit) != \(expected.costPerYieldUnit))")

        #expect(actual.costPerServingCents == expected.costPerServingCents, "\(ctx) campo: cost_per_serving_cents (\(String(describing: actual.costPerServingCents)) != \(String(describing: expected.costPerServingCents)))")
        #expect(actual.marginPercent == expected.marginPercent, "\(ctx) campo: margin_percent (\(actual.marginPercent) != \(expected.marginPercent))")
        #expect(actual.suggestedPriceCents == expected.suggestedPriceCents, "\(ctx) campo: suggested_price_cents (\(actual.suggestedPriceCents) != \(expected.suggestedPriceCents))")
        #expect(actual.suggestedPricePerYieldUnitCents == expected.suggestedPricePerYieldUnitCents, "\(ctx) campo: suggested_price_per_yield_unit_cents (\(actual.suggestedPricePerYieldUnitCents) != \(expected.suggestedPricePerYieldUnitCents))")
        #expect(actual.complete == expected.complete, "\(ctx) campo: complete (\(actual.complete) != \(expected.complete))")
        #expect(actual.hasStalePrices == expected.hasStalePrices, "\(ctx) campo: has_stale_prices (\(actual.hasStalePrices) != \(expected.hasStalePrices))")
        #expect(actual.versionId == expected.versionId, "\(ctx) campo: version_id (\(String(describing: actual.versionId)) != \(String(describing: expected.versionId)))")
        #expect(actual.versionName == expected.versionName, "\(ctx) campo: version_name (\(String(describing: actual.versionName)) != \(String(describing: expected.versionName)))")

        #expect(actual.lines.count == expected.lines.count, "\(ctx) campo: lines.count (\(actual.lines.count) != \(expected.lines.count))")

        let count = min(actual.lines.count, expected.lines.count)
        for i in 0..<count {
            let a = actual.lines[i]
            let e = expected.lines[i]
            let lineCtx = "\(ctx) campo: lines[\(i)]"

            #expect(a.kind == e.kind, "\(lineCtx).kind (\(a.kind) != \(e.kind))")
            #expect(a.refId == e.refId, "\(lineCtx).ref_id (\(a.refId) != \(e.refId))")
            #expect(a.refName == e.refName, "\(lineCtx).ref_name (\(a.refName) != \(e.refName))")

            // quantity comparado por valor
            #expect(Qty.decimal(a.quantity) == Qty.decimal(e.quantity), "\(lineCtx).quantity (\(a.quantity) != \(e.quantity))")

            #expect(a.unitName == e.unitName, "\(lineCtx).unit_name (\(String(describing: a.unitName)) != \(String(describing: e.unitName)))")

            // quantity_in_base comparado por valor
            #expect(Qty.decimal(a.quantityInBase) == Qty.decimal(e.quantityInBase), "\(lineCtx).quantity_in_base (\(a.quantityInBase) != \(e.quantityInBase))")

            #expect(a.baseUnit == e.baseUnit, "\(lineCtx).base_unit (\(a.baseUnit) != \(e.baseUnit))")
            #expect(a.presentationId == e.presentationId, "\(lineCtx).presentation_id (\(String(describing: a.presentationId)) != \(String(describing: e.presentationId)))")
            #expect(a.presentationLabel == e.presentationLabel, "\(lineCtx).presentation_label (\(String(describing: a.presentationLabel)) != \(String(describing: e.presentationLabel)))")
            #expect(a.pinned == e.pinned, "\(lineCtx).pinned (\(a.pinned) != \(e.pinned))")
            #expect(a.brandSource == e.brandSource, "\(lineCtx).brand_source (\(String(describing: a.brandSource)) != \(String(describing: e.brandSource)))")
            #expect(a.costCents == e.costCents, "\(lineCtx).cost_cents (\(a.costCents) != \(e.costCents))")
            #expect(a.missingPrice == e.missingPrice, "\(lineCtx).missing_price (\(a.missingPrice) != \(e.missingPrice))")
            #expect(a.priceIsStale == e.priceIsStale, "\(lineCtx).price_is_stale (\(a.priceIsStale) != \(e.priceIsStale))")
        }
    }
}
