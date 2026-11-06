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

@Suite("Ajustes del negocio y Tablero de costos de recetas (K3)")
struct SettingsAndDashboardTests {
    private let testNow = KitchenCoding.parseDate("2026-11-06T12:00:00.000Z")!

    private func makeContext(prefix: String = "id") -> MutationContext {
        let gen = TestIdGenerator(prefix: prefix)
        return MutationContext(now: testNow, newId: { gen.next() })
    }

    // MARK: - 1. Ajustes del negocio

    @Test("Rangos de ajustes válidos y cambios parciales")
    func validSettingsUpdates() throws {
        let ctx = makeContext(prefix: "set")
        var data = KitchenData(deviceId: "test-dev")

        #expect(data.settings.name == "Mi cocina")
        #expect(data.settings.currency == "MXN")
        #expect(data.settings.defaultMarginPercent == 40)
        #expect(data.settings.priceStaleDays == 90)

        // Cambio parcial: solo nombre (con trim)
        let s1 = try data.updateSettings(name: "  Pastelería Dulce Elena  ", ctx: ctx)
        #expect(s1.name == "Pastelería Dulce Elena")
        #expect(data.settings.name == "Pastelería Dulce Elena")
        #expect(data.settings.currency == "MXN")
        #expect(data.settings.defaultMarginPercent == 40)
        #expect(data.settings.priceStaleDays == 90)

        // Límites válidos: margen 0 y 1000, días 1 y 3650
        try data.updateSettings(defaultMarginPercent: 0, ctx: ctx)
        #expect(data.settings.defaultMarginPercent == 0)

        try data.updateSettings(defaultMarginPercent: 1000, ctx: ctx)
        #expect(data.settings.defaultMarginPercent == 1000)

        try data.updateSettings(priceStaleDays: 1, ctx: ctx)
        #expect(data.settings.priceStaleDays == 1)

        try data.updateSettings(priceStaleDays: 3650, ctx: ctx)
        #expect(data.settings.priceStaleDays == 3650)

        // Moneda válida de 3 letras mayúsculas con trim
        try data.updateSettings(currency: "  USD  ", ctx: ctx)
        #expect(data.settings.currency == "USD")

        // Nombre de 1 carácter y de 80 caracteres
        try data.updateSettings(name: "X", ctx: ctx)
        #expect(data.settings.name == "X")

        let eightyChars = String(repeating: "A", count: 80)
        try data.updateSettings(name: eightyChars, ctx: ctx)
        #expect(data.settings.name == eightyChars)
    }

    @Test("Rangos de ajustes inválidos y atomicidad: un error no cambia nada")
    func invalidSettingsRangesAndAtomicity() throws {
        let ctx = makeContext(prefix: "set")
        var data = KitchenData(deviceId: "test-dev")
        let snapshot = data.settings

        // 1. Nombre vacío o de puros espacios
        #expect(throws: DomainError.invalidValue(detail: "El nombre del negocio no puede estar vacío")) {
            try data.updateSettings(name: "", ctx: ctx)
        }
        #expect(data.settings == snapshot)

        #expect(throws: DomainError.invalidValue(detail: "El nombre del negocio no puede estar vacío")) {
            try data.updateSettings(name: "   \n\t  ", ctx: ctx)
        }
        #expect(data.settings == snapshot)

        // 2. Nombre con más de 80 caracteres
        let eightyOneChars = String(repeating: "B", count: 81)
        #expect(throws: DomainError.invalidValue(detail: "El nombre del negocio no puede tener más de 80 caracteres")) {
            try data.updateSettings(name: eightyOneChars, ctx: ctx)
        }
        #expect(data.settings == snapshot)

        // 3. Margen fuera de rango (0...1000)
        #expect(throws: DomainError.invalidValue(detail: "El margen va de 0 % a 1000 %")) {
            try data.updateSettings(defaultMarginPercent: -1, ctx: ctx)
        }
        #expect(data.settings == snapshot)

        #expect(throws: DomainError.invalidValue(detail: "El margen va de 0 % a 1000 %")) {
            try data.updateSettings(defaultMarginPercent: 1001, ctx: ctx)
        }
        #expect(data.settings == snapshot)

        // 4. Días de precio viejo fuera de rango (1...3650)
        #expect(throws: DomainError.invalidValue(detail: "Los días para considerar un precio viejo van de 1 a 3650")) {
            try data.updateSettings(priceStaleDays: 0, ctx: ctx)
        }
        #expect(data.settings == snapshot)

        #expect(throws: DomainError.invalidValue(detail: "Los días para considerar un precio viejo van de 1 a 3650")) {
            try data.updateSettings(priceStaleDays: 3651, ctx: ctx)
        }
        #expect(data.settings == snapshot)

        // 5. Moneda inválida (no son 3 letras mayúsculas)
        #expect(throws: DomainError.invalidValue(detail: "La moneda debe tener 3 letras mayúsculas")) {
            try data.updateSettings(currency: "mxn", ctx: ctx) // minúsculas
        }
        #expect(data.settings == snapshot)

        #expect(throws: DomainError.invalidValue(detail: "La moneda debe tener 3 letras mayúsculas")) {
            try data.updateSettings(currency: "US", ctx: ctx) // 2 letras
        }
        #expect(data.settings == snapshot)

        #expect(throws: DomainError.invalidValue(detail: "La moneda debe tener 3 letras mayúsculas")) {
            try data.updateSettings(currency: "USDT", ctx: ctx) // 4 letras
        }
        #expect(data.settings == snapshot)

        #expect(throws: DomainError.invalidValue(detail: "La moneda debe tener 3 letras mayúsculas")) {
            try data.updateSettings(currency: "123", ctx: ctx) // números
        }
        #expect(data.settings == snapshot)

        // 6. Atomicidad en borrador con varios campos: si uno falla, ninguno se aplica
        let draft = SettingsUpdateDraft(
            name: "Nuevo Nombre Válido",
            currency: "EUR",
            defaultMarginPercent: -50, // Inválido
            priceStaleDays: 45
        )
        #expect(throws: DomainError.invalidValue(detail: "El margen va de 0 % a 1000 %")) {
            try data.updateSettings(draft: draft, ctx: ctx)
        }
        #expect(data.settings.name == snapshot.name)
        #expect(data.settings.currency == snapshot.currency)
        #expect(data.settings.defaultMarginPercent == snapshot.defaultMarginPercent)
        #expect(data.settings.priceStaleDays == snapshot.priceStaleDays)
    }

    // MARK: - 2. Tablero de costos con el ejemplo canónico de B7

    @Test("Tablero con el ejemplo de B7: 12 pz, tanda de $120 de costo, margen 30")
    func dashboardWithB7Example() throws {
        var data = KitchenData(deviceId: "test-dev")

        // Receta B7: 12 pz, tanda de $120 de costo (12000 centavos), margen 30
        let rec = Recipe(
            id: "rec-galletas-12",
            name: "Galletas 12 pz",
            extraCosts: [ExtraCost(name: "Insumos", costCents: 12000)],
            yieldQuantity: "12",
            yieldUnit: .pz,
            servings: 12,
            marginPercent: 30,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        let dashboard = data.costDashboard(now: testNow)

        #expect(dashboard.totals.totalRecipes == 1)
        #expect(dashboard.totals.incompleteRecipes == 0)
        #expect(dashboard.totals.stalePriceRecipes == 0)
        #expect(dashboard.items.count == 1)

        let item = dashboard.items[0]
        #expect(item.id == "rec-galletas-12")
        #expect(item.name == "Galletas 12 pz")
        #expect(item.yieldQuantity == "12")
        #expect(item.yieldUnit == BaseUnit.pz)
        #expect(item.servings == 12)

        // Costo de tanda: 12000 centavos ($120)
        #expect(item.batchCostCents == 12000)

        // Costo por unidad de rendimiento: 12000 / 12 = 1000 centavos ($10)
        #expect(item.costPerYieldUnitCents == 1000)

        // Costo por porción: 12000 / 12 = 1000 centavos
        #expect(item.costPerServingCents == 1000)

        // Margen efectivo: 30 %
        #expect(item.effectiveMarginPercent == 30)
        #expect(item.marginPercent == 30)

        // Precio sugerido por tanda: 12000 * 1.30 = 15600 centavos ($156)
        #expect(item.suggestedPriceCents == 15600)

        // Precio sugerido por unidad de rendimiento: 1000 * 1.30 = 1300 centavos ($13)
        #expect(item.suggestedPricePerYieldUnitCents == 1300)

        // Ganancia sugerida por tanda: 15600 - 12000 = 3600 centavos ($36)
        #expect(item.suggestedProfitCents == 3600)

        // Completitud y frescura
        #expect(item.complete == true)
        #expect(item.hasStalePrices == false)
    }

    // MARK: - 3. Receta sin precio y orden "por revisar"

    @Test("Una receta sin precio sale incompleta y primero en 'por revisar'")
    func dashboardRecipeWithoutPriceNeedsReviewOrder() throws {
        var data = KitchenData(deviceId: "test-dev")

        // 1. Ingrediente sin precio registrado
        let ingNoPrice = Ingredient(
            id: "ing-sin-precio",
            name: "Vainilla Especial",
            baseUnit: .ml,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.ingredients.append(ingNoPrice)

        // Receta 1: Incompleta (ingrediente sin precio)
        let recIncomplete = Recipe(
            id: "rec-incompleta",
            name: "Pastel Incompleto",
            items: [RecipeItem(kind: .ingredient, refId: ingNoPrice.id, quantity: "10")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 30,
            createdAt: testNow,
            updatedAt: testNow
        )

        // 2. Ingrediente con precio viejo (100 días atrás con priceStaleDays = 90)
        let ingStale = Ingredient(
            id: "ing-viejo",
            name: "Harina",
            baseUnit: .g,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.ingredients.append(ingStale)

        let presStale = Presentation(
            id: "pres-harina",
            ingredientId: ingStale.id,
            brand: "Selecta",
            packageQuantity: "1000",
            createdAt: testNow,
            updatedAt: testNow
        )
        data.presentations.append(presStale)

        let oldDate = Calendar.current.date(byAdding: .day, value: -100, to: testNow)!
        let priceStale = PriceRecord(
            id: "price-harina-old",
            presentationId: presStale.id,
            priceCents: 2000,
            recordedAt: oldDate,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        data.priceRecords.append(priceStale)

        // Receta 2: Completa pero con precio viejo
        let recStale = Recipe(
            id: "rec-stale",
            name: "Pan de Harina",
            items: [RecipeItem(kind: .ingredient, refId: ingStale.id, quantity: "500")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 30,
            createdAt: testNow,
            updatedAt: testNow
        )

        // Receta 3: Completa y al día (con costo extra, sin ingredientes)
        let recFresh = Recipe(
            id: "rec-fresh",
            name: "Galletas Al Día",
            extraCosts: [ExtraCost(name: "Insumos", costCents: 5000)],
            yieldQuantity: "10",
            yieldUnit: .pz,
            marginPercent: 40,
            createdAt: testNow,
            updatedAt: testNow
        )

        // Receta 4: Borrada (no debe figurar en el tablero)
        let recDeleted = Recipe(
            id: "rec-deleted",
            name: "Receta Borrada",
            extraCosts: [ExtraCost(name: "Insumos", costCents: 1000)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow,
            deletedAt: testNow
        )

        data.recipes = [recFresh, recStale, recIncomplete, recDeleted]

        // Consulta en orden .needsReview
        let dashboard = data.costDashboard(order: .needsReview, now: testNow)

        // Solo 3 recetas activas
        #expect(dashboard.totals.totalRecipes == 3)
        #expect(dashboard.totals.incompleteRecipes == 1)
        #expect(dashboard.totals.stalePriceRecipes == 1)
        #expect(dashboard.items.count == 3)

        // Orden de "por revisar":
        // 1º Incompletas
        // 2º Precios viejos
        // 3º El resto (al día)
        #expect(dashboard.items[0].id == "rec-incompleta")
        #expect(dashboard.items[0].complete == false)

        #expect(dashboard.items[1].id == "rec-stale")
        #expect(dashboard.items[1].complete == true)
        #expect(dashboard.items[1].hasStalePrices == true)

        #expect(dashboard.items[2].id == "rec-fresh")
        #expect(dashboard.items[2].complete == true)
        #expect(dashboard.items[2].hasStalePrices == false)
    }

    // MARK: - 4. defaultMarginPercent afecta a recetas sin margen propio

    @Test("Cambiar defaultMarginPercent cambia el precio sugerido de una receta sin margen propio")
    func changeDefaultMarginAffectsRecipeWithoutOwnMargin() throws {
        let ctx = makeContext(prefix: "margin")
        var data = KitchenData(deviceId: "test-dev")

        // Receta sin margen propio (marginPercent = nil)
        let rec = Recipe(
            id: "rec-sin-margen",
            name: "Bizcocho Clásico",
            extraCosts: [ExtraCost(name: "Mano de obra", costCents: 10000)], // $100
            yieldQuantity: "10",
            yieldUnit: .pz,
            marginPercent: nil,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        // 1. Con el defaultMarginPercent inicial (40 %)
        #expect(data.settings.defaultMarginPercent == 40)
        let d1 = data.costDashboard(now: testNow)
        let item1 = d1.items[0]
        #expect(item1.batchCostCents == 10000)
        #expect(item1.effectiveMarginPercent == 40)
        // 10000 * 1.40 = 14000
        #expect(item1.suggestedPriceCents == 14000)
        #expect(item1.suggestedPricePerYieldUnitCents == 1400)
        #expect(item1.suggestedProfitCents == 4000)

        // 2. Modificamos defaultMarginPercent a 50 %
        try data.updateSettings(defaultMarginPercent: 50, ctx: ctx)
        #expect(data.settings.defaultMarginPercent == 50)

        let d2 = data.costDashboard(now: testNow)
        let item2 = d2.items[0]
        #expect(item2.batchCostCents == 10000)
        #expect(item2.effectiveMarginPercent == 50)
        // 10000 * 1.50 = 15000
        #expect(item2.suggestedPriceCents == 15000)
        #expect(item2.suggestedPricePerYieldUnitCents == 1500)
        #expect(item2.suggestedProfitCents == 5000)
    }

    // MARK: - 5. Categorías de gasto

    @Test("Las categorías de gasto salen sin repetir y en el orden pedido")
    func expenseCategoriesDistinctAndOrdered() throws {
        var data = KitchenData(deviceId: "test-dev")

        // Gastos activos con repeticiones y variaciones
        data.expenses = [
            Expense(id: "e1", description: "Luz", amountCents: 5000, spentAt: testNow, category: "Servicios", createdAt: testNow, updatedAt: testNow),
            Expense(id: "e2", description: "Cajas", amountCents: 2000, spentAt: testNow, category: "Empaque", createdAt: testNow, updatedAt: testNow),
            Expense(id: "e3", description: "Agua", amountCents: 1500, spentAt: testNow, category: "Servicios", createdAt: testNow, updatedAt: testNow),
            Expense(id: "e4", description: "Azúcar", amountCents: 4000, spentAt: testNow, category: "Materia prima", createdAt: testNow, updatedAt: testNow),
            Expense(id: "e5", description: "Bolsas", amountCents: 1200, spentAt: testNow, category: "Empaque", createdAt: testNow, updatedAt: testNow),
            Expense(id: "e6", description: "Gas", amountCents: 3000, spentAt: testNow, category: "Servicios", createdAt: testNow, updatedAt: testNow),
            // Sin categoría (nil)
            Expense(id: "e7", description: "Misceláneo", amountCents: 800, spentAt: testNow, category: nil, createdAt: testNow, updatedAt: testNow),
            // Categoría vacía o de solo espacios
            Expense(id: "e8", description: "Propina", amountCents: 500, spentAt: testNow, category: "   ", createdAt: testNow, updatedAt: testNow),
            // Gasto borrado: su categoría no debe contar
            Expense(id: "e9", description: "Herramienta", amountCents: 900, spentAt: testNow, category: "Herramientas", createdAt: testNow, updatedAt: testNow, deletedAt: testNow),
        ]

        // Frecuencia esperada en gastos activos:
        // "Servicios": 3 (e1, e3, e6)
        // "Empaque": 2 (e2, e5)
        // "Materia prima": 1 (e4)
        let categories = data.expenseCategories()
        #expect(categories == ["Servicios", "Empaque", "Materia prima"])

        // Desempate por nombre si tienen la misma frecuencia
        data.expenses.append(
            Expense(id: "e10", description: "Publicidad", amountCents: 1000, spentAt: testNow, category: "Alquiler", createdAt: testNow, updatedAt: testNow)
        )
        // Ahora "Alquiler" y "Materia prima" tienen 1 cada una; "Alquiler" debe ir antes por orden alfabético
        let categoriesWithTie = data.expenseCategories()
        #expect(categoriesWithTie == ["Servicios", "Empaque", "Alquiler", "Materia prima"])
    }

    // MARK: - 6. Criterios de ordenamiento del tablero de costos

    @Test("Criterios de ordenamiento por nombre, costo y ganancia")
    func dashboardSortOrders() throws {
        var data = KitchenData(deviceId: "test-dev")

        // Receta A: Nombre "Chocochips", costo 6000, margen 50 -> precio 9000, ganancia 3000
        let recA = Recipe(
            id: "rec-a",
            name: "Chocochips",
            extraCosts: [ExtraCost(name: "Base", costCents: 6000)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 50,
            createdAt: testNow,
            updatedAt: testNow
        )

        // Receta B: Nombre "Alfajores", costo 10000, margen 20 -> precio 12000, ganancia 2000
        let recB = Recipe(
            id: "rec-b",
            name: "Alfajores",
            extraCosts: [ExtraCost(name: "Base", costCents: 10000)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 20,
            createdAt: testNow,
            updatedAt: testNow
        )

        // Receta C: Nombre "Brownies", costo 2000, margen 300 -> precio 8000, ganancia 6000
        let recC = Recipe(
            id: "rec-c",
            name: "Brownies",
            extraCosts: [ExtraCost(name: "Base", costCents: 2000)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 300,
            createdAt: testNow,
            updatedAt: testNow
        )

        data.recipes = [recA, recB, recC]

        // 1. Por nombre: Alfajores, Brownies, Chocochips
        let byName = data.costDashboard(order: .name, now: testNow)
        #expect(byName.items.map(\.name) == ["Alfajores", "Brownies", "Chocochips"])

        // 2. Por costo de tanda descendente: Alfajores (10000), Chocochips (6000), Brownies (2000)
        let byCost = data.costDashboard(order: .batchCost, now: testNow)
        #expect(byCost.items.map(\.name) == ["Alfajores", "Chocochips", "Brownies"])

        // 3. Por ganancia sugerida descendente: Brownies (6000), Chocochips (3000), Alfajores (2000)
        let byProfit = data.costDashboard(order: .suggestedProfit, now: testNow)
        #expect(byProfit.items.map(\.name) == ["Brownies", "Chocochips", "Alfajores"])
    }

    @Test("Receta cuyo costeo lanza aparece con costos nulos y complete falso")
    func dashboardHandlesCostingFailureGracefully() throws {
        var data = KitchenData(deviceId: "test-dev")

        // Receta con unidad no convertible: ingrediente en gramos, línea en piezas sin conversión
        let ingGrams = Ingredient(
            id: "ing-g",
            name: "Nuez",
            baseUnit: .g,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.ingredients.append(ingGrams)

        let brokenRec = Recipe(
            id: "rec-broken",
            name: "Tarta Rota",
            items: [RecipeItem(kind: .ingredient, refId: ingGrams.id, quantity: "5", unitId: "pz")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 30,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(brokenRec)

        let dashboard = data.costDashboard(now: testNow)
        #expect(dashboard.totals.totalRecipes == 1)
        #expect(dashboard.totals.incompleteRecipes == 1)

        let item = dashboard.items[0]
        #expect(item.id == "rec-broken")
        #expect(item.batchCostCents == nil)
        #expect(item.costPerYieldUnitCents == nil)
        #expect(item.suggestedPriceCents == nil)
        #expect(item.suggestedProfitCents == nil)
        #expect(item.complete == false)
        #expect(item.hasStalePrices == false)
    }
}
