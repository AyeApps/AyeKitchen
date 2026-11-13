import Foundation
import Testing
@testable import KitchenDomain

@Suite("Búsqueda, filtros y orden del catálogo (K7)")
struct CatalogListTests {
    private let now = KitchenCoding.parseDate("2026-11-13T12:00:00.000Z")!

    private struct Fixture {
        var data: KitchenData
        let costco: Supplier
        let walmart: Supplier
        let leche: Ingredient
        let harina: Ingredient
        let huevo: Ingredient
        let kirkland: Presentation
        let lala: Presentation
        let harinaPres: Presentation
        let gen: FixedIdGenerator
    }

    private func makeFixture() throws -> Fixture {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "k7")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // Tiendas / Proveedores
        let costco = try data.createSupplier(name: "Costco", ctx: ctx)
        let walmart = try data.createSupplier(name: "Walmart", ctx: ctx)

        // Ingredientes
        // Leche: grupo "Lácteos"
        let leche = try data.createIngredient(name: "Leche", baseUnit: .ml, group: "Lácteos", ctx: ctx)
        // Harina: grupo "Secos"
        let harina = try data.createIngredient(name: "Harina", baseUnit: .g, group: "Secos", ctx: ctx)
        // Huevo: grupo "Secos", sin marcas
        let huevo = try data.createIngredient(name: "Huevo", baseUnit: .pz, group: "Secos", ctx: ctx)

        // Marcas de leche:
        // 1. Lala en Walmart: $28 (2800 centavos), registrada hace 100 días (vieja / stale)
        let tLala = now.addingTimeInterval(-100 * 86400)
        let ctxLala = MutationContext(now: tLala, newId: { gen.next() })
        let lala = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Lala",
            supplierId: walmart.id,
            packageQuantity: "1000",
            priceCents: 2800,
            ctx: ctxLala
        )

        // 2. Kirkland en Costco: $389 (38900 centavos), registrada hace 2 días (reciente)
        let tKirkland = now.addingTimeInterval(-2 * 86400)
        let ctxKirkland = MutationContext(now: tKirkland, newId: { gen.next() })
        let kirkland = try data.createPresentation(
            ingredientId: leche.id,
            brand: "Kirkland",
            supplierId: costco.id,
            packageQuantity: "10000",
            priceCents: 38900,
            ctx: ctxKirkland
        )

        // Marca de harina: sin tienda y sin precio
        let harinaPres = try data.createPresentation(
            ingredientId: harina.id,
            brand: "San Antonio",
            supplierId: nil,
            packageQuantity: "1000",
            priceCents: nil,
            ctx: ctx
        )

        return Fixture(
            data: data,
            costco: costco,
            walmart: walmart,
            leche: leche,
            harina: harina,
            huevo: huevo,
            kirkland: kirkland,
            lala: lala,
            harinaPres: harinaPres,
            gen: gen
        )
    }

    @Test("Sin filtros: todos los ingredientes en orden A–Z con highlightsBrand falso")
    func noFilters() throws {
        let fixture = try makeFixture()
        let items = fixture.data.catalogList(CatalogFilter(), now: now)

        #expect(items.count == 3)
        #expect(items.map(\.ingredient.name) == ["Harina", "Huevo", "Leche"])

        // Harina: marca mostrada San Antonio, highlightsBrand falso
        #expect(items[0].shownBrand?.brand == "San Antonio")
        #expect(items[0].highlightsBrand == false)

        // Huevo: sin marca, highlightsBrand falso
        #expect(items[1].shownBrand == nil)
        #expect(items[1].highlightsBrand == false)

        // Leche: marca mostrada Kirkland (vigente / más reciente), highlightsBrand falso
        #expect(items[2].shownBrand?.brand == "Kirkland")
        #expect(items[2].highlightsBrand == false)
    }

    @Test("Filtro de tienda Costco: solo leche con Kirkland y highlightsBrand verdadero")
    func storeCostcoFilter() throws {
        let fixture = try makeFixture()
        let filter = CatalogFilter(store: .store(id: fixture.costco.id))
        let items = fixture.data.catalogList(filter, now: now)

        #expect(items.count == 1)
        #expect(items[0].ingredient.name == "Leche")
        #expect(items[0].shownBrand?.brand == "Kirkland")
        #expect(items[0].shownBrand?.supplierId == fixture.costco.id)
        #expect(items[0].highlightsBrand == true)
    }

    @Test("Filtro .noStore: solo harina y highlightsBrand verdadero")
    func noStoreFilter() throws {
        let fixture = try makeFixture()
        let filter = CatalogFilter(store: .noStore)
        let items = fixture.data.catalogList(filter, now: now)

        #expect(items.count == 1)
        #expect(items[0].ingredient.name == "Harina")
        #expect(items[0].shownBrand?.brand == "San Antonio")
        #expect(items[0].shownBrand?.supplierId == nil)
        #expect(items[0].highlightsBrand == true)
    }

    @Test("Búsqueda por tienda 'costco' y por marca 'kirkland': leche con Kirkland y highlightsBrand verdadero")
    func searchStoreAndBrand() throws {
        let fixture = try makeFixture()

        // Buscar tienda "costco"
        let byStore = fixture.data.catalogList(CatalogFilter(query: "costco"), now: now)
        #expect(byStore.count == 1)
        #expect(byStore[0].ingredient.name == "Leche")
        #expect(byStore[0].shownBrand?.brand == "Kirkland")
        #expect(byStore[0].highlightsBrand == true)

        // Buscar marca "kirkland"
        let byBrand = fixture.data.catalogList(CatalogFilter(query: "kirkland"), now: now)
        #expect(byBrand.count == 1)
        #expect(byBrand[0].ingredient.name == "Leche")
        #expect(byBrand[0].shownBrand?.brand == "Kirkland")
        #expect(byBrand[0].highlightsBrand == true)

        // Buscar tienda "walmart" (solo coincide Lala)
        let byWalmart = fixture.data.catalogList(CatalogFilter(query: "walmart"), now: now)
        #expect(byWalmart.count == 1)
        #expect(byWalmart[0].ingredient.name == "Leche")
        #expect(byWalmart[0].shownBrand?.brand == "Lala")
        #expect(byWalmart[0].highlightsBrand == true)
    }

    @Test("Búsqueda 'lacteos' sin acento coincide por grupo con highlightsBrand falso")
    func searchGroupWithoutAccent() throws {
        let fixture = try makeFixture()
        let items = fixture.data.catalogList(CatalogFilter(query: "lacteos"), now: now)

        #expect(items.count == 1)
        #expect(items[0].ingredient.name == "Leche")
        #expect(items[0].ingredient.group == "Lácteos")
        #expect(items[0].shownBrand?.brand == "Kirkland")
        // No coincidió SOLO por marca/tienda y no hay otros filtros: highlightsBrand es falso
        #expect(items[0].highlightsBrand == false)
    }

    @Test("Búsqueda 'LECHE' en mayúsculas coincide por nombre con highlightsBrand falso")
    func searchNameUppercase() throws {
        let fixture = try makeFixture()
        let items = fixture.data.catalogList(CatalogFilter(query: "LECHE"), now: now)

        #expect(items.count == 1)
        #expect(items[0].ingredient.name == "Leche")
        #expect(items[0].shownBrand?.brand == "Kirkland")
        #expect(items[0].highlightsBrand == false)
    }

    @Test("Filtro .withoutPrice: incluye harina y huevo")
    func withoutPriceFilter() throws {
        let fixture = try makeFixture()
        let items = fixture.data.catalogList(CatalogFilter(price: .withoutPrice), now: now)

        #expect(items.count == 2)
        #expect(items.map(\.ingredient.name) == ["Harina", "Huevo"])

        // Harina tiene marca mostrada sin precio -> highlightsBrand es true (filtro de precio != .all)
        #expect(items[0].shownBrand?.brand == "San Antonio")
        #expect(items[0].highlightsBrand == true)

        // Huevo no tiene marca mostrada -> highlightsBrand es false
        #expect(items[1].shownBrand == nil)
        #expect(items[1].highlightsBrand == false)
    }

    @Test("Filtro .stale con tienda Walmart: leche con Lala")
    func staleWithWalmart() throws {
        let fixture = try makeFixture()

        // Con tienda Walmart, la única candidata es Lala, que tiene precio viejo (100 días > 90)
        let filterWalmart = CatalogFilter(store: .store(id: fixture.walmart.id), price: .stale)
        let itemsWalmart = fixture.data.catalogList(filterWalmart, now: now)
        #expect(itemsWalmart.count == 1)
        #expect(itemsWalmart[0].ingredient.name == "Leche")
        #expect(itemsWalmart[0].shownBrand?.brand == "Lala")
        #expect(itemsWalmart[0].shownBrand?.priceIsStale == true)
        #expect(itemsWalmart[0].highlightsBrand == true)

        // Sin filtro de tienda (store = .all), la marca mostrada de Leche es Kirkland (reciente, no stale)
        // por lo que no debe salir en .stale
        let filterAll = CatalogFilter(price: .stale)
        let itemsAll = fixture.data.catalogList(filterAll, now: now)
        #expect(itemsAll.isEmpty)
    }

    @Test("Filtro de rango 100–500 pesos y rango con un extremo nulo")
    func rangePriceFilter() throws {
        let fixture = try makeFixture()

        // Kirkland cuesta $389 (38900 centavos). Lala cuesta $28 (2800 centavos).
        // Rango 100–500 pesos (10000 a 50000 centavos): incluye Leche (Kirkland $389)
        let range100to500 = CatalogFilter(price: .range(minCents: 10000, maxCents: 50000))
        let itemsRange = fixture.data.catalogList(range100to500, now: now)
        #expect(itemsRange.count == 1)
        #expect(itemsRange[0].ingredient.name == "Leche")
        #expect(itemsRange[0].shownBrand?.brand == "Kirkland")
        #expect(itemsRange[0].highlightsBrand == true)

        // Rango con extremo inferior nulo: hasta $500 pesos (<= 50000 centavos)
        let upTo500 = CatalogFilter(price: .range(minCents: nil, maxCents: 50000))
        let itemsUpTo500 = fixture.data.catalogList(upTo500, now: now)
        #expect(itemsUpTo500.count == 1)
        #expect(itemsUpTo500[0].ingredient.name == "Leche")

        // Rango con extremo superior nulo: desde $100 pesos (>= 10000 centavos)
        let from100 = CatalogFilter(price: .range(minCents: 10000, maxCents: nil))
        let itemsFrom100 = fixture.data.catalogList(from100, now: now)
        #expect(itemsFrom100.count == 1)
        #expect(itemsFrom100[0].ingredient.name == "Leche")

        // Rango invertido: minCents 50000 y maxCents 10000 (debe tratarse como 10000 a 50000)
        let invertedRange = CatalogFilter(price: .range(minCents: 50000, maxCents: 10000))
        let itemsInverted = fixture.data.catalogList(invertedRange, now: now)
        #expect(itemsInverted.count == 1)
        #expect(itemsInverted[0].ingredient.name == "Leche")

        // Rango donde no cae el precio: 40000 a 50000 centavos
        let outOfRange = CatalogFilter(price: .range(minCents: 40000, maxCents: 50000))
        let itemsOutOfRange = fixture.data.catalogList(outOfRange, now: now)
        #expect(itemsOutOfRange.isEmpty)

        // Rango para Lala con tienda Walmart: 2000 a 3000 centavos ($20 a $30)
        let rangeWalmart = CatalogFilter(store: .store(id: fixture.walmart.id), price: .range(minCents: 2000, maxCents: 3000))
        let itemsWalmart = fixture.data.catalogList(rangeWalmart, now: now)
        #expect(itemsWalmart.count == 1)
        #expect(itemsWalmart[0].shownBrand?.brand == "Lala")
    }

    @Test("Los tres órdenes por precio con los sin precio al final por nombre")
    func priceSorts() throws {
        var fixture = try makeFixture()
        let gen = fixture.gen
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // Agregamos Mantequilla con precio $50 (5000 centavos) y fecha intermedia (-10 días)
        let tMantequilla = now.addingTimeInterval(-10 * 86400)
        let ctxMantequilla = MutationContext(now: tMantequilla, newId: { gen.next() })
        let mantequilla = try fixture.data.createIngredient(name: "Mantequilla", baseUnit: .g, group: "Lácteos", ctx: ctx)
        try fixture.data.createPresentation(
            ingredientId: mantequilla.id,
            brand: "Gloria",
            packageQuantity: "1000",
            priceCents: 5000,
            ctx: ctxMantequilla
        )

        // 1. priceLowToHigh: Mantequilla ($50), Leche ($389), Harina (sin precio), Huevo (sin precio)
        let sortLowToHigh = fixture.data.catalogList(CatalogFilter(sort: .priceLowToHigh), now: now)
        #expect(sortLowToHigh.map(\.ingredient.name) == ["Mantequilla", "Leche", "Harina", "Huevo"])
        #expect(sortLowToHigh[0].highlightsBrand == true)
        #expect(sortLowToHigh[1].highlightsBrand == true)
        #expect(sortLowToHigh[2].highlightsBrand == true) // Harina tiene shownBrand
        #expect(sortLowToHigh[3].highlightsBrand == false) // Huevo no tiene shownBrand

        // 2. priceHighToLow: Leche ($389), Mantequilla ($50), Harina (sin precio), Huevo (sin precio)
        let sortHighToLow = fixture.data.catalogList(CatalogFilter(sort: .priceHighToLow), now: now)
        #expect(sortHighToLow.map(\.ingredient.name) == ["Leche", "Mantequilla", "Harina", "Huevo"])

        // 3. oldestPrice: Mantequilla (-10 días), Leche (-2 días), Harina (sin precio), Huevo (sin precio)
        let sortOldest = fixture.data.catalogList(CatalogFilter(sort: .oldestPrice), now: now)
        #expect(sortOldest.map(\.ingredient.name) == ["Mantequilla", "Leche", "Harina", "Huevo"])

        // 4. Empate de precio se desempata por nombre
        let crema = try fixture.data.createIngredient(name: "Crema", baseUnit: .ml, group: "Lácteos", ctx: ctx)
        try fixture.data.createPresentation(
            ingredientId: crema.id,
            brand: "Alpura",
            packageQuantity: "1000",
            priceCents: 5000,
            ctx: ctxMantequilla
        )
        // Crema y Mantequilla empatan en $50: "Crema" < "Mantequilla"
        let sortTie = fixture.data.catalogList(CatalogFilter(sort: .priceLowToHigh), now: now)
        #expect(sortTie.map(\.ingredient.name) == ["Crema", "Mantequilla", "Leche", "Harina", "Huevo"])
    }

    @Test("Filtro exacto por grupo")
    func groupFilter() throws {
        let fixture = try makeFixture()

        let lacteos = fixture.data.catalogList(CatalogFilter(group: "Lácteos"), now: now)
        #expect(lacteos.count == 1)
        #expect(lacteos[0].ingredient.name == "Leche")

        let secos = fixture.data.catalogList(CatalogFilter(group: "  Secos  "), now: now)
        #expect(secos.count == 2)
        #expect(secos.map(\.ingredient.name) == ["Harina", "Huevo"])

        let inexistente = fixture.data.catalogList(CatalogFilter(group: "Frutas"), now: now)
        #expect(inexistente.isEmpty)
    }

    @Test("catalogGroups devuelve los grupos de ingredientes activos sin espacios, sin repetidos y ordenados")
    func catalogGroupsQuery() throws {
        var fixture = try makeFixture()
        let gen = fixture.gen
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // Con los ingredientes iniciales (Leche: "Lácteos", Harina: "Secos", Huevo: "Secos")
        #expect(fixture.data.catalogGroups() == ["Lácteos", "Secos"])

        // Agregar ingrediente con espacios alrededor del grupo y otro sin grupo
        try fixture.data.createIngredient(name: "Yogurt", baseUnit: .ml, group: "  Lácteos  ", ctx: ctx)
        try fixture.data.createIngredient(name: "Sal", baseUnit: .g, group: nil, ctx: ctx)
        try fixture.data.createIngredient(name: "Agua", baseUnit: .ml, group: "   ", ctx: ctx)

        #expect(fixture.data.catalogGroups() == ["Lácteos", "Secos"])
    }

    @Test("Ingrediente borrado no sale en catalogList ni sus grupos si era el único")
    func deletedIngredientExcluded() throws {
        var fixture = try makeFixture()
        let gen = fixture.gen
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // Agregamos ingrediente en grupo exclusivo "Dulces"
        let azucar = try fixture.data.createIngredient(name: "Azúcar", baseUnit: .g, group: "Dulces", ctx: ctx)
        #expect(fixture.data.catalogGroups() == ["Dulces", "Lácteos", "Secos"])

        let listBefore = fixture.data.catalogList(CatalogFilter(), now: now)
        #expect(listBefore.contains { $0.ingredient.id == azucar.id })

        // Borrado suave
        try fixture.data.deleteIngredient(id: azucar.id, ctx: ctx)

        let listAfter = fixture.data.catalogList(CatalogFilter(), now: now)
        #expect(!listAfter.contains { $0.ingredient.id == azucar.id })
        #expect(fixture.data.catalogGroups() == ["Lácteos", "Secos"])
    }
}
