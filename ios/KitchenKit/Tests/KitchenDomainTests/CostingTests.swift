import Foundation
import Testing
@testable import KitchenDomain

@Suite("Costeo de recetas en KitchenDomain")
struct CostingTests {
    private let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    // MARK: - 1. 705 centavos (ejemplo canónico del contrato)

    @Test("705 centavos: Harina 1000 g a $23.50, línea de 300 g")
    func example705Cents() throws {
        let harina = Ingredient(id: "ing-harina", name: "Harina de trigo", baseUnit: .g,
                                createdAt: now, updatedAt: now)
        let selecta = Presentation(id: "pres-selecta", ingredientId: harina.id, brand: "Selecta",
                                   packageQuantity: "1000", createdAt: now, updatedAt: now)
        let precioSelecta = PriceRecord(id: "pr-1", presentationId: selecta.id, priceCents: 2350,
                                        recordedAt: now, createdAt: now, updatedAt: now)

        let receta = Recipe(
            id: "rec-galletas",
            name: "Galletas",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "300")],
            yieldQuantity: "12",
            yieldUnit: .pz,
            servings: 12,
            marginPercent: 40,
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(
            deviceId: "dev-test",
            ingredients: [harina],
            presentations: [selecta],
            priceRecords: [precioSelecta],
            recipes: [receta]
        )

        let index = CostingIndex(data: data)
        let cost = try index.calculateRecipeCost(recipe: receta, now: now)

        #expect(cost.lines.count == 1)
        let line = cost.lines[0]
        #expect(line.kind == .ingredient)
        #expect(line.refId == harina.id)
        #expect(line.refName == "Harina de trigo")
        #expect(line.quantity == "300")
        #expect(line.quantityInBase == "300")
        #expect(line.baseUnit == .g)
        #expect(line.presentationId == selecta.id)
        #expect(line.presentationLabel == "Selecta · 1000 g")
        #expect(line.pinned == false)
        #expect(line.brandSource == .current)
        #expect(line.costCents == 705)
        #expect(line.missingPrice == false)
        #expect(line.priceIsStale == false)

        #expect(cost.ingredientsCostCents == 705)
        #expect(cost.extrasCostCents == 0)
        #expect(cost.batchCostCents == 705)
        #expect(cost.complete == true)
        #expect(cost.hasStalePrices == false)
        // 705 / 12 = 58.75 -> 58.750000
        #expect(cost.costPerYieldUnit == "58.750000")
        // 705 / 12 = 58.75 -> roundToCents -> 59
        #expect(cost.costPerServingCents == 59)
        // suggested price: 705 * 1.4 = 987.0 -> 987
        #expect(cost.suggestedPriceCents == 987)
        // per yield: 58.75 * 1.4 = 82.25 -> 82
        #expect(cost.suggestedPricePerYieldUnitCents == 82)
    }

    // MARK: - 2. Tres líneas de 0.4 -> 1

    @Test("Redondeo: tres líneas de 0.4 centavos suman 1.2 -> ingredientsCostCents es 1")
    func threeLinesOfPointFourCents() throws {
        let ing1 = Ingredient(id: "ing-1", name: "Ingrediente 1", baseUnit: .g, createdAt: now, updatedAt: now)
        let ing2 = Ingredient(id: "ing-2", name: "Ingrediente 2", baseUnit: .g, createdAt: now, updatedAt: now)
        let ing3 = Ingredient(id: "ing-3", name: "Ingrediente 3", baseUnit: .g, createdAt: now, updatedAt: now)

        // 1000 g a 400 centavos ($4.00) -> 1 g = 0.4 centavos
        let pres1 = Presentation(id: "p1", ingredientId: ing1.id, brand: "B1", packageQuantity: "1000", createdAt: now, updatedAt: now)
        let pres2 = Presentation(id: "p2", ingredientId: ing2.id, brand: "B2", packageQuantity: "1000", createdAt: now, updatedAt: now)
        let pres3 = Presentation(id: "p3", ingredientId: ing3.id, brand: "B3", packageQuantity: "1000", createdAt: now, updatedAt: now)

        let pr1 = PriceRecord(id: "pr1", presentationId: pres1.id, priceCents: 400, recordedAt: now, createdAt: now, updatedAt: now)
        let pr2 = PriceRecord(id: "pr2", presentationId: pres2.id, priceCents: 400, recordedAt: now, createdAt: now, updatedAt: now)
        let pr3 = PriceRecord(id: "pr3", presentationId: pres3.id, priceCents: 400, recordedAt: now, createdAt: now, updatedAt: now)

        let receta = Recipe(
            id: "rec-pizcas",
            name: "Pizcas",
            items: [
                RecipeItem(kind: .ingredient, refId: ing1.id, quantity: "1"),
                RecipeItem(kind: .ingredient, refId: ing2.id, quantity: "1"),
                RecipeItem(kind: .ingredient, refId: ing3.id, quantity: "1"),
            ],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(
            deviceId: "dev-test",
            ingredients: [ing1, ing2, ing3],
            presentations: [pres1, pres2, pres3],
            priceRecords: [pr1, pr2, pr3],
            recipes: [receta]
        )

        let cost = try CostingIndex(data: data).calculateRecipeCost(recipe: receta, now: now)

        #expect(cost.lines.count == 3)
        #expect(cost.lines[0].costCents == 0)
        #expect(cost.lines[1].costCents == 0)
        #expect(cost.lines[2].costCents == 0)
        #expect(cost.ingredientsCostCents == 1)
        #expect(cost.batchCostCents == 1)
    }

    // MARK: - 3. Taza de harina con equivalencia

    @Test("Taza de harina con equivalencia propia (taza = 125 g): 2 tazas -> 250 g")
    func cupOfFlourWithConversion() throws {
        let harina = Ingredient(
            id: "ing-harina",
            name: "Harina de trigo",
            baseUnit: .g,
            conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "125")],
            createdAt: now,
            updatedAt: now
        )
        let selecta = Presentation(id: "pres-selecta", ingredientId: harina.id, brand: "Selecta",
                                   packageQuantity: "1000", createdAt: now, updatedAt: now)
        let pr = PriceRecord(id: "pr-1", presentationId: selecta.id, priceCents: 2350,
                             recordedAt: now, createdAt: now, updatedAt: now)

        let receta = Recipe(
            id: "rec-pastel",
            name: "Pastel",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "2", unitId: "sys.tz")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(
            deviceId: "dev-test",
            ingredients: [harina],
            presentations: [selecta],
            priceRecords: [pr],
            recipes: [receta]
        )

        let cost = try CostingIndex(data: data).calculateRecipeCost(recipe: receta, now: now)
        let line = cost.lines[0]
        #expect(line.quantity == "2")
        #expect(line.unitName == "taza")
        #expect(line.quantityInBase == "250")
        #expect(line.baseUnit == .g)
        // 250 * 2350 / 1000 = 587.5 -> 588
        #expect(line.costCents == 588)
        #expect(cost.batchCostCents == 588)
    }

    // MARK: - 4. Taza de harina sin equivalencia -> error con texto exacto

    @Test("Taza de harina sin equivalencia -> DomainError.unitNotConvertible con texto exacto")
    func cupOfFlourWithoutConversionThrows() {
        let harina = Ingredient(
            id: "ing-harina",
            name: "Harina de trigo",
            baseUnit: .g,
            conversions: [],
            createdAt: now,
            updatedAt: now
        )
        let receta = Recipe(
            id: "rec-pastel",
            name: "Pastel",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "2", unitId: "sys.tz")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(
            deviceId: "dev-test",
            ingredients: [harina],
            recipes: [receta]
        )

        let index = CostingIndex(data: data)
        #expect(throws: DomainError.unitNotConvertible(detail: "Define cuántos g tiene 1 taza de Harina de trigo")) {
            try index.calculateRecipeCost(recipe: receta, now: now)
        }
    }

    // MARK: - 5. Versión con otra marca

    @Test("Versión con otra marca y comparación de versiones")
    func versionWithAlternativeBrand() throws {
        let harina = Ingredient(id: "ing-harina", name: "Harina de trigo", baseUnit: .g, createdAt: now, updatedAt: now)
        let selecta = Presentation(id: "pres-selecta", ingredientId: harina.id, brand: "Selecta", packageQuantity: "1000",
                                   createdAt: now.addingTimeInterval(-100), updatedAt: now)
        let sanAntonio = Presentation(id: "pres-san-antonio", ingredientId: harina.id, brand: "San Antonio", packageQuantity: "1000",
                                      createdAt: now, updatedAt: now)

        let prSelecta = PriceRecord(id: "pr-sel", presentationId: selecta.id, priceCents: 2350,
                                    recordedAt: now, createdAt: now, updatedAt: now)
        let prSanAntonio = PriceRecord(id: "pr-sa", presentationId: sanAntonio.id, priceCents: 3000,
                                       recordedAt: now.addingTimeInterval(-10), createdAt: now, updatedAt: now)

        let receta = Recipe(
            id: "rec-1",
            name: "Pan",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "300")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )

        let version = CostVersion(
            id: "ver-1",
            recipeId: receta.id,
            name: "Con San Antonio",
            choices: [CostVersionChoice(ingredientId: harina.id, presentationId: sanAntonio.id)],
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(
            deviceId: "dev-test",
            ingredients: [harina],
            presentations: [selecta, sanAntonio],
            priceRecords: [prSelecta, prSanAntonio],
            recipes: [receta],
            costVersions: [version]
        )

        let index = CostingIndex(data: data)

        // 1. Costo base (usa Selecta que es la vigente porque su precio grabado es más reciente)
        let baseCost = try index.calculateRecipeCost(recipe: receta, now: now)
        #expect(baseCost.lines[0].presentationId == selecta.id)
        #expect(baseCost.lines[0].brandSource == .current)
        #expect(baseCost.lines[0].pinned == false)
        #expect(baseCost.batchCostCents == 705)
        #expect(baseCost.versionId == nil)
        #expect(baseCost.versionName == nil)

        // 2. Costo con la versión
        let vCost = try index.calculateRecipeCost(recipe: receta, version: version, now: now)
        #expect(vCost.lines[0].presentationId == sanAntonio.id)
        #expect(vCost.lines[0].brandSource == .version)
        #expect(vCost.lines[0].pinned == true)
        // 300 * 3000 / 1000 = 900
        #expect(vCost.batchCostCents == 900)
        #expect(vCost.versionId == version.id)
        #expect(vCost.versionName == "Con San Antonio")

        // 3. Comparación de versiones
        let compare = try index.compareVersions(recipe: receta, now: now)
        #expect(compare.count == 2)
        #expect(compare[0].name == "Base")
        #expect(compare[0].versionId == nil)
        #expect(compare[0].batchCostCents == 705)
        #expect(compare[1].name == "Con San Antonio")
        #expect(compare[1].versionId == version.id)
        #expect(compare[1].batchCostCents == 900)
    }

    // MARK: - 6. Marca fijada sin precio

    @Test("Marca fijada sin precio: mantiene pinned=true, missingPrice=true, costo 0 sin caer a vigente")
    func pinnedPresentationWithoutPrice() throws {
        let harina = Ingredient(id: "ing-harina", name: "Harina de trigo", baseUnit: .g, createdAt: now, updatedAt: now)
        let selecta = Presentation(id: "pres-selecta", ingredientId: harina.id, brand: "Selecta", packageQuantity: "1000",
                                   createdAt: now, updatedAt: now)
        let zulka = Presentation(id: "pres-zulka", ingredientId: harina.id, brand: "Zulka", packageQuantity: "1000",
                                 createdAt: now, updatedAt: now)

        // Selecta tiene precio, Zulka NO tiene precio
        let prSelecta = PriceRecord(id: "pr-1", presentationId: selecta.id, priceCents: 2350,
                                    recordedAt: now, createdAt: now, updatedAt: now)

        let receta = Recipe(
            id: "rec-1",
            name: "Pan",
            items: [
                RecipeItem(
                    kind: .ingredient,
                    refId: harina.id,
                    quantity: "300",
                    pinnedPresentationId: zulka.id
                )
            ],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(
            deviceId: "dev-test",
            ingredients: [harina],
            presentations: [selecta, zulka],
            priceRecords: [prSelecta],
            recipes: [receta]
        )

        let cost = try CostingIndex(data: data).calculateRecipeCost(recipe: receta, now: now)
        #expect(cost.lines.count == 1)
        let line = cost.lines[0]
        #expect(line.presentationId == zulka.id)
        #expect(line.pinned == true)
        #expect(line.brandSource == .recipe)
        #expect(line.missingPrice == true)
        #expect(line.costCents == 0)
        #expect(cost.complete == false)
        #expect(cost.batchCostCents == 0)
    }

    // MARK: - 7. Subreceta

    @Test("Subreceta: recursión, conversión de unidad de rendimiento y propagación de incompletitud")
    func subrecipeCosting() throws {
        let tomate = Ingredient(id: "ing-tomate", name: "Tomate", baseUnit: .g, createdAt: now, updatedAt: now)
        let presTomate = Presentation(id: "pres-tomate", ingredientId: tomate.id, brand: "Local", packageQuantity: "1000",
                                      createdAt: now, updatedAt: now)
        let prTomate = PriceRecord(id: "pr-tomate", presentationId: presTomate.id, priceCents: 2000,
                                   recordedAt: now, createdAt: now, updatedAt: now)

        // Subreceta Salsa: rinde 500 g, usa 500 g de tomate (costo = 1000 centavos)
        let subreceta = Recipe(
            id: "rec-salsa",
            name: "Salsa",
            items: [RecipeItem(kind: .ingredient, refId: tomate.id, quantity: "500")],
            yieldQuantity: "500",
            yieldUnit: .g,
            createdAt: now,
            updatedAt: now
        )

        // Receta Lasaña: usa 0.25 kg de salsa (debe convertir kg a g -> 250 g)
        let receta = Recipe(
            id: "rec-lasana",
            name: "Lasaña",
            items: [RecipeItem(kind: .recipe, refId: subreceta.id, quantity: "0.25", unitId: "sys.kg")],
            extraCosts: [ExtraCost(name: "Caja", costCents: 150)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            servings: 2,
            marginPercent: 50,
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(
            deviceId: "dev-test",
            ingredients: [tomate],
            presentations: [presTomate],
            priceRecords: [prTomate],
            recipes: [subreceta, receta]
        )

        let index = CostingIndex(data: data)
        let cost = try index.calculateRecipeCost(recipe: receta, now: now)

        #expect(cost.lines.count == 1)
        let line = cost.lines[0]
        #expect(line.kind == .recipe)
        #expect(line.refId == subreceta.id)
        #expect(line.refName == "Salsa")
        #expect(line.quantity == "0.25")
        #expect(line.unitName == "kilogramo")
        #expect(line.quantityInBase == "250")
        #expect(line.baseUnit == .g)
        // Salsa rinde 500 g con costo 1000 centavos -> 250 g cuesta 500 centavos
        #expect(line.costCents == 500)
        #expect(line.missingPrice == false)

        #expect(cost.ingredientsCostCents == 500)
        #expect(cost.extrasCostCents == 150)
        #expect(cost.batchCostCents == 650)
        #expect(cost.complete == true)
        // servings: 2 -> 650 / 2 = 325
        #expect(cost.costPerServingCents == 325)
        // suggested: 650 * 1.5 = 975
        #expect(cost.suggestedPriceCents == 975)
    }

    // MARK: - 8. Defensa de recursión cíclica (> 10 niveles)

    @Test("Defensa contra ciclos de subrecetas: corta a más de 10 niveles y marca missingPrice sin crash")
    func recursiveCycleDefense() throws {
        // Receta A llama a B, B llama a A
        let recA = Recipe(
            id: "rec-a",
            name: "Receta A",
            items: [RecipeItem(kind: .recipe, refId: "rec-b", quantity: "1")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )
        let recB = Recipe(
            id: "rec-b",
            name: "Receta B",
            items: [RecipeItem(kind: .recipe, refId: "rec-a", quantity: "1")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )

        let data = KitchenData(deviceId: "dev-test", recipes: [recA, recB])
        let cost = try CostingIndex(data: data).calculateRecipeCost(recipe: recA, now: now)

        #expect(cost.complete == false)
        #expect(cost.lines[0].missingPrice == true)
        #expect(cost.batchCostCents == 0)
    }

    // MARK: - 9. Precios viejos (staleness)

    @Test("Detección de precio viejo: más de priceStaleDays marca priceIsStale y hasStalePrices")
    func stalePriceDetection() throws {
        let harina = Ingredient(id: "ing-harina", name: "Harina", baseUnit: .g, createdAt: now, updatedAt: now)
        let selecta = Presentation(id: "pres-selecta", ingredientId: harina.id, brand: "Selecta", packageQuantity: "1000",
                                   createdAt: now, updatedAt: now)

        // Precio grabado hace 100 días
        let oldDate = Calendar.current.date(byAdding: .day, value: -100, to: now)!
        let pr = PriceRecord(id: "pr-old", presentationId: selecta.id, priceCents: 2000,
                             recordedAt: oldDate, createdAt: oldDate, updatedAt: oldDate)

        let receta = Recipe(
            id: "rec-1",
            name: "Galletas",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "100")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: now,
            updatedAt: now
        )

        var settings = KitchenSettings()
        settings.priceStaleDays = 90
        let data = KitchenData(
            deviceId: "dev-test",
            settings: settings,
            ingredients: [harina],
            presentations: [selecta],
            priceRecords: [pr],
            recipes: [receta]
        )

        let cost = try CostingIndex(data: data).calculateRecipeCost(recipe: receta, now: now)
        #expect(cost.lines[0].priceIsStale == true)
        #expect(cost.hasStalePrices == true)
    }
}
