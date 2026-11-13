import Foundation
import Testing
@testable import KitchenDomain

@Suite("Reglas de Paquete Grande en Marcas (K6)")
struct PackRulesTests {
    private let now = KitchenCoding.parseDate("2026-11-12T10:00:00.000Z")!

    @Test("Crear marca con paquete grande: 24 piezas de 900 ml y 24 piezas de 0.9 l")
    func createPackPresentation() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)

        // 24 piezas de 900 ml -> total 21600 ml
        let presMl = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala Reja ml",
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            ctx: ctx
        )
        #expect(presMl.packageQuantity == "21600")
        #expect(presMl.packCount == 24)
        #expect(presMl.packItemQuantity == "900")

        // 24 piezas de 0.9 l (sys.l) -> total 21600 ml, packItemQuantity "900"
        let presL = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala Reja l",
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "0.9",
            packItemUnitId: "sys.l",
            ctx: ctx
        )
        #expect(presL.packageQuantity == "21600")
        #expect(presL.packCount == 24)
        #expect(presL.packItemQuantity == "900")
    }

    @Test("Validaciones de creación con paquete grande: packCount y packItemQuantity inválidos")
    func createPackValidations() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)

        // packCount == 0
        #expect(throws: DomainError.invalidValue(detail: "Las piezas del paquete deben ser entre 1 y 10,000")) {
            try data.createPresentation(
                ingredientId: leche.id,
                brand: "Lala 0",
                packageQuantity: "100",
                packCount: 0,
                packItemQuantity: "900",
                ctx: ctx
            )
        }

        // packCount == 10_001
        #expect(throws: DomainError.invalidValue(detail: "Las piezas del paquete deben ser entre 1 y 10,000")) {
            try data.createPresentation(
                ingredientId: leche.id,
                brand: "Lala 10001",
                packageQuantity: "100",
                packCount: 10_001,
                packItemQuantity: "900",
                ctx: ctx
            )
        }

        // Sin packItemQuantity
        #expect(throws: DomainError.invalidValue(detail: "Indica cuánto trae cada pieza")) {
            try data.createPresentation(
                ingredientId: leche.id,
                brand: "Lala Sin ItemQty",
                packageQuantity: "100",
                packCount: 24,
                packItemQuantity: nil,
                ctx: ctx
            )
        }

        // packItemQuantity <= 0 o no numérico
        #expect(throws: DomainError.invalidValue(detail: "Indica cuánto trae cada pieza")) {
            try data.createPresentation(
                ingredientId: leche.id,
                brand: "Lala Cero",
                packageQuantity: "100",
                packCount: 24,
                packItemQuantity: "0",
                ctx: ctx
            )
        }

        #expect(throws: DomainError.invalidValue(detail: "Indica cuánto trae cada pieza")) {
            try data.createPresentation(
                ingredientId: leche.id,
                brand: "Lala Negativo",
                packageQuantity: "100",
                packCount: 24,
                packItemQuantity: "-100",
                ctx: ctx
            )
        }

        #expect(throws: DomainError.invalidValue(detail: "Indica cuánto trae cada pieza")) {
            try data.createPresentation(
                ingredientId: leche.id,
                brand: "Lala Invalido",
                packageQuantity: "100",
                packCount: 24,
                packItemQuantity: "leche",
                ctx: ctx
            )
        }
    }

    @Test("Pieza en unidad no convertible deja pasar error de convertToBase")
    func unconvertiblePackItemUnit() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)

        #expect(throws: DomainError.unitNotConvertible(detail: "Define cuántos ml tiene 1 kilogramo de Leche")) {
            try data.createPresentation(
                ingredientId: leche.id,
                brand: "Lala Kg",
                packageQuantity: "100",
                packCount: 24,
                packItemQuantity: "1",
                packItemUnitId: "sys.kg",
                ctx: ctx
            )
        }
    }

    @Test("Crear sin paquete deja campos nulos")
    func createWithoutPack() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)

        let pres = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala Litro",
            packageQuantity: "1000",
            ctx: ctx
        )
        #expect(pres.packageQuantity == "1000")
        #expect(pres.packCount == nil)
        #expect(pres.packItemQuantity == nil)

        // Si packCount es nulo aunque llegue packItemQuantity, los campos quedan nulos
        let presConItem = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala Litro 2",
            packageQuantity: "1000",
            packCount: nil,
            packItemQuantity: "900",
            ctx: ctx
        )
        #expect(presConItem.packageQuantity == "1000")
        #expect(presConItem.packCount == nil)
        #expect(presConItem.packItemQuantity == nil)
    }

    @Test("Update de presentación con y sin paquete grande")
    func updatePresentationPack() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)

        var pres = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala Reja",
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            ctx: ctx
        )
        #expect(pres.packageQuantity == "21600")
        #expect(pres.packCount == 24)
        #expect(pres.packItemQuantity == "900")

        // 1. Cambiar a 12 piezas de 1 l
        pres = try data.updatePresentation(
            id: pres.id,
            packCount: .some(12),
            packItemQuantity: "1",
            packItemUnitId: "sys.l",
            ctx: ctx
        )
        #expect(pres.packageQuantity == "12000")
        #expect(pres.packCount == 12)
        #expect(pres.packItemQuantity == "1000")

        // 2. Editar solo la marca no toca el paquete
        pres = try data.updatePresentation(
            id: pres.id,
            brand: "Lala Reja Docena",
            ctx: ctx
        )
        #expect(pres.brand == "Lala Reja Docena")
        #expect(pres.packageQuantity == "12000")
        #expect(pres.packCount == 12)
        #expect(pres.packItemQuantity == "1000")

        // 3. Mandar solo packageQuantity borra el paquete
        pres = try data.updatePresentation(
            id: pres.id,
            packageQuantity: "5000",
            ctx: ctx
        )
        #expect(pres.packageQuantity == "5000")
        #expect(pres.packCount == nil)
        #expect(pres.packItemQuantity == nil)

        // Restaurar paquete: 6 piezas de 500 ml -> 3000 ml
        pres = try data.updatePresentation(
            id: pres.id,
            packCount: .some(6),
            packItemQuantity: "500",
            ctx: ctx
        )
        #expect(pres.packageQuantity == "3000")
        #expect(pres.packCount == 6)
        #expect(pres.packItemQuantity == "500")

        // 4. Quitar el paquete con .some(nil) sin packageQuantity -> total se queda igual
        pres = try data.updatePresentation(
            id: pres.id,
            packCount: .some(nil),
            ctx: ctx
        )
        #expect(pres.packageQuantity == "3000")
        #expect(pres.packCount == nil)
        #expect(pres.packItemQuantity == nil)

        // Restaurar paquete
        pres = try data.updatePresentation(
            id: pres.id,
            packCount: .some(6),
            packItemQuantity: "500",
            ctx: ctx
        )
        #expect(pres.packCount == 6)

        // 5. Quitar el paquete con .some(nil) con packageQuantity -> total se actualiza
        pres = try data.updatePresentation(
            id: pres.id,
            packageQuantity: "2500",
            packCount: .some(nil),
            ctx: ctx
        )
        #expect(pres.packageQuantity == "2500")
        #expect(pres.packCount == nil)
        #expect(pres.packItemQuantity == nil)
    }

    @Test("pricePerPackItemCents en CatalogPresentation")
    func pricePerPackItem() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)

        // Reja de 24 a $389.00 (38900 centavos) -> 1620.8333... -> 1621 centavos
        let presConPrecio = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala 24",
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            priceCents: 38900,
            ctx: ctx
        )

        // Reja de 24 sin precio -> nulo
        let presSinPrecio = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala 24 Sin Precio",
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            ctx: ctx
        )

        // Paquete simple con precio -> nulo
        let presSinPaquete = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala Simple",
            packageQuantity: "21600",
            priceCents: 38900,
            ctx: ctx
        )

        let catalog = try data.presentations(forIngredient: leche.id, now: now)
        let catConPrecio = try #require(catalog.first { $0.id == presConPrecio.id })
        let catSinPrecio = try #require(catalog.first { $0.id == presSinPrecio.id })
        let catSinPaquete = try #require(catalog.first { $0.id == presSinPaquete.id })

        #expect(catConPrecio.pricePerPackItemCents == 1621)
        #expect(catSinPrecio.pricePerPackItemCents == nil)
        #expect(catSinPaquete.pricePerPackItemCents == nil)
    }

    @Test("Receta con leche en paquete grande cuesta lo mismo que con marca simple al mismo precio")
    func recipeCostingEquivalence() throws {
        let genA = FixedIdGenerator(prefix: "a")
        let ctxA = MutationContext(now: now, newId: { genA.next() })
        var dataA = KitchenData.empty(deviceId: "dev-a")

        let lecheA = try dataA.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctxA)
        try dataA.createPresentation(
            ingredientId: lecheA.id,
            brand: "Lala Reja",
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            priceCents: 38900,
            ctx: ctxA
        )
        let recA = try dataA.createRecipe(
            name: "Flan",
            items: [RecipeItem(kind: .ingredient, refId: lecheA.id, quantity: "500")],
            yieldQuantity: "8",
            yieldUnit: .pz,
            ctx: ctxA
        )
        let costA = try dataA.calculateRecipeCost(recipeId: recA.id, now: now)

        let genB = FixedIdGenerator(prefix: "b")
        let ctxB = MutationContext(now: now, newId: { genB.next() })
        var dataB = KitchenData.empty(deviceId: "dev-b")

        let lecheB = try dataB.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctxB)
        try dataB.createPresentation(
            ingredientId: lecheB.id,
            brand: "Lala Simple",
            packageQuantity: "21600",
            priceCents: 38900,
            ctx: ctxB
        )
        let recB = try dataB.createRecipe(
            name: "Flan",
            items: [RecipeItem(kind: .ingredient, refId: lecheB.id, quantity: "500")],
            yieldQuantity: "8",
            yieldUnit: .pz,
            ctx: ctxB
        )
        let costB = try dataB.calculateRecipeCost(recipeId: recB.id, now: now)

        #expect(costA.batchCostCents == costB.batchCostCents)
        #expect(costA.ingredientsCostCents == costB.ingredientsCostCents)
        #expect(costA.lines.first?.costCents == costB.lines.first?.costCents)
    }

    @Test("Ida y vuelta por KitchenCoding con paquete y lectura de JSON viejo")
    func codingPackRoundTrip() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)
        let pres = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala Reja",
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            ctx: ctx
        )

        let encoded = try KitchenCoding.encode(data)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"pack_count\":24"))
        #expect(json.contains("\"pack_item_quantity\":\"900\""))

        let decoded = try KitchenCoding.decode(encoded)
        let decodedPres = try #require(decoded.presentations.first { $0.id == pres.id })
        #expect(decodedPres.packCount == 24)
        #expect(decodedPres.packItemQuantity == "900")
        #expect(decodedPres.packageQuantity == "21600")

        // JSON viejo sin pack_count ni pack_item_quantity
        let oldJson = """
        {
          "schema_version": 1,
          "exported_at": "2026-11-05T16:56:13.264Z",
          "device_id": "old-device",
          "presentations": [
            {
              "id": "pres-old",
              "ingredient_id": "ing-1",
              "brand": "Selecta",
              "package_quantity": "1000",
              "created_at": "2026-11-05T16:56:13.264Z",
              "updated_at": "2026-11-05T16:56:13.264Z"
            }
          ]
        }
        """
        let decodedOld = try KitchenCoding.decode(Data(oldJson.utf8))
        let oldPres = try #require(decodedOld.presentations.first)
        #expect(oldPres.packCount == nil)
        #expect(oldPres.packItemQuantity == nil)
        #expect(oldPres.packageQuantity == "1000")
    }

    @Test("Etiqueta en costeo (presentationLabel) con y sin paquete")
    func presentationLabelFormat() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let sup = try data.createSupplier(name: "Costco", ctx: ctx)
        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, ctx: ctx)

        // Con paquete y proveedor: "Lala · Costco · 24 × 900 ml"
        let presConSup = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala",
            supplierId: sup.id,
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            priceCents: 38900,
            ctx: ctx
        )
        let rec1 = try data.createRecipe(
            name: "Postre 1",
            items: [RecipeItem(kind: .ingredient, refId: leche.id, quantity: "200", pinnedPresentationId: presConSup.id)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )
        let cost1 = try data.calculateRecipeCost(recipeId: rec1.id, now: now)
        #expect(cost1.lines.first?.presentationLabel == "Lala · Costco · 24 × 900 ml")

        // Con paquete sin proveedor: "Lala · 24 × 900 ml"
        let presSinSup = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala",
            supplierId: nil,
            packageQuantity: "ignorada",
            packCount: 24,
            packItemQuantity: "900",
            priceCents: 38900,
            ctx: ctx
        )
        let rec2 = try data.createRecipe(
            name: "Postre 2",
            items: [RecipeItem(kind: .ingredient, refId: leche.id, quantity: "200", pinnedPresentationId: presSinSup.id)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )
        let cost2 = try data.calculateRecipeCost(recipeId: rec2.id, now: now)
        #expect(cost2.lines.first?.presentationLabel == "Lala · 24 × 900 ml")

        // Sin paquete con proveedor: "Selecta · Costco · 1000 g"
        let harina = try data.createIngredient(name: "Harina", baseUnit: .g, ctx: ctx)
        let presHarina = try data.createPresentation(
            ingredientId: harina.id,
            brand: "Selecta",
            supplierId: sup.id,
            packageQuantity: "1000",
            priceCents: 2350,
            ctx: ctx
        )
        let rec3 = try data.createRecipe(
            name: "Pan",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "300", pinnedPresentationId: presHarina.id)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )
        let cost3 = try data.calculateRecipeCost(recipeId: rec3.id, now: now)
        #expect(cost3.lines.first?.presentationLabel == "Selecta · Costco · 1000 g")

        // Sin paquete sin proveedor: "Selecta · 1000 g"
        let presHarinaSinSup = try data.createPresentation(
            ingredientId: harina.id,
            brand: "Selecta",
            supplierId: nil,
            packageQuantity: "1000",
            priceCents: 2350,
            ctx: ctx
        )
        let rec4 = try data.createRecipe(
            name: "Pan 2",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "300", pinnedPresentationId: presHarinaSinSup.id)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )
        let cost4 = try data.calculateRecipeCost(recipeId: rec4.id, now: now)
        #expect(cost4.lines.first?.presentationLabel == "Selecta · 1000 g")
    }
}
