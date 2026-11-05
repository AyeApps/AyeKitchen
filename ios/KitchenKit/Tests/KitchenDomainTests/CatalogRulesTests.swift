import Foundation
import Testing
@testable import KitchenDomain

// MARK: - Helper de IDs para pruebas con MutationContext

final class FixedIdGenerator: @unchecked Sendable {
    private var counter = 0
    private let lock = NSLock()
    let prefix: String

    init(prefix: String = "test") {
        self.prefix = prefix
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        return "\(prefix)-\(counter)"
    }
}

// MARK: - Pruebas de Unidades

@Suite("Reglas del Catálogo - Unidades")
struct UnitRulesTests {
    private let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    @Test("Listar unidades disponibles incluye sistema y custom, ordenadas por base_unit y factor")
    func listUnits() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "unit")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        try data.createUnit(name: "Cucharón", abbreviation: "cchn", baseUnit: .ml, factorToBase: "60", ctx: ctx)
        try data.createUnit(name: "Pizca", abbreviation: "pzc", baseUnit: .g, factorToBase: "0.5", ctx: ctx)

        let available = data.availableUnits(now: now)
        #expect(available.count >= 14) // 12 del sistema + 2 custom

        let taza = available.first { $0.abbreviation == "tz" }
        #expect(taza != nil)
        #expect(taza?.name == "taza")
        #expect(taza?.baseUnit == .ml)
        #expect(taza?.factorToBase == "240")
        #expect(taza?.isSystem == true)

        let cucharón = available.first { $0.abbreviation == "cchn" }
        #expect(cucharón != nil)
        #expect(cucharón?.isSystem == false)
        #expect(cucharón?.factorToBase == "60")

        // Verificar orden: base_unit.rawValue ("g" < "ml" < "pz")
        for i in 0..<(available.count - 1) {
            let u1 = available[i]
            let u2 = available[i + 1]
            if u1.baseUnit == u2.baseUnit {
                let f1 = Qty.decimal(u1.factorToBase) ?? 0
                let f2 = Qty.decimal(u2.factorToBase) ?? 0
                #expect(f1 <= f2)
            } else {
                #expect(u1.baseUnit.rawValue < u2.baseUnit.rawValue)
            }
        }
    }

    @Test("CRUD de unidad personalizada")
    func crudCustomUnit() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "u")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // 1. Crear
        let created = try data.createUnit(
            name: "Cucharón",
            abbreviation: "cchn",
            baseUnit: .ml,
            factorToBase: "60",
            ctx: ctx
        )
        #expect(created.id == "u-1")
        #expect(created.name == "Cucharón")
        #expect(created.abbreviation == "cchn")
        #expect(created.factorToBase == "60")
        #expect(created.createdAt == now)
        #expect(created.updatedAt == now)

        // 2. Editar
        let t1 = now.addingTimeInterval(3600)
        let ctx1 = MutationContext(now: t1, newId: { gen.next() })
        let patched = try data.updateUnit(
            id: created.id,
            name: "Cucharón Grande",
            factorToBase: "75",
            ctx: ctx1
        )
        #expect(patched.name == "Cucharón Grande")
        #expect(patched.factorToBase == "75")
        #expect(patched.abbreviation == "cchn")
        #expect(patched.updatedAt == t1)

        // 3. Borrar
        let t2 = now.addingTimeInterval(7200)
        let ctx2 = MutationContext(now: t2, newId: { gen.next() })
        try data.deleteUnit(id: created.id, ctx: ctx2)

        #expect(data.units.first { $0.id == created.id }?.deletedAt == t2)
        #expect(data.units.first { $0.id == created.id }?.isActive == false)

        // 4. Intentar editar o borrar de nuevo lanza NOT_FOUND
        #expect(throws: DomainError.notFound(detail: "Unidad no encontrada")) {
            try data.updateUnit(id: created.id, name: "Otro", ctx: ctx2)
        }
        #expect(throws: DomainError.notFound(detail: "Unidad no encontrada")) {
            try data.deleteUnit(id: created.id, ctx: ctx2)
        }
    }

    @Test("Unidades del sistema son de solo lectura")
    func systemUnitsReadonly() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let ctx = MutationContext(now: now)

        #expect(throws: DomainError.systemUnitReadonly(detail: "No se pueden editar unidades del sistema")) {
            try data.updateUnit(id: "sys.tz", name: "Taza Modificada", ctx: ctx)
        }
        #expect(throws: DomainError.systemUnitReadonly(detail: "No se pueden eliminar unidades del sistema")) {
            try data.deleteUnit(id: "sys.tz", ctx: ctx)
        }
    }

    @Test("Nombres y abreviaturas duplicadas")
    func duplicateUnitNameOrAbbr() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "u")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // Duplicado con nombre del sistema (case-insensitive)
        #expect(throws: DomainError.duplicateName(detail: "Ya existe una unidad con ese nombre o abreviatura")) {
            try data.createUnit(name: "TAZA", abbreviation: "tz_custom", baseUnit: .ml, factorToBase: "240", ctx: ctx)
        }

        // Duplicado con abreviatura del sistema (case-insensitive)
        #expect(throws: DomainError.duplicateName(detail: "Ya existe una unidad con ese nombre o abreviatura")) {
            try data.createUnit(name: "Taza personalizada", abbreviation: "TZ", baseUnit: .ml, factorToBase: "250", ctx: ctx)
        }

        // Crear una unidad propia
        try data.createUnit(name: "Pizca", abbreviation: "pzc", baseUnit: .g, factorToBase: "0.5", ctx: ctx)

        // Duplicado con unidad propia
        #expect(throws: DomainError.duplicateName(detail: "Ya existe una unidad con ese nombre o abreviatura")) {
            try data.createUnit(name: "pizca", abbreviation: "pzc2", baseUnit: .g, factorToBase: "1", ctx: ctx)
        }
        #expect(throws: DomainError.duplicateName(detail: "Ya existe una unidad con ese nombre o abreviatura")) {
            try data.createUnit(name: "Otra Pizca", abbreviation: "PZC", baseUnit: .g, factorToBase: "1", ctx: ctx)
        }
    }

    @Test("Borrar unidad en uso en ingrediente lanza IN_USE")
    func deleteUnitInUseIngredient() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let unit = try data.createUnit(name: "Gotero", abbreviation: "gt", baseUnit: .ml, factorToBase: "0.05", ctx: ctx)

        // Crear ingrediente que usa la unidad en conversiones
        try data.createIngredient(
            name: "Esencia de vainilla",
            baseUnit: .ml,
            conversions: [IngredientConversion(unitId: unit.id, quantityInBase: "0.05")],
            ctx: ctx
        )

        #expect(throws: DomainError.inUse(detail: "La unidad está en uso en ingredientes")) {
            try data.deleteUnit(id: unit.id, ctx: ctx)
        }
    }

    @Test("Borrar unidad en uso en receta lanza IN_USE")
    func deleteUnitInUseRecipe() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let unit = try data.createUnit(name: "Barra", abbreviation: "bar", baseUnit: .g, factorToBase: "90", ctx: ctx)

        data.recipes.append(
            Recipe(
                id: "rec-1",
                name: "Galletas",
                items: [RecipeItem(kind: .ingredient, refId: "dummy", quantity: "2", unitId: unit.id)],
                yieldQuantity: "10",
                yieldUnit: .pz,
                createdAt: now,
                updatedAt: now
            )
        )

        #expect(throws: DomainError.inUse(detail: "La unidad está en uso en recetas")) {
            try data.deleteUnit(id: unit.id, ctx: ctx)
        }
    }

    @Test("Cambiar base_unit de unidad en uso lanza IN_USE")
    func updateUnitBaseUnitInUse() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let unit = try data.createUnit(name: "Vaso", abbreviation: "vs", baseUnit: .ml, factorToBase: "250", ctx: ctx)

        data.recipes.append(
            Recipe(
                id: "rec-1",
                name: "Licuado",
                items: [RecipeItem(kind: .ingredient, refId: "dummy", quantity: "1", unitId: unit.id)],
                yieldQuantity: "1",
                yieldUnit: .pz,
                createdAt: now,
                updatedAt: now
            )
        )

        #expect(throws: DomainError.inUse(detail: "La unidad está en uso en recetas")) {
            try data.updateUnit(id: unit.id, baseUnit: .g, ctx: ctx)
        }

        // Pero cambiar factor_to_base sí está permitido
        let updated = try data.updateUnit(id: unit.id, factorToBase: "300", ctx: ctx)
        #expect(updated.factorToBase == "300")
    }
}

// MARK: - Pruebas de Ingredientes

@Suite("Reglas del Catálogo - Ingredientes")
struct IngredientRulesTests {
    private let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    @Test("CRUD de ingrediente")
    func crudIngredient() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "ing")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let created = try data.createIngredient(
            name: "Harina de trigo",
            baseUnit: .g,
            group: "Secos",
            notes: "Todo uso",
            conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "125")],
            ctx: ctx
        )
        #expect(created.id == "ing-1")
        #expect(created.name == "Harina de trigo")
        #expect(created.baseUnit == .g)
        #expect(created.group == "Secos")
        #expect(created.conversions.count == 1)
        #expect(created.conversions[0].unitId == "sys.tz")
        #expect(created.conversions[0].quantityInBase == "125")

        // Consulta activa
        let activeList = data.activeIngredients(now: now)
        #expect(activeList.count == 1)
        #expect(activeList[0].name == "Harina de trigo")
        #expect(activeList[0].conversions[0].unitName == "taza")

        // Editar
        let t1 = now.addingTimeInterval(3600)
        let ctx1 = MutationContext(now: t1, newId: { gen.next() })
        let patched = try data.updateIngredient(
            id: created.id,
            name: "Harina de Repostería",
            notes: "Especial para pasteles",
            ctx: ctx1
        )
        #expect(patched.name == "Harina de Repostería")
        #expect(patched.notes == "Especial para pasteles")
        #expect(patched.updatedAt == t1)

        // Borrar
        let t2 = now.addingTimeInterval(7200)
        let ctx2 = MutationContext(now: t2, newId: { gen.next() })
        try data.deleteIngredient(id: created.id, ctx: ctx2)

        #expect(data.ingredients.first { $0.id == created.id }?.deletedAt == t2)
        #expect(data.activeIngredients(now: now).isEmpty)

        #expect(throws: DomainError.notFound(detail: "Ingrediente no encontrado")) {
            try data.updateIngredient(id: created.id, name: "Otro", ctx: ctx2)
        }
        #expect(throws: DomainError.notFound(detail: "Ingrediente no encontrado")) {
            try data.deleteIngredient(id: created.id, ctx: ctx2)
        }
    }

    @Test("Nombre duplicado de ingrediente lanza DUPLICATE_NAME")
    func duplicateIngredientName() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "ing")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        try data.createIngredient(name: "Mantequilla", baseUnit: .g, ctx: ctx)

        #expect(throws: DomainError.duplicateName(detail: "Ya existe un ingrediente con ese nombre")) {
            try data.createIngredient(name: "  mantequilla  ", baseUnit: .g, ctx: ctx)
        }
    }

    @Test("Validaciones de conversiones en ingrediente")
    func ingredientConversionsValidation() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "ing")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // Unidad inexistente
        #expect(throws: DomainError.invalidReference(detail: "Unidad no encontrada: unidad_fantasma")) {
            try data.createIngredient(
                name: "Azúcar",
                baseUnit: .g,
                conversions: [IngredientConversion(unitId: "unidad_fantasma", quantityInBase: "200")],
                ctx: ctx
            )
        }

        // Unidad duplicada
        #expect(throws: DomainError.invalidReference(detail: "Unidad duplicada en conversiones: sys.tz")) {
            try data.createIngredient(
                name: "Cacao",
                baseUnit: .g,
                conversions: [
                    IngredientConversion(unitId: "sys.tz", quantityInBase: "100"),
                    IngredientConversion(unitId: "sys.tz", quantityInBase: "110")
                ],
                ctx: ctx
            )
        }

        // Cantidad <= 0
        #expect(throws: DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")) {
            try data.createIngredient(
                name: "Canela",
                baseUnit: .g,
                conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "0")],
                ctx: ctx
            )
        }
    }

    @Test("Filtros y ordenamiento en activeIngredients")
    func ingredientFiltersAndSorting() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "ing")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let items = [
            ("Azúcar Mascabado", "Secos"),
            ("Azúcar Blanca", "Secos"),
            ("Leche Condensada", "Lácteos"),
            ("Azúcar Glass", "Secos"),
            ("Crema para Batir", "Lácteos"),
        ]
        for (name, group) in items {
            try data.createIngredient(name: name, baseUnit: .g, group: group, ctx: ctx)
        }

        // Filtro por q (búsqueda parcial insensible a mayúsculas)
        let azucar = data.activeIngredients(q: "azúcar", now: now)
        #expect(azucar.count == 3)
        #expect(azucar[0].name == "Azúcar Blanca")
        #expect(azucar[1].name == "Azúcar Glass")
        #expect(azucar[2].name == "Azúcar Mascabado")

        // Filtro por grupo
        let lacteos = data.activeIngredients(group: "Lácteos", now: now)
        #expect(lacteos.count == 2)
        #expect(lacteos[0].name == "Crema para Batir")
        #expect(lacteos[1].name == "Leche Condensada")
    }

    @Test("Cambiar base_unit de ingrediente con presentaciones o recetas lanza IN_USE")
    func updateIngredientBaseUnitInUse() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Aceite de Oliva", baseUnit: .ml, ctx: ctx)
        try data.createPresentation(ingredientId: ing.id, brand: "Borges", packageQuantity: "1000", ctx: ctx)

        #expect(throws: DomainError.inUse(detail: "No se puede cambiar la unidad base de un ingrediente con presentaciones activas")) {
            try data.updateIngredient(id: ing.id, baseUnit: .g, ctx: ctx)
        }

        let ing2 = try data.createIngredient(name: "Harina de Almendras", baseUnit: .g, ctx: ctx)
        data.recipes.append(
            Recipe(
                id: "rec-macarons",
                name: "Macarons",
                items: [RecipeItem(kind: .ingredient, refId: ing2.id, quantity: "200")],
                yieldQuantity: "20",
                yieldUnit: .pz,
                createdAt: now,
                updatedAt: now
            )
        )

        #expect(throws: DomainError.inUse(detail: "El ingrediente está en uso en recetas activas")) {
            try data.updateIngredient(id: ing2.id, baseUnit: .ml, ctx: ctx)
        }
    }

    @Test("Quitar una conversión en uso en receta activa lanza IN_USE, modificarla sí se permite")
    func updateConversionInUse() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(
            name: "Harina Pastelera Especial",
            baseUnit: .g,
            conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "125")],
            ctx: ctx
        )

        data.recipes.append(
            Recipe(
                id: "rec-panque",
                name: "Panqué de Vainilla",
                items: [RecipeItem(kind: .ingredient, refId: ing.id, quantity: "2", unitId: "sys.tz")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                createdAt: now,
                updatedAt: now
            )
        )

        // Quitar la conversión de taza -> lanza IN_USE
        #expect(throws: DomainError.inUse(detail: "La conversión está en uso en recetas activas")) {
            try data.updateIngredient(id: ing.id, conversions: [], ctx: ctx)
        }

        // Modificar quantity_in_base sí está permitido
        let updated = try data.updateIngredient(
            id: ing.id,
            conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "130")],
            ctx: ctx
        )
        #expect(updated.conversions[0].quantityInBase == "130")
    }

    @Test("Resumen de marcas en ingrediente: sin marcas y con 3 marcas")
    func ingredientBrandSummaries() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // 1. Ingrediente sin marcas
        let vainilla = try data.createIngredient(name: "Vainilla", baseUnit: .ml, ctx: ctx)
        let list1 = data.activeIngredients(now: now)
        let v1 = list1.first { $0.id == vainilla.id }
        #expect(v1?.brandsCount == 0)
        #expect(v1?.currentBrand == nil)

        // 2. Ingrediente con 3 marcas
        let costco = try data.createSupplier(name: "Costco", ctx: ctx)
        let harina = try data.createIngredient(name: "Harina de fuerza", baseUnit: .g, ctx: ctx)

        // Marca 1: sin precio
        try data.createPresentation(ingredientId: harina.id, brand: "Marca Sin Precio", packageQuantity: "1000", ctx: ctx)

        // Marca 2: precio t1 (hace 2 días)
        let t1 = now.addingTimeInterval(-2 * 86400)
        let ctxT1 = MutationContext(now: t1, newId: { gen.next() })
        let p2 = try data.createPresentation(
            ingredientId: harina.id,
            brand: "Marca Antigua",
            packageQuantity: "1000",
            priceCents: 2000,
            ctx: ctxT1
        )
        _ = p2

        // Marca 3: precio t2 (hoy) con proveedor Costco
        let t2 = now
        let ctxT2 = MutationContext(now: t2, newId: { gen.next() })
        let p3 = try data.createPresentation(
            ingredientId: harina.id,
            brand: "Marca Vigente",
            supplierId: costco.id,
            packageQuantity: "1000",
            priceCents: 2350,
            ctx: ctxT2
        )

        let list2 = data.activeIngredients(now: now)
        let h = list2.first { $0.id == harina.id }
        #expect(h?.brandsCount == 3)
        #expect(h?.currentBrand?.presentationId == p3.id)
        #expect(h?.currentBrand?.brand == "Marca Vigente")
        #expect(h?.currentBrand?.supplierName == "Costco")
        #expect(h?.currentBrand?.costPerBaseUnit == "2.350000")
    }
}

// MARK: - Pruebas de Proveedores

@Suite("Reglas del Catálogo - Proveedores")
struct SupplierRulesTests {
    private let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    @Test("CRUD de proveedor y ordenamiento por nombre")
    func crudSupplier() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "sup")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let created = try data.createSupplier(name: "Walmart Supercenter", notes: "Comprar lácteos aquí", ctx: ctx)
        #expect(created.id == "sup-1")
        #expect(created.name == "Walmart Supercenter")
        #expect(created.notes == "Comprar lácteos aquí")

        // Patch
        let t1 = now.addingTimeInterval(3600)
        let ctx1 = MutationContext(now: t1, newId: { gen.next() })
        let patched = try data.updateSupplier(id: created.id, name: "Walmart Express", notes: "Sucursal cercana", ctx: ctx1)
        #expect(patched.name == "Walmart Express")
        #expect(patched.notes == "Sucursal cercana")
        #expect(patched.updatedAt == t1)

        // Lista ordenada por nombre
        try data.createSupplier(name: "Costco", ctx: ctx)
        try data.createSupplier(name: "Central de Abastos", ctx: ctx)
        let suppliers = data.activeSuppliers(now: now)
        let names = suppliers.map(\.name)
        #expect(names == ["Central de Abastos", "Costco", "Walmart Express"])

        // Borrar
        let t2 = now.addingTimeInterval(7200)
        let ctx2 = MutationContext(now: t2, newId: { gen.next() })
        try data.deleteSupplier(id: created.id, ctx: ctx2)

        #expect(data.suppliers.first { $0.id == created.id }?.deletedAt == t2)
        #expect(throws: DomainError.notFound(detail: "Proveedor no encontrado")) {
            try data.updateSupplier(id: created.id, name: "Otro", ctx: ctx2)
        }
        #expect(throws: DomainError.notFound(detail: "Proveedor no encontrado")) {
            try data.deleteSupplier(id: created.id, ctx: ctx2)
        }
    }

    @Test("Proveedor con nombre duplicado lanza DUPLICATE_NAME")
    func duplicateSupplierName() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "sup")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        try data.createSupplier(name: "La Comer", ctx: ctx)
        #expect(throws: DomainError.duplicateName(detail: "Ya existe un proveedor con ese nombre")) {
            try data.createSupplier(name: "  la comer  ", ctx: ctx)
        }
    }

    @Test("Borrar proveedor deja supplier_id en nil en sus presentaciones activas")
    func deleteSupplierSetsPresentationSupplierNull() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let sup = try data.createSupplier(name: "Sams Club", ctx: ctx)
        let ing = try data.createIngredient(name: "Queso Crema", baseUnit: .g, ctx: ctx)
        let pres = try data.createPresentation(
            ingredientId: ing.id,
            brand: "Member's Mark",
            supplierId: sup.id,
            packageQuantity: "2000",
            ctx: ctx
        )
        #expect(pres.supplierId == sup.id)

        try data.deleteSupplier(id: sup.id, ctx: ctx)

        let reloadedPres = data.presentations.first { $0.id == pres.id }
        #expect(reloadedPres?.supplierId == nil)
        #expect(reloadedPres?.updatedAt == ctx.now)
    }
}

// MARK: - Pruebas de Marcas y Precios

@Suite("Reglas del Catálogo - Marcas y Precios")
struct PresentationRulesTests {
    private let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    @Test("Crear marca con precio, cost_per_base_unit e is_current")
    func createPresentationWithPrice() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Harina Selecta", baseUnit: .g, ctx: ctx)
        let pres = try data.createPresentation(
            ingredientId: ing.id,
            brand: "Selecta",
            packageQuantity: "1000",
            priceCents: 2350,
            ctx: ctx
        )
        #expect(pres.packageQuantity == "1000")

        let list = try data.presentations(forIngredient: ing.id, now: now)
        #expect(list.count == 1)
        let item = list[0]
        #expect(item.brand == "Selecta")
        #expect(item.latestPriceCents == 2350)
        #expect(item.costPerBaseUnit == "2.350000")
        #expect(item.isCurrent == true)
        #expect(item.packageQuantity == "1000")
        #expect(item.baseUnit == .g)
    }

    @Test("Crear marca con package_unit_id convierte a la unidad base")
    func createPresentationWithUnitConversion() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Azúcar Zulka", baseUnit: .g, ctx: ctx)
        let pres = try data.createPresentation(
            ingredientId: ing.id,
            brand: "Zulka",
            packageQuantity: "1",
            packageUnitId: "sys.kg",
            ctx: ctx
        )
        #expect(pres.packageQuantity == "1000")
    }

    @Test("Historial de precios descendente y latest_price actualizado")
    func priceHistoryDescending() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Mantequilla Gloria", baseUnit: .g, ctx: ctx)
        let pres = try data.createPresentation(
            ingredientId: ing.id,
            brand: "Gloria",
            packageQuantity: "500",
            priceCents: 1000,
            ctx: ctx
        )

        let t1 = now.addingTimeInterval(300)
        let ctx1 = MutationContext(now: t1, newId: { gen.next() })
        try data.addPrice(presentationId: pres.id, priceCents: 1200, note: "Subió", ctx: ctx1)

        let t2 = now.addingTimeInterval(600)
        let ctx2 = MutationContext(now: t2, newId: { gen.next() })
        try data.addPrice(presentationId: pres.id, priceCents: 1500, note: "Subió más", ctx: ctx2)

        let list = try data.presentations(forIngredient: ing.id, now: t2)
        #expect(list[0].latestPriceCents == 1500)

        let history = try data.priceHistory(presentationId: pres.id, now: t2)
        #expect(history.count == 3)
        #expect(history[0].priceCents == 1500)
        #expect(history[1].priceCents == 1200)
        #expect(history[2].priceCents == 1000)
    }

    @Test("is_current sigue al precio más nuevo (recorded_at)")
    func isCurrentFollowsLatestRecordedAt() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")

        let t1 = now.addingTimeInterval(-10800)
        let t2 = now.addingTimeInterval(-7200)
        let t3 = now.addingTimeInterval(-3600)

        let ctx0 = MutationContext(now: now, newId: { gen.next() })
        let ing = try data.createIngredient(name: "Leche Entera", baseUnit: .ml, ctx: ctx0)

        // Marca A con precio en t1
        let ctxT1 = MutationContext(now: t1, newId: { gen.next() })
        let presA = try data.createPresentation(ingredientId: ing.id, brand: "Lala", packageQuantity: "1000", ctx: ctxT1)
        try data.addPrice(presentationId: presA.id, priceCents: 2500, recordedAt: t1, ctx: ctxT1)

        // Marca B con precio en t2 (más nuevo)
        let ctxT2 = MutationContext(now: t2, newId: { gen.next() })
        let presB = try data.createPresentation(ingredientId: ing.id, brand: "Alpura", packageQuantity: "1000", ctx: ctxT2)
        try data.addPrice(presentationId: presB.id, priceCents: 2600, recordedAt: t2, ctx: ctxT2)

        var list = try data.presentations(forIngredient: ing.id, now: now)
        let a = list.first { $0.id == presA.id }
        let b = list.first { $0.id == presB.id }
        #expect(a?.isCurrent == false)
        #expect(b?.isCurrent == true)

        // Lala recibe nuevo precio en t3
        let ctxT3 = MutationContext(now: t3, newId: { gen.next() })
        try data.addPrice(presentationId: presA.id, priceCents: 2700, recordedAt: t3, ctx: ctxT3)

        list = try data.presentations(forIngredient: ing.id, now: now)
        let a2 = list.first { $0.id == presA.id }
        let b2 = list.first { $0.id == presB.id }
        #expect(a2?.isCurrent == true)
        #expect(b2?.isCurrent == false)
    }

    @Test("Presentación sin precio nunca es vigente")
    func presentationWithoutPriceNotCurrent() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Polvo Royal", baseUnit: .g, ctx: ctx)
        _ = try data.createPresentation(ingredientId: ing.id, brand: "Royal", packageQuantity: "100", ctx: ctx)

        let list = try data.presentations(forIngredient: ing.id, now: now)
        #expect(list.count == 1)
        #expect(list[0].isCurrent == false)
        #expect(list[0].latestPriceCents == nil)
        #expect(list[0].costPerBaseUnit == nil)
    }

    @Test("Borrar presentación fijada en receta activa lanza IN_USE")
    func deletePinnedPresentationInUse() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Chocolate Amargo", baseUnit: .g, ctx: ctx)
        let pres = try data.createPresentation(ingredientId: ing.id, brand: "Turin", packageQuantity: "500", ctx: ctx)

        data.recipes.append(
            Recipe(
                id: "rec-chocolate",
                name: "Pastel Fino",
                items: [
                    RecipeItem(kind: .ingredient, refId: ing.id, quantity: "250", pinnedPresentationId: pres.id)
                ],
                yieldQuantity: "1",
                yieldUnit: .pz,
                createdAt: now,
                updatedAt: now
            )
        )

        #expect(throws: DomainError.inUse(detail: "La presentación está en uso en recetas activas")) {
            try data.deletePresentation(id: pres.id, ctx: ctx)
        }

        // Si la receta se borra, ya se puede borrar la presentación
        data.recipes[0].deletedAt = now
        try data.deletePresentation(id: pres.id, ctx: ctx)
        #expect(data.presentations.first { $0.id == pres.id }?.isActive == false)
    }

    @Test("Referencias inválidas al crear presentación")
    func presentationInvalidReferences() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Canela en Rama", baseUnit: .g, ctx: ctx)

        // Ingrediente inexistente
        #expect(throws: DomainError.invalidReference(detail: "Ingrediente no encontrado")) {
            try data.createPresentation(ingredientId: "fantasma", brand: "X", packageQuantity: "100", ctx: ctx)
        }

        // Proveedor inexistente
        #expect(throws: DomainError.invalidReference(detail: "Proveedor no encontrado")) {
            try data.createPresentation(ingredientId: ing.id, brand: "X", supplierId: "sup-fantasma", packageQuantity: "100", ctx: ctx)
        }

        // Unidad no encontrada
        #expect(throws: DomainError.invalidReference(detail: "Unidad no encontrada: unidad_fantasma")) {
            try data.createPresentation(ingredientId: ing.id, brand: "X", packageQuantity: "100", packageUnitId: "unidad_fantasma", ctx: ctx)
        }

        // Unidad no convertible (taza a gramos sin conversión en ingrediente)
        #expect(throws: DomainError.unitNotConvertible(detail: "Define cuántos g tiene 1 taza de Canela en Rama")) {
            try data.createPresentation(ingredientId: ing.id, brand: "X", packageQuantity: "1", packageUnitId: "sys.tz", ctx: ctx)
        }

        // Cantidad <= 0
        #expect(throws: DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")) {
            try data.createPresentation(ingredientId: ing.id, brand: "X", packageQuantity: "0", ctx: ctx)
        }
    }

    @Test("Editar presentación y limpiar proveedor con .some(nil)")
    func updatePresentationClearSupplier() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Nuez Picada", baseUnit: .g, ctx: ctx)
        let sup = try data.createSupplier(name: "Central de Abastos", ctx: ctx)
        let pres = try data.createPresentation(
            ingredientId: ing.id,
            brand: "Nuez de Oro",
            supplierId: sup.id,
            packageQuantity: "500",
            barcode: "1234567890",
            ctx: ctx
        )

        let t1 = now.addingTimeInterval(3600)
        let ctx1 = MutationContext(now: t1, newId: { gen.next() })
        let patched = try data.updatePresentation(
            id: pres.id,
            brand: "Nuez de Oro Gourmet",
            supplierId: .some(nil),
            packageQuantity: "600",
            ctx: ctx1
        )

        #expect(patched.brand == "Nuez de Oro Gourmet")
        #expect(patched.supplierId == nil)
        #expect(patched.packageQuantity == "600")
        #expect(patched.barcode == "1234567890") // Se preserva
    }

    @Test("Orden en listado de presentaciones: con precio más nuevo primero, sin precio al final")
    func listPresentationsOrdering() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")

        let t1 = now.addingTimeInterval(-7200)
        let t2 = now

        let ctx0 = MutationContext(now: now, newId: { gen.next() })
        let ing = try data.createIngredient(name: "Levadura Seca", baseUnit: .g, ctx: ctx0)

        // p1: con precio viejo (t1)
        let ctxT1 = MutationContext(now: t1, newId: { gen.next() })
        let p1 = try data.createPresentation(ingredientId: ing.id, brand: "Levadura A", packageQuantity: "100", ctx: ctxT1)
        try data.addPrice(presentationId: p1.id, priceCents: 50, recordedAt: t1, ctx: ctxT1)

        // p2: sin precio
        let p2 = try data.createPresentation(ingredientId: ing.id, brand: "Levadura B", packageQuantity: "100", ctx: ctx0)

        // p3: con precio nuevo (t2)
        let ctxT2 = MutationContext(now: t2, newId: { gen.next() })
        let p3 = try data.createPresentation(ingredientId: ing.id, brand: "Levadura C", packageQuantity: "100", ctx: ctxT2)
        try data.addPrice(presentationId: p3.id, priceCents: 60, recordedAt: t2, ctx: ctxT2)

        let list = try data.presentations(forIngredient: ing.id, now: now)
        #expect(list.count == 3)
        #expect(list[0].id == p3.id)
        #expect(list[1].id == p1.id)
        #expect(list[2].id == p2.id)
        #expect(list[0].isCurrent == true)
        #expect(list[1].isCurrent == false)
        #expect(list[2].isCurrent == false)
    }
}

// MARK: - Pruebas de Staleness y Precios por Actualizar

@Suite("Reglas del Catálogo - Consultas y Precios Viejos")
struct StalePresentationsTests {
    private let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    @Test("Cálculo de días de antigüedad y detección de precio viejo")
    func priceAgeDaysAndStaleness() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Canela en Polvo", baseUnit: .g, ctx: ctx)

        // 1. Precio de hace 91 días -> isStale true
        let t91 = now.addingTimeInterval(-91 * 86400)
        let ctx91 = MutationContext(now: t91, newId: { gen.next() })
        let p91 = try data.createPresentation(ingredientId: ing.id, brand: "Canela 91", packageQuantity: "100", ctx: ctx91)
        try data.addPrice(presentationId: p91.id, priceCents: 550, recordedAt: t91, ctx: ctx91)

        let list91 = try data.presentations(forIngredient: ing.id, now: now)
        let item91 = list91.first { $0.id == p91.id }
        #expect(item91?.priceAgeDays == 91)
        #expect(item91?.priceIsStale == true)

        // 2. Precio de hace 90 días -> isStale false
        let t90 = now.addingTimeInterval(-90 * 86400)
        let ctx90 = MutationContext(now: t90, newId: { gen.next() })
        let p90 = try data.createPresentation(ingredientId: ing.id, brand: "Canela 90", packageQuantity: "100", ctx: ctx90)
        try data.addPrice(presentationId: p90.id, priceCents: 550, recordedAt: t90, ctx: ctx90)

        let list90 = try data.presentations(forIngredient: ing.id, now: now)
        let item90 = list90.first { $0.id == p90.id }
        #expect(item90?.priceAgeDays == 90)
        #expect(item90?.priceIsStale == false)

        // 3. Sin precio -> ageDays nil, isStale false
        let pNoPrice = try data.createPresentation(ingredientId: ing.id, brand: "Sin Precio", packageQuantity: "100", ctx: ctx)
        let listNoPrice = try data.presentations(forIngredient: ing.id, now: now)
        let itemNoPrice = listNoPrice.first { $0.id == pNoPrice.id }
        #expect(itemNoPrice?.priceAgeDays == nil)
        #expect(itemNoPrice?.priceIsStale == false)
    }

    @Test("Precios por actualizar (/presentations/stale) con used_in_recipes y orden más vieja primero")
    func stalePresentationsQuery() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        // 1. Ingrediente Chocolate:
        // p1b (no vigente, 100 días): no usada
        // p1a (vigente, 95 días): usada en 2 recetas activas
        let ing1 = try data.createIngredient(name: "Chocolate Amargo", baseUnit: .g, ctx: ctx)

        let t100 = now.addingTimeInterval(-100 * 86400)
        let p1b = try data.createPresentation(ingredientId: ing1.id, brand: "Choco Viejo No Vigente", packageQuantity: "1000", ctx: ctx)
        try data.addPrice(presentationId: p1b.id, priceCents: 900, recordedAt: t100, ctx: ctx)

        let t95 = now.addingTimeInterval(-95 * 86400)
        let p1a = try data.createPresentation(ingredientId: ing1.id, brand: "Choco Vigente", packageQuantity: "1000", ctx: ctx)
        try data.addPrice(presentationId: p1a.id, priceCents: 1000, recordedAt: t95, ctx: ctx)

        data.recipes.append(
            Recipe(id: "rec-selva", name: "Selva Negra", items: [RecipeItem(kind: .ingredient, refId: ing1.id, quantity: "200")], yieldQuantity: "1", yieldUnit: .pz, createdAt: now, updatedAt: now)
        )
        data.recipes.append(
            Recipe(id: "rec-trufa", name: "Cupcake Trufa", items: [RecipeItem(kind: .ingredient, refId: ing1.id, quantity: "50")], yieldQuantity: "1", yieldUnit: .pz, createdAt: now, updatedAt: now)
        )

        // 2. Ingrediente Vainilla: vigente vieja (95 días), pero ninguna receta la usa
        let ing2 = try data.createIngredient(name: "Vainilla Rara", baseUnit: .ml, ctx: ctx)
        let p2 = try data.createPresentation(ingredientId: ing2.id, brand: "Vainilla Sin Uso", packageQuantity: "100", ctx: ctx)
        try data.addPrice(presentationId: p2.id, priceCents: 800, recordedAt: t95, ctx: ctx)

        // 3. Ingrediente Nuez:
        // p3b (vieja, 92 días): fijada en una receta activa
        // p3a (fresca, 10 días): vigente fresca
        let ing3 = try data.createIngredient(name: "Nuez Pecana", baseUnit: .g, ctx: ctx)

        let t92 = now.addingTimeInterval(-92 * 86400)
        let p3b = try data.createPresentation(ingredientId: ing3.id, brand: "Nuez Especial Fijada", packageQuantity: "500", ctx: ctx)
        try data.addPrice(presentationId: p3b.id, priceCents: 1500, recordedAt: t92, ctx: ctx)

        let t10 = now.addingTimeInterval(-10 * 86400)
        let p3a = try data.createPresentation(ingredientId: ing3.id, brand: "Nuez Fresca Vigente", packageQuantity: "500", ctx: ctx)
        try data.addPrice(presentationId: p3a.id, priceCents: 1600, recordedAt: t10, ctx: ctx)

        data.recipes.append(
            Recipe(id: "rec-pay", name: "Pay de Nuez", items: [RecipeItem(kind: .ingredient, refId: ing3.id, quantity: "150", pinnedPresentationId: p3b.id)], yieldQuantity: "1", yieldUnit: .pz, createdAt: now, updatedAt: now)
        )

        // Consultar precios por actualizar
        let stale = data.stalePresentations(now: now)
        #expect(stale.count == 2)

        // Orden: la más vieja primero (95 días antes de 92 días)
        #expect(stale[0].id == p1a.id)
        #expect(stale[0].brand == "Choco Vigente")
        #expect(stale[0].usedInRecipes == 2)
        #expect(stale[0].priceIsStale == true)
        #expect(stale[0].priceAgeDays == 95)

        #expect(stale[1].id == p3b.id)
        #expect(stale[1].brand == "Nuez Especial Fijada")
        #expect(stale[1].usedInRecipes == 1)
        #expect(stale[1].priceIsStale == true)
        #expect(stale[1].priceAgeDays == 92)
    }
}

// MARK: - Pruebas de Atomicidad y Efectos en Cascada

@Suite("Reglas del Catálogo - Atomicidad y Efectos en Cascada")
struct AtomicityAndIntegrityTests {
    private let now = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    @Test("Una operación que lanza deja KitchenData exactamente igual que antes")
    func operationRollbackOnFailure() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Harina", baseUnit: .g, ctx: ctx)
        let pres = try data.createPresentation(ingredientId: ing.id, brand: "Selecta", packageQuantity: "1000", ctx: ctx)
        let snap = data

        // Falla por nombre duplicado al crear unidad
        #expect(throws: DomainError.duplicateName(detail: "Ya existe una unidad con ese nombre o abreviatura")) {
            try data.createUnit(name: "taza", abbreviation: "tz_custom", baseUnit: .ml, factorToBase: "240", ctx: ctx)
        }
        #expect(data == snap)

        // Falla por valor inválido al crear ingrediente
        #expect(throws: DomainError.invalidValue(detail: "El nombre del ingrediente no puede estar vacío")) {
            try data.createIngredient(name: "   ", baseUnit: .g, ctx: ctx)
        }
        #expect(data == snap)

        // Falla por referencia inválida al crear presentación
        #expect(throws: DomainError.invalidReference(detail: "Proveedor no encontrado")) {
            try data.createPresentation(ingredientId: ing.id, brand: "Marca", supplierId: "no-existe", packageQuantity: "100", ctx: ctx)
        }
        #expect(data == snap)

        // Falla al agregar precio negativo
        #expect(throws: DomainError.invalidValue(detail: "El precio no puede ser negativo")) {
            try data.addPrice(presentationId: pres.id, priceCents: -50, ctx: ctx)
        }
        #expect(data == snap)
    }

    @Test("Borrar un ingrediente borra sus marcas en cascada")
    func deleteIngredientSoftDeletesPresentations() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing = try data.createIngredient(name: "Vainilla Liquida", baseUnit: .ml, ctx: ctx)
        let p1 = try data.createPresentation(ingredientId: ing.id, brand: "Molina", packageQuantity: "500", ctx: ctx)
        let p2 = try data.createPresentation(ingredientId: ing.id, brand: "Papantla", packageQuantity: "250", ctx: ctx)

        #expect(data.presentations.filter { $0.isActive }.count == 2)

        let t1 = now.addingTimeInterval(3600)
        let ctx1 = MutationContext(now: t1, newId: { gen.next() })
        try data.deleteIngredient(id: ing.id, ctx: ctx1)

        #expect(data.ingredients.first { $0.id == ing.id }?.isActive == false)
        let reloadedP1 = data.presentations.first { $0.id == p1.id }
        let reloadedP2 = data.presentations.first { $0.id == p2.id }
        #expect(reloadedP1?.isActive == false)
        #expect(reloadedP1?.deletedAt == t1)
        #expect(reloadedP2?.isActive == false)
        #expect(reloadedP2?.deletedAt == t1)
    }

    @Test("Borrar una marca la quita de las elecciones de las versiones de costeo activas")
    func deletePresentationRemovesFromCostVersions() throws {
        var data = KitchenData.empty(deviceId: "dev-test")
        let gen = FixedIdGenerator(prefix: "test")
        let ctx = MutationContext(now: now, newId: { gen.next() })

        let ing1 = try data.createIngredient(name: "Harina", baseUnit: .g, ctx: ctx)
        let p1 = try data.createPresentation(ingredientId: ing1.id, brand: "Selecta", packageQuantity: "1000", ctx: ctx)
        _ = try data.createPresentation(ingredientId: ing1.id, brand: "Tres Estrellas", packageQuantity: "1000", ctx: ctx)

        let ing2 = try data.createIngredient(name: "Azúcar", baseUnit: .g, ctx: ctx)
        let p3 = try data.createPresentation(ingredientId: ing2.id, brand: "Zulka", packageQuantity: "1000", ctx: ctx)

        // Crear una versión de costeo que elige p1 para ing1 y p3 para ing2
        let costVersion = CostVersion(
            id: "ver-1",
            recipeId: "rec-1",
            name: "Versión Selecta",
            choices: [
                CostVersionChoice(ingredientId: ing1.id, presentationId: p1.id),
                CostVersionChoice(ingredientId: ing2.id, presentationId: p3.id),
            ],
            createdAt: now,
            updatedAt: now
        )
        data.costVersions.append(costVersion)

        let t1 = now.addingTimeInterval(3600)
        let ctx1 = MutationContext(now: t1, newId: { gen.next() })

        // Borrar p1
        try data.deletePresentation(id: p1.id, ctx: ctx1)

        let reloadedVer = data.costVersions.first { $0.id == "ver-1" }
        #expect(reloadedVer != nil)
        #expect(reloadedVer?.updatedAt == t1)
        #expect(reloadedVer?.choices.count == 1)
        #expect(reloadedVer?.choices[0].presentationId == p3.id)
        #expect(reloadedVer?.choices[0].ingredientId == ing2.id)
    }
}
