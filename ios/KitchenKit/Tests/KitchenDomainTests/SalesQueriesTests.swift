import Foundation
import Testing
@testable import KitchenDomain

private final class TestIdGenerator: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()
    private let prefix: String

    init(prefix: String = "id") {
        self.prefix = prefix
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return "\(prefix)-\(count)"
    }
}

@Suite("Precio Propio de Recetas, Ganancia y Tandas por Pedido (Bloque K5)")
struct SalesQueriesTests {
    private let testNow = KitchenCoding.parseDate("2026-11-06T12:00:00.000Z")!

    private func makeContext(prefix: String = "id") -> MutationContext {
        let gen = TestIdGenerator(prefix: prefix)
        return MutationContext(now: testNow, newId: { gen.next() })
    }

    /// Prepara un negocio con un ingrediente (Harina 1000g a $100 -> $0.10/g).
    private func makeBaseData() -> KitchenData {
        KitchenData(
            exportedAt: testNow,
            deviceId: "test-device",
            ingredients: [
                Ingredient(id: "ing-1", name: "Harina", baseUnit: .g, createdAt: testNow, updatedAt: testNow),
            ],
            presentations: [
                Presentation(id: "pres-1", ingredientId: "ing-1", brand: "Selecta", packageQuantity: "1000",
                             createdAt: testNow, updatedAt: testNow),
            ],
            priceRecords: [
                PriceRecord(id: "pr-1", presentationId: "pres-1", priceCents: 10000, recordedAt: testNow,
                            createdAt: testNow, updatedAt: testNow),
            ]
        )
    }

    // MARK: - 1. Leer respaldo / JSON sin los campos nuevos

    @Test("Leer respaldo o JSON sin los campos nuevos decodifica nulos sin error")
    func legacyJsonDecodeWithoutNewFields() throws {
        let jsonWithoutNewFields = """
        {
          "schema_version": 1,
          "exported_at": "2026-11-06T12:00:00.000Z",
          "device_id": "legacy-dev",
          "recipes": [
            {
              "id": "rec-1",
              "name": "Pastel Tradicional",
              "items": [],
              "extra_costs": [],
              "yield_quantity": "1",
              "yield_unit": "pz",
              "created_at": "2026-11-06T12:00:00.000Z",
              "updated_at": "2026-11-06T12:00:00.000Z"
            }
          ]
        }
        """

        let data = try KitchenCoding.decode(Data(jsonWithoutNewFields.utf8))
        #expect(data.recipes.count == 1)
        let recipe = data.recipes[0]
        #expect(recipe.id == "rec-1")
        #expect(recipe.salePriceCents == nil)
        #expect(recipe.salePriceSoldBy == nil)
    }

    // MARK: - 2. Poner, cambiar y quitar precio propio (y validaciones de error)

    @Test("Poner, cambiar y quitar precio propio con updateRecipe y validación de errores")
    func recipeSalePriceCRUDAndValidations() throws {
        let ctx = makeContext(prefix: "rec")
        var data = makeBaseData()

        let created = try data.createRecipe(
            name: "Galletas de Mantequilla",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "200")],
            yieldQuantity: "12",
            yieldUnit: .pz,
            ctx: ctx
        )
        #expect(created.salePriceCents == nil)
        #expect(created.salePriceSoldBy == nil)

        // 1. Poner precio propio sin forma de venta -> queda .batch
        let withPrice = try data.updateRecipe(
            id: created.id,
            salePriceCents: 24000,
            ctx: ctx
        )
        #expect(withPrice.salePriceCents == 24000)
        #expect(withPrice.salePriceSoldBy == .batch)

        // 2. Cambiar forma de venta a .unit
        let withUnitSoldBy = try data.updateRecipe(
            id: created.id,
            salePriceSoldBy: .unit,
            ctx: ctx
        )
        #expect(withUnitSoldBy.salePriceCents == 24000)
        #expect(withUnitSoldBy.salePriceSoldBy == .unit)

        // 3. Cambiar precio manteniendo forma de venta
        let updatedPrice = try data.updateRecipe(
            id: created.id,
            salePriceCents: 25000,
            ctx: ctx
        )
        #expect(updatedPrice.salePriceCents == 25000)
        #expect(updatedPrice.salePriceSoldBy == .unit)

        // 4. Quitar precio propio con .some(nil) -> precio y soldBy quedan nulos
        let removedPrice = try data.updateRecipe(
            id: created.id,
            salePriceCents: .some(nil),
            ctx: ctx
        )
        #expect(removedPrice.salePriceCents == nil)
        #expect(removedPrice.salePriceSoldBy == nil)

        // 5. Errores de validación y atomicidad
        // Precio <= 0
        #expect(throws: DomainError.invalidValue(detail: "El precio debe ser mayor a $0")) {
            try data.updateRecipe(id: created.id, salePriceCents: 0, ctx: ctx)
        }
        #expect(throws: DomainError.invalidValue(detail: "El precio debe ser mayor a $0")) {
            try data.updateRecipe(id: created.id, salePriceCents: -500, ctx: ctx)
        }
        // Precio > 100_000_000 centavos
        #expect(throws: DomainError.invalidValue(detail: "El precio debe ser mayor a $0")) {
            try data.updateRecipe(id: created.id, salePriceCents: 100_000_001, ctx: ctx)
        }

        // Estado sigue intacto tras los errores
        let current = try #require(data.recipes.active(created.id))
        #expect(current.salePriceCents == nil)
        #expect(current.salePriceSoldBy == nil)
    }

    // MARK: - 3. Profit con ganancia, pérdida y costo 0

    @Test("Profit con ganancia, pérdida y costo 0, y profitPercent en OrderTotals")
    func profitCalculation() {
        // Ganancia
        let profit = Profit.make(priceCents: 15000, costCents: 10000)
        #expect(profit.priceCents == 15000)
        #expect(profit.costCents == 10000)
        #expect(profit.profitCents == 5000)
        #expect(profit.percent == 50)

        // Pérdida
        let loss = Profit.make(priceCents: 8000, costCents: 10000)
        #expect(loss.priceCents == 8000)
        #expect(loss.costCents == 10000)
        #expect(loss.profitCents == -2000)
        #expect(loss.percent == -20)

        // Costo 0
        let zeroCost = Profit.make(priceCents: 5000, costCents: 0)
        #expect(zeroCost.priceCents == 5000)
        #expect(zeroCost.costCents == 0)
        #expect(zeroCost.profitCents == 5000)
        #expect(zeroCost.percent == nil)

        // OrderTotals.profitPercent
        let totalsProfit = OrderTotals(totalCents: 15000, paidCents: 5000, balanceCents: 10000, costCents: 10000, profitCents: 5000)
        #expect(totalsProfit.profitPercent == 50)

        let totalsLoss = OrderTotals(totalCents: 8000, paidCents: 8000, balanceCents: 0, costCents: 10000, profitCents: -2000)
        #expect(totalsLoss.profitPercent == -20)

        let totalsZeroCost = OrderTotals(totalCents: 5000, paidCents: 0, balanceCents: 5000, costCents: 0, profitCents: 5000)
        #expect(totalsZeroCost.profitPercent == nil)
    }

    // MARK: - 4. Sugerido con margen 40 % da 40 %

    @Test("Precio sugerido con margen de 40 % produce 40 % de ganancia exacta")
    func suggestedProfitWithFortyPercentMargin() throws {
        let ctx = makeContext()
        var data = makeBaseData()

        // Costo: 1000 g de harina a $100 = 10000 centavos.
        // Receta usa 1000 g -> costo tanda = 10000 centavos.
        // Margen 40% -> sugerido = 14000 centavos.
        let recipe = try data.createRecipe(
            name: "Pan Rústico",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "1000")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 40,
            ctx: ctx
        )

        let cost = try data.costingIndex().calculateRecipeCost(recipe: recipe, version: nil, now: testNow)
        #expect(cost.batchCostCents == 10000)
        #expect(cost.suggestedPriceCents == 14000)

        let suggested = suggestedProfit(cost: cost)
        #expect(suggested.priceCents == 14000)
        #expect(suggested.costCents == 10000)
        #expect(suggested.profitCents == 4000)
        #expect(suggested.percent == 40)
    }

    // MARK: - 5. RecipeSalePrice por tanda y por unidad (rendimiento 12 y 1)

    @Test("RecipeSalePrice por tanda y por unidad con rendimiento 12 y rendimiento 1")
    func recipeSalePriceBreakdown() throws {
        let ctx = makeContext()
        var data = makeBaseData()

        // 1. Rendimiento 12: 1200 g de harina = 12000 centavos costo tanda -> 1000 centavos/pz.
        var rec12 = try data.createRecipe(
            name: "Docena de Cupcakes",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "1200")],
            yieldQuantity: "12",
            yieldUnit: .pz,
            ctx: ctx
        )
        let cost12 = try data.costingIndex().calculateRecipeCost(recipe: rec12, version: nil, now: testNow)
        #expect(cost12.batchCostCents == 12000)

        // 1a. Precio propio por tanda: $240 (24000 centavos)
        rec12.salePriceCents = 24000
        rec12.salePriceSoldBy = .batch
        let saleBatch12 = try #require(salePrice(of: rec12, cost: cost12))
        #expect(saleBatch12.soldBy == .batch)
        // Batch
        #expect(saleBatch12.batch.priceCents == 24000)
        #expect(saleBatch12.batch.costCents == 12000)
        #expect(saleBatch12.batch.profitCents == 12000)
        #expect(saleBatch12.batch.percent == 100)
        // Unit: 24000 / 12 = 2000 centavos
        #expect(saleBatch12.perUnit.priceCents == 2000)
        #expect(saleBatch12.perUnit.costCents == 1000)
        #expect(saleBatch12.perUnit.profitCents == 1000)
        #expect(saleBatch12.perUnit.percent == 100)

        // 1b. Precio propio por unidad: $25 (2500 centavos)
        rec12.salePriceCents = 2500
        rec12.salePriceSoldBy = .unit
        let saleUnit12 = try #require(salePrice(of: rec12, cost: cost12))
        #expect(saleUnit12.soldBy == .unit)
        // Unit
        #expect(saleUnit12.perUnit.priceCents == 2500)
        #expect(saleUnit12.perUnit.costCents == 1000)
        #expect(saleUnit12.perUnit.profitCents == 1500)
        #expect(saleUnit12.perUnit.percent == 150)
        // Batch: 2500 * 12 = 30000 centavos
        #expect(saleUnit12.batch.priceCents == 30000)
        #expect(saleUnit12.batch.costCents == 12000)
        #expect(saleUnit12.batch.profitCents == 18000)
        #expect(saleUnit12.batch.percent == 150)

        // 2. Rendimiento 1: 500 g de harina = 5000 centavos costo tanda -> 5000 centavos/pz.
        var rec1 = try data.createRecipe(
            name: "Pastel Individual",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "500")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )
        let cost1 = try data.costingIndex().calculateRecipeCost(recipe: rec1, version: nil, now: testNow)

        rec1.salePriceCents = 8000
        rec1.salePriceSoldBy = .batch
        let saleBatch1 = try #require(salePrice(of: rec1, cost: cost1))
        #expect(saleBatch1.batch.priceCents == 8000)
        #expect(saleBatch1.perUnit.priceCents == 8000)
        #expect(saleBatch1.batch.profitCents == 3000)
        #expect(saleBatch1.perUnit.profitCents == 3000)
        #expect(saleBatch1.batch.percent == 60)
        #expect(saleBatch1.perUnit.percent == 60)

        rec1.salePriceCents = 9000
        rec1.salePriceSoldBy = .unit
        let saleUnit1 = try #require(salePrice(of: rec1, cost: cost1))
        #expect(saleUnit1.batch.priceCents == 9000)
        #expect(saleUnit1.perUnit.priceCents == 9000)
    }

    // MARK: - 6. Precio por defecto de una línea con y sin precio propio

    @Test("Precio por defecto de una línea con y sin precio propio, por tanda y por unidad")
    func defaultLinePriceTests() throws {
        let ctx = makeContext()
        var data = makeBaseData()

        // Receta sin precio propio (costo batch = 12000, margen 30% -> sugerido tanda 15600, sugerido unidad 1300)
        let recWithout = try data.createRecipe(
            name: "Muffins",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "1200")],
            yieldQuantity: "12",
            yieldUnit: .pz,
            marginPercent: 30,
            ctx: ctx
        )
        let costWithout = try data.costingIndex().calculateRecipeCost(recipe: recWithout, version: nil, now: testNow)

        #expect(data.defaultLinePriceCents(recipeId: recWithout.id, soldBy: .batch, cost: costWithout) == 15600)
        #expect(data.defaultLinePriceCents(recipeId: recWithout.id, soldBy: .unit, cost: costWithout) == 1300)

        // Receta con precio propio por tanda: $240 (24000 centavos) -> por unidad $20 (2000 centavos)
        let recWithBatch = try data.createRecipe(
            name: "Donas",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "1200")],
            yieldQuantity: "12",
            yieldUnit: .pz,
            ctx: ctx
        )
        try data.updateRecipe(id: recWithBatch.id, salePriceCents: 24000, salePriceSoldBy: .batch, ctx: ctx)
        let costBatch = try data.costingIndex().calculateRecipeCost(recipe: data.recipes.active(recWithBatch.id)!, version: nil, now: testNow)

        #expect(data.defaultLinePriceCents(recipeId: recWithBatch.id, soldBy: .batch, cost: costBatch) == 24000)
        #expect(data.defaultLinePriceCents(recipeId: recWithBatch.id, soldBy: .unit, cost: costBatch) == 2000)

        // Receta con precio propio por unidad: $25 (2500 centavos) -> por tanda $300 (30000 centavos)
        let recWithUnit = try data.createRecipe(
            name: "Galletas Gourmet",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "1200")],
            yieldQuantity: "12",
            yieldUnit: .pz,
            ctx: ctx
        )
        try data.updateRecipe(id: recWithUnit.id, salePriceCents: 2500, salePriceSoldBy: .unit, ctx: ctx)
        let costUnit = try data.costingIndex().calculateRecipeCost(recipe: data.recipes.active(recWithUnit.id)!, version: nil, now: testNow)

        #expect(data.defaultLinePriceCents(recipeId: recWithUnit.id, soldBy: .unit, cost: costUnit) == 2500)
        #expect(data.defaultLinePriceCents(recipeId: recWithUnit.id, soldBy: .batch, cost: costUnit) == 30000)

        // Verificación con createOrder: líneas sin unitPriceCents toman el defaultLinePriceCents
        let order = try data.createOrder(
            customerName: "Cliente 1",
            deliveryAt: testNow,
            items: [
                OrderItemDraft(recipeId: recWithBatch.id, soldBy: .batch, quantity: "2"), // debería tomar 24000
                OrderItemDraft(recipeId: recWithBatch.id, soldBy: .unit, quantity: "5"),  // debería tomar 2000
                OrderItemDraft(recipeId: recWithout.id, soldBy: .batch, quantity: "1"),   // debería tomar sugerido 15600
                OrderItemDraft(recipeId: recWithout.id, soldBy: .unit, quantity: "3"),    // debería tomar sugerido 1300
            ],
            ctx: ctx
        )
        #expect(order.items[0].unitPriceCents == 24000)
        #expect(order.items[1].unitPriceCents == 2000)
        #expect(order.items[2].unitPriceCents == 15600)
        #expect(order.items[3].unitPriceCents == 1300)

        // Verificación con updateOrder agregando nueva línea sin precio
        let updatedOrder = try data.updateOrder(
            id: order.id,
            draft: OrderUpdateDraft(
                items: [
                    OrderItemDraft(recipeId: recWithUnit.id, soldBy: .unit, quantity: "4") // debería tomar 2500
                ]
            ),
            ctx: ctx
        )
        #expect(updatedOrder.items.count == 1)
        #expect(updatedOrder.items[0].unitPriceCents == 2500)
    }

    // MARK: - 7. Tandas de un pedido (batchNeeds)

    @Test("batchNeeds con 18 tandas exactas, 15 piezas de rinde 10, suma de líneas, receta borrada y múltiples pedidos")
    func batchNeedsScenarios() throws {
        let ctx = makeContext()
        var data = makeBaseData()

        // Receta A: rinde 1 pz, costo $10 (1000 centavos), precio propio $15 (1500 centavos)
        let recA = try data.createRecipe(
            name: "Pastel Cumpleaños",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "100")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )
        try data.updateRecipe(id: recA.id, salePriceCents: 1500, salePriceSoldBy: .batch, ctx: ctx)

        // Receta B: rinde 10 pz, costo $100 (10000 centavos = $10/pz), precio sugerido 30% ($13/pz = 1300 centavos)
        let recB = try data.createRecipe(
            name: "Panqueques",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "1000")],
            yieldQuantity: "10",
            yieldUnit: .pz,
            marginPercent: 30,
            ctx: ctx
        )

        // Receta C: se borrará para probar que se salta
        let recC = try data.createRecipe(
            name: "Receta Descontinuada",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "50")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // Escenario 1: 18 tandas de Receta A (18 exactas, nada sobra)
        let order1 = try data.createOrder(
            customerName: "Cliente 1",
            deliveryAt: testNow,
            items: [
                OrderItemDraft(recipeId: recA.id, soldBy: .batch, quantity: "18")
            ],
            ctx: ctx
        )
        let needs1 = data.batchNeeds(for: order1)
        #expect(needs1.count == 1)
        let n1 = needs1[0]
        #expect(n1.recipeId == recA.id)
        #expect(n1.recipeName == "Pastel Cumpleaños")
        #expect(n1.yieldQuantity == "1")
        #expect(n1.yieldUnit == .pz)
        #expect(n1.neededUnits == "18")
        #expect(n1.exactBatches == "18")
        #expect(n1.wholeBatches == 18)
        #expect(n1.leftoverUnits == "0")
        #expect(n1.leftoverValueCents == nil)

        // Escenario 2: 15 piezas de Receta B que rinde 10 (1.5 exactas, 2 enteras, sobran 5 con su valor)
        // Precio por unidad de B: sugerido 1300 centavos.
        // Sobrante: 5 pz * 1300 centavos = 6500 centavos.
        let order2 = try data.createOrder(
            customerName: "Cliente 2",
            deliveryAt: testNow,
            items: [
                OrderItemDraft(recipeId: recB.id, soldBy: .unit, quantity: "15")
            ],
            ctx: ctx
        )
        let needs2 = data.batchNeeds(for: order2)
        #expect(needs2.count == 1)
        let n2 = needs2[0]
        #expect(n2.recipeId == recB.id)
        #expect(n2.neededUnits == "15")
        #expect(n2.exactBatches == "1.5")
        #expect(n2.wholeBatches == 2)
        #expect(n2.leftoverUnits == "5")
        #expect(n2.leftoverValueCents == 6500)

        // Escenario 3: Dos líneas de la misma receta (una por tanda y otra por pieza) que se suman
        // 1 tanda de B (10 pz) + 5 piezas de B (5 pz) = 15 piezas en total
        let order3 = try data.createOrder(
            customerName: "Cliente 3",
            deliveryAt: testNow,
            items: [
                OrderItemDraft(recipeId: recB.id, soldBy: .batch, quantity: "1"),
                OrderItemDraft(recipeId: recB.id, soldBy: .unit, quantity: "5"),
            ],
            ctx: ctx
        )
        let needs3 = data.batchNeeds(for: order3)
        #expect(needs3.count == 1)
        #expect(needs3[0].recipeId == recB.id)
        #expect(needs3[0].neededUnits == "15")
        #expect(needs3[0].exactBatches == "1.5")
        #expect(needs3[0].wholeBatches == 2)
        #expect(needs3[0].leftoverUnits == "5")
        #expect(needs3[0].leftoverValueCents == 6500)

        // Escenario 4: Receta borrada que se salta
        // Creamos un pedido con recC y luego borramos recC
        let orderWithDeleted = try data.createOrder(
            customerName: "Cliente 4",
            deliveryAt: testNow,
            items: [
                OrderItemDraft(recipeId: recA.id, soldBy: .batch, quantity: "1"),
                OrderItemDraft(recipeId: recC.id, soldBy: .batch, quantity: "3"),
            ],
            ctx: ctx
        )
        try data.deleteRecipe(id: recC.id, ctx: ctx)
        let needsDeleted = data.batchNeeds(for: orderWithDeleted)
        // Solo debe estar recA, recC se salta porque ya no está activa
        #expect(needsDeleted.count == 1)
        #expect(needsDeleted[0].recipeId == recA.id)

        // Escenario 5: Varios pedidos sumados (batchNeeds(for: [Order]))
        // order1: 18 tandas de A (18 pz)
        // orderWithDeleted (tras borrar C): 1 tanda de A (1 pz)
        // order2: 15 piezas de B (15 pz)
        let multiNeeds = data.batchNeeds(for: [order1, orderWithDeleted, order2])
        #expect(multiNeeds.count == 2)
        // Orden: A primero (aparece en order1), luego B (aparece en order2)
        #expect(multiNeeds[0].recipeId == recA.id)
        #expect(multiNeeds[0].neededUnits == "19") // 18 + 1
        #expect(multiNeeds[0].exactBatches == "19")
        #expect(multiNeeds[0].wholeBatches == 19)
        #expect(multiNeeds[0].leftoverUnits == "0")
        #expect(multiNeeds[0].leftoverValueCents == nil)

        #expect(multiNeeds[1].recipeId == recB.id)
        #expect(multiNeeds[1].neededUnits == "15")
        #expect(multiNeeds[1].exactBatches == "1.5")
        #expect(multiNeeds[1].wholeBatches == 2)
        #expect(multiNeeds[1].leftoverUnits == "5")
        #expect(multiNeeds[1].leftoverValueCents == 6500)
    }

    // MARK: - 8. Ida y vuelta por KitchenCoding

    @Test("Ida y vuelta por KitchenCoding conserva campos nuevos de precio propio")
    func roundTripCodingWithSalePriceFields() throws {
        var data = makeBaseData()
        let rec1 = Recipe(
            id: "rec-1",
            name: "Pastel Chocolate",
            items: [],
            extraCosts: [],
            yieldQuantity: "1",
            yieldUnit: .pz,
            salePriceCents: 35000,
            salePriceSoldBy: .batch,
            createdAt: testNow,
            updatedAt: testNow
        )
        let rec2 = Recipe(
            id: "rec-2",
            name: "Galletas Avena",
            items: [],
            extraCosts: [],
            yieldQuantity: "24",
            yieldUnit: .pz,
            salePriceCents: 1500,
            salePriceSoldBy: .unit,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes = [rec1, rec2]

        let encoded = try KitchenCoding.encode(data)
        let jsonString = try #require(String(data: encoded, encoding: .utf8))
        #expect(jsonString.contains("\"sale_price_cents\":35000"))
        #expect(jsonString.contains("\"sale_price_sold_by\":\"batch\""))
        #expect(jsonString.contains("\"sale_price_cents\":1500"))
        #expect(jsonString.contains("\"sale_price_sold_by\":\"unit\""))

        let decoded = try KitchenCoding.decode(encoded)
        #expect(decoded == data)
        #expect(decoded.recipes[0].salePriceCents == 35000)
        #expect(decoded.recipes[0].salePriceSoldBy == .batch)
        #expect(decoded.recipes[1].salePriceCents == 1500)
        #expect(decoded.recipes[1].salePriceSoldBy == .unit)
    }
}
