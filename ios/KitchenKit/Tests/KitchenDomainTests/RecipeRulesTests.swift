import Foundation
import Testing
@testable import KitchenDomain

@Suite("Reglas y consultas de recetas y versiones de costeo (K2b)")
struct RecipeRulesTests {
    private let fixedNow = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    private final class IdGenerator: @unchecked Sendable {
        private var counter: Int
        private let lock = NSLock()

        init(start: Int = 1) {
            self.counter = start
        }

        func next() -> String {
            lock.lock()
            defer { lock.unlock() }
            let id = "id-\(counter)"
            counter += 1
            return id
        }
    }

    private func makeContext(startId: Int = 1) -> MutationContext {
        let generator = IdGenerator(start: startId)
        return MutationContext(
            now: fixedNow,
            newId: { generator.next() }
        )
    }

    private func makeTestData() -> KitchenData {
        let harina = Ingredient(
            id: "ing-harina",
            name: "Harina de trigo",
            baseUnit: .g,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let azucar = Ingredient(
            id: "ing-azucar",
            name: "Azúcar",
            baseUnit: .g,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let selecta = Presentation(
            id: "pres-selecta",
            ingredientId: harina.id,
            brand: "Selecta",
            packageQuantity: "1000",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let tresEstrellas = Presentation(
            id: "pres-tres",
            ingredientId: harina.id,
            brand: "Tres Estrellas",
            packageQuantity: "1000",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let zulka = Presentation(
            id: "pres-zulka",
            ingredientId: azucar.id,
            brand: "Zulka",
            packageQuantity: "1000",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let prSelecta = PriceRecord(
            id: "pr-selecta",
            presentationId: selecta.id,
            priceCents: 2350,
            recordedAt: fixedNow,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let prTres = PriceRecord(
            id: "pr-tres",
            presentationId: tresEstrellas.id,
            priceCents: 3000,
            recordedAt: fixedNow,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let prZulka = PriceRecord(
            id: "pr-zulka",
            presentationId: zulka.id,
            priceCents: 2800,
            recordedAt: fixedNow,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )

        return KitchenData(
            deviceId: "dev-test",
            ingredients: [harina, azucar],
            presentations: [selecta, tresEstrellas, zulka],
            priceRecords: [prSelecta, prTres, prZulka]
        )
    }

    // MARK: - 1. Recipe CRUD

    @Test("CRUD de recetas: crear subreceta, receta consumidora, listar, editar y borrar")
    func testRecipeCRUD() throws {
        var data = makeTestData()
        let ctx = makeContext(startId: 100)

        // 1. Crear subreceta: Bizcocho esponjoso
        let bizcocho = try data.createRecipe(
            name: "Bizcocho esponjoso",
            description: "Base para pasteles",
            items: [
                RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "400")
            ],
            extraCosts: [
                ExtraCost(name: "Gas", costCents: 50)
            ],
            yieldQuantity: "500",
            yieldUnit: .g,
            ctx: ctx
        )
        #expect(bizcocho.name == "Bizcocho esponjoso")
        #expect(bizcocho.yieldQuantity == "500")
        #expect(bizcocho.yieldUnit == .g)
        #expect(bizcocho.items.count == 1)
        #expect(bizcocho.extraCosts.count == 1)

        // 2. Crear receta principal con la subreceta: Pastel decorado
        let pastel = try data.createRecipe(
            name: "Pastel decorado",
            description: "Pastel con betún",
            items: [
                RecipeItem(kind: .recipe, refId: bizcocho.id, quantity: "500")
            ],
            extraCosts: [
                ExtraCost(name: "Caja", costCents: 100)
            ],
            yieldQuantity: "1",
            yieldUnit: .pz,
            servings: 10,
            marginPercent: 25,
            ctx: ctx
        )
        #expect(pastel.name == "Pastel decorado")
        #expect(pastel.servings == 10)
        #expect(pastel.marginPercent == 25)

        // 3. Buscar por id
        let found = data.recipe(id: pastel.id)
        #expect(found?.name == "Pastel decorado")

        // 4. Listar recetas con búsqueda q="pastel"
        let list = data.listRecipes(query: "pastel", now: fixedNow)
        #expect(list.count == 1)
        #expect(list[0].id == pastel.id)
        #expect(list[0].batchCostCents != nil)
        #expect(list[0].complete == true)
        #expect(list[0].items[0].refName == "Bizcocho esponjoso")

        // 5. Editar receta
        let updated = try data.updateRecipe(
            id: pastel.id,
            name: "Pastel super decorado",
            extraCosts: [
                ExtraCost(name: "Caja grande", costCents: 150)
            ],
            servings: 12,
            ctx: ctx
        )
        #expect(updated.name == "Pastel super decorado")
        #expect(updated.servings == 12)
        #expect(updated.extraCosts.count == 1)
        #expect(updated.extraCosts[0].name == "Caja grande")

        // 6. Borrar receta principal
        try data.deleteRecipe(id: pastel.id, ctx: ctx)
        #expect(data.recipe(id: pastel.id) == nil)
        #expect(data.listRecipes(query: "pastel", now: fixedNow).isEmpty)

        // Intentar leer o editar la receta borrada lanza notFound
        #expect(throws: DomainError.notFound(detail: "Receta no encontrada")) {
            try data.updateRecipe(id: pastel.id, name: "Intento", ctx: ctx)
        }
        #expect(throws: DomainError.notFound(detail: "Receta no encontrada")) {
            try data.deleteRecipe(id: pastel.id, ctx: ctx)
        }
    }

    // MARK: - 2. Nombre duplicado

    @Test("Nombre duplicado (case-insensitive) y vacío")
    func testDuplicateAndEmptyName() throws {
        var data = makeTestData()
        let ctx = makeContext()

        try data.createRecipe(
            name: "Pay de Limón",
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // Mismo nombre en minúsculas lanza duplicateName
        #expect(throws: DomainError.duplicateName(detail: "Ya existe una receta con ese nombre")) {
            try data.createRecipe(
                name: "pay de limón",
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        // Nombre solo con espacios lanza invalidValue
        #expect(throws: DomainError.invalidValue(detail: "El nombre no puede estar vacío")) {
            try data.createRecipe(
                name: "   \n\t  ",
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        let otra = try data.createRecipe(
            name: "Otra receta",
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // Editar con nombre duplicado
        #expect(throws: DomainError.duplicateName(detail: "Ya existe una receta con ese nombre")) {
            try data.updateRecipe(id: otra.id, name: "PAY DE LIMÓN", ctx: ctx)
        }
    }

    // MARK: - 3. Ciclos directo e indirecto

    @Test("Ciclo directo e indirecto en recetas")
    func testRecipeCycles() throws {
        var data = makeTestData()
        let ctx = makeContext()

        let recA = try data.createRecipe(
            name: "Receta A",
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )

        // 1. Ciclo directo: A intenta usarse a sí misma
        #expect(throws: DomainError.recipeCycle(detail: "La receta se usaría a sí misma directa o indirectamente")) {
            try data.updateRecipe(
                id: recA.id,
                items: [RecipeItem(kind: .recipe, refId: recA.id, quantity: "10")],
                ctx: ctx
            )
        }

        // B usa A (B -> A)
        let recB = try data.createRecipe(
            name: "Receta B",
            items: [RecipeItem(kind: .recipe, refId: recA.id, quantity: "10")],
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )

        // 2. Ciclo indirecto: A intenta usar B (A -> B -> A)
        #expect(throws: DomainError.recipeCycle(detail: "La receta se usaría a sí misma directa o indirectamente")) {
            try data.updateRecipe(
                id: recA.id,
                items: [RecipeItem(kind: .recipe, refId: recB.id, quantity: "10")],
                ctx: ctx
            )
        }

        // C usa B (C -> B -> A)
        let recC = try data.createRecipe(
            name: "Receta C",
            items: [RecipeItem(kind: .recipe, refId: recB.id, quantity: "10")],
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )

        // Ciclo indirecto más largo: A intenta usar C (A -> C -> B -> A)
        #expect(throws: DomainError.recipeCycle(detail: "La receta se usaría a sí misma directa o indirectamente")) {
            try data.updateRecipe(
                id: recA.id,
                items: [RecipeItem(kind: .recipe, refId: recC.id, quantity: "10")],
                ctx: ctx
            )
        }
    }

    // MARK: - 4. Cadena de 11 niveles (recipeTooDeep)

    @Test("Profundidad máxima de 10 niveles y rechazo de nivel 11")
    func testRecipeTooDeep11Levels() throws {
        var data = makeTestData()
        let ctx = makeContext()

        // Construir cadena de 10 niveles permitida: Nivel 10 -> Nivel 9 -> ... -> Nivel 1
        var createdIds: [String] = []
        var prevId: String? = nil

        for i in 1...10 {
            var items: [RecipeItem] = []
            if let p = prevId {
                items.append(RecipeItem(kind: .recipe, refId: p, quantity: "10"))
            }
            let r = try data.createRecipe(
                name: "Nivel \(i)",
                items: items,
                yieldQuantity: "100",
                yieldUnit: .g,
                ctx: ctx
            )
            prevId = r.id
            createdIds.append(r.id)
        }

        let leafId = createdIds[0] // Nivel 1 (hoja)
        let rootId = createdIds[9] // Nivel 10 (raíz)

        // 1. Agregar Nivel 11 encima de la raíz lanza recipeTooDeep
        #expect(throws: DomainError.recipeTooDeep(detail: "La receta excede la profundidad máxima permitida de 10 niveles")) {
            try data.createRecipe(
                name: "Nivel 11 Encima de Raíz",
                items: [RecipeItem(kind: .recipe, refId: rootId, quantity: "10")],
                yieldQuantity: "100",
                yieldUnit: .g,
                ctx: ctx
            )
        }

        // 2. Hacer que una receta existente sin subrecetas use la raíz lanza recipeTooDeep
        let aislada = try data.createRecipe(
            name: "Receta Aislada",
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )
        #expect(throws: DomainError.recipeTooDeep(detail: "La receta excede la profundidad máxima permitida de 10 niveles")) {
            try data.updateRecipe(
                id: aislada.id,
                items: [RecipeItem(kind: .recipe, refId: rootId, quantity: "10")],
                ctx: ctx
            )
        }

        // 3. Agregar subreceta bajo la hoja lanza recipeTooDeep
        let subFondo = try data.createRecipe(
            name: "Subreceta Fondo",
            yieldQuantity: "50",
            yieldUnit: .g,
            ctx: ctx
        )
        #expect(throws: DomainError.recipeTooDeep(detail: "La receta excede la profundidad máxima permitida de 10 niveles")) {
            try data.updateRecipe(
                id: leafId,
                items: [RecipeItem(kind: .recipe, refId: subFondo.id, quantity: "10")],
                ctx: ctx
            )
        }
    }

    // MARK: - 5. No se puede borrar si está en uso (inUse)

    @Test("Borrar receta usada como subreceta lanza IN_USE")
    func testRecipeInUseCannotDelete() throws {
        var data = makeTestData()
        let ctx = makeContext()

        let base = try data.createRecipe(
            name: "Receta Base",
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )

        try data.createRecipe(
            name: "Receta Consumidora",
            items: [RecipeItem(kind: .recipe, refId: base.id, quantity: "10")],
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )

        #expect(throws: DomainError.inUse(detail: "La receta está en uso como subreceta en recetas activas")) {
            try data.deleteRecipe(id: base.id, ctx: ctx)
        }
    }

    // MARK: - 6. Validaciones de items y referencias

    @Test("Validaciones de líneas de receta y referencias inválidas")
    func testRecipeItemValidations() throws {
        var data = makeTestData()
        let ctx = makeContext()

        // 1. Ingrediente no encontrado
        #expect(throws: DomainError.invalidReference(detail: "Ingrediente no encontrado: no-existe")) {
            try data.createRecipe(
                name: "R1",
                items: [RecipeItem(kind: .ingredient, refId: "no-existe", quantity: "100")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        // 2. Subreceta no encontrada
        #expect(throws: DomainError.invalidReference(detail: "Receta no encontrada: no-existe")) {
            try data.createRecipe(
                name: "R2",
                items: [RecipeItem(kind: .recipe, refId: "no-existe", quantity: "100")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        // 3. pinned_presentation_id solo en ingredientes
        let sub = try data.createRecipe(name: "Sub", yieldQuantity: "1", yieldUnit: .pz, ctx: ctx)
        #expect(throws: DomainError.invalidReference(detail: "pinned_presentation_id solo se permite en líneas de ingrediente")) {
            try data.createRecipe(
                name: "R3",
                items: [RecipeItem(kind: .recipe, refId: sub.id, quantity: "1", pinnedPresentationId: "pres-selecta")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        // 4. Presentación de otro ingrediente (Zulka es de Azúcar, no de Harina)
        #expect(throws: DomainError.invalidReference(detail: "La presentación no pertenece a este ingrediente o no existe")) {
            try data.createRecipe(
                name: "R4",
                items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "100", pinnedPresentationId: "pres-zulka")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        // 5. Presentación inexistente
        #expect(throws: DomainError.invalidReference(detail: "Presentación fijada no encontrada")) {
            try data.createRecipe(
                name: "R5",
                items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "100", pinnedPresentationId: "pres-inexistente")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        // 6. Cantidad <= 0
        #expect(throws: DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")) {
            try data.createRecipe(
                name: "R6",
                items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "0")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }

        // 7. Rendimiento <= 0
        #expect(throws: DomainError.invalidReference(detail: "La cantidad de rendimiento debe ser mayor que cero")) {
            try data.createRecipe(
                name: "R7",
                items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "100")],
                yieldQuantity: "0",
                yieldUnit: .pz,
                ctx: ctx
            )
        }
    }

    // MARK: - 7. Unidad no convertible

    @Test("Unidad no convertible lanza UNIT_NOT_CONVERTIBLE")
    func testRecipeUnitNotConvertible() throws {
        var data = makeTestData()
        let ctx = makeContext()

        // Taza (ml) con Harina (g) sin conversión propia
        #expect(throws: DomainError.unitNotConvertible(detail: "Define cuántos g tiene 1 taza de Harina de trigo")) {
            try data.createRecipe(
                name: "Receta taza no convertible",
                items: [
                    RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "2", unitId: "sys.tz")
                ],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }
    }

    // MARK: - 8. Usables como subreceta (usable-as-subrecipe)

    @Test("Recetas usables como subreceta excluyen ciclos y ancestros")
    func testUsableAsSubrecipe() throws {
        var data = makeTestData()
        let ctx = makeContext()

        // Estructura: A (base), B -> A, C -> B, D independiente
        let recA = try data.createRecipe(name: "Receta A", yieldQuantity: "100", yieldUnit: .g, ctx: ctx)
        let recB = try data.createRecipe(
            name: "Receta B",
            items: [RecipeItem(kind: .recipe, refId: recA.id, quantity: "10")],
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )
        let recC = try data.createRecipe(
            name: "Receta C",
            items: [RecipeItem(kind: .recipe, refId: recB.id, quantity: "10")],
            yieldQuantity: "100",
            yieldUnit: .g,
            ctx: ctx
        )
        let recD = try data.createRecipe(name: "Receta D", yieldQuantity: "100", yieldUnit: .g, ctx: ctx)

        // Para A: excluye a A, y a sus ancestros B y C. Solo incluye D.
        let usableA = try data.usableSubrecipes(for: recA.id)
        let usableAIds = usableA.map { $0.id }
        #expect(usableAIds.contains(recD.id))
        #expect(!usableAIds.contains(recA.id))
        #expect(!usableAIds.contains(recB.id))
        #expect(!usableAIds.contains(recC.id))

        // Para D: puede usar A, B y C
        let usableD = try data.usableSubrecipes(for: recD.id)
        let usableDIds = usableD.map { $0.id }
        #expect(!usableDIds.contains(recD.id))
        #expect(usableDIds.contains(recA.id))
        #expect(usableDIds.contains(recB.id))
        #expect(usableDIds.contains(recC.id))
    }

    // MARK: - 9. Listar recetas con receta que falla en costeo

    @Test("listRecipes maneja receta con costeo fallido mostrando costo nulo y complete falso")
    func testListRecipesWithFailingCostRecipe() throws {
        var data = makeTestData()
        let ctx = makeContext()

        // 1. Receta válida
        let recOk = try data.createRecipe(
            name: "Galletas Válidas",
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "100")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // 2. Insertar directamente receta rota en datos (unidad no convertible)
        let recRota = Recipe(
            id: "rec-rota",
            name: "Receta Rota Conversión",
            items: [
                RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "2", unitId: "sys.tz")
            ],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        data.recipes.append(recRota)

        // 3. listRecipes no lanza: la rota sale con batchCostCents = nil y complete = false
        let list = data.listRecipes(now: fixedNow)
        let map = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })

        #expect(map[recOk.id]?.batchCostCents != nil)
        #expect(map[recOk.id]?.complete == true)

        #expect(map[recRota.id]?.batchCostCents == nil)
        #expect(map[recRota.id]?.complete == false)
    }

    // MARK: - 10. Conservar nombres de ingredientes borrados en listRecipes

    @Test("listRecipes conserva refName incluso para ingredientes soft-deleted")
    func testListRecipesPreservesDeletedIngredientName() throws {
        var data = makeTestData()
        let ctx = makeContext()

        let rec = try data.createRecipe(
            name: "Galletas de Vainilla",
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "100")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // Borrar lógicamente el ingrediente
        let ingIdx = data.ingredients.firstIndex(where: { $0.id == "ing-harina" })!
        data.ingredients[ingIdx].deletedAt = fixedNow

        let list = data.listRecipes(now: fixedNow)
        let item = list.first { $0.id == rec.id }
        #expect(item?.items[0].refName == "Harina de trigo")
    }

    // MARK: - 11. Versiones de Costeo: CRUD y Validaciones

    @Test("CRUD y validaciones de versiones de costeo")
    func testCostVersionCRUDAndValidations() throws {
        var data = makeTestData()
        let ctx = makeContext(startId: 200)

        let rec = try data.createRecipe(
            name: "Pastel simple",
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "300")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // 1. Nombre solo con espacios
        #expect(throws: DomainError.invalidValue(detail: "El nombre no puede estar vacío")) {
            try data.createCostVersion(recipeId: rec.id, name: "   ", ctx: ctx)
        }

        // 2. Nombre 'Base' reservado
        for invalidName in ["Base", "base", " BASE "] {
            #expect(throws: DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")) {
                try data.createCostVersion(recipeId: rec.id, name: invalidName, ctx: ctx)
            }
        }

        // 3. Crear versión válida
        let v1 = try data.createCostVersion(
            recipeId: rec.id,
            name: "Con Tres Estrellas",
            choices: [CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-tres")],
            ctx: ctx
        )
        #expect(v1.name == "Con Tres Estrellas")
        #expect(v1.choices.count == 1)

        // 4. Nombre repetido en la misma receta
        #expect(throws: DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")) {
            try data.createCostVersion(recipeId: rec.id, name: "con tres estrellas", ctx: ctx)
        }

        // 5. Listar versiones
        let versions = try data.costVersions(for: rec.id)
        #expect(versions.count == 1)
        #expect(versions[0].id == v1.id)
        #expect(versions[0].choices[0].ingredientName == "Harina de trigo")
        #expect(versions[0].choices[0].brand == "Tres Estrellas")

        // 6. Crear segunda versión
        let v2 = try data.createCostVersion(
            recipeId: rec.id,
            name: "Con Selecta",
            choices: [CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-selecta")],
            ctx: ctx
        )

        // 7. Intentar renombrar v2 al nombre de v1
        #expect(throws: DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")) {
            try data.updateCostVersion(recipeId: rec.id, versionId: v2.id, name: "CON TRES ESTRELLAS", ctx: ctx)
        }

        // 8. Intentar renombrar v2 a Base
        #expect(throws: DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")) {
            try data.updateCostVersion(recipeId: rec.id, versionId: v2.id, name: "Base", ctx: ctx)
        }

        // 9. Renombrar v2 válidamente
        let v2Updated = try data.updateCostVersion(recipeId: rec.id, versionId: v2.id, name: "Con Selecta Económica", ctx: ctx)
        #expect(v2Updated.name == "Con Selecta Económica")

        // 10. Borrar v2
        try data.deleteCostVersion(recipeId: rec.id, versionId: v2.id, ctx: ctx)
        let remaining = try data.costVersions(for: rec.id)
        #expect(remaining.count == 1)
        #expect(remaining[0].id == v1.id)
    }

    @Test("Validaciones de elecciones de marca en versiones de costeo")
    func testCostVersionChoicesValidation() throws {
        var data = makeTestData()
        let ctx = makeContext()

        // Receta con solo Harina
        let rec = try data.createRecipe(
            name: "Solo Harina",
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "300")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // 1. Ingrediente no pertenece a la receta (Azúcar no está en la receta)
        #expect(throws: DomainError.invalidReference(detail: "El ingrediente no pertenece a la receta")) {
            try data.createCostVersion(
                recipeId: rec.id,
                name: "V1",
                choices: [CostVersionChoice(ingredientId: "ing-azucar", presentationId: "pres-zulka")],
                ctx: ctx
            )
        }

        // 2. Ingrediente repetido en elecciones
        #expect(throws: DomainError.invalidReference(detail: "Ingrediente repetido en las elecciones")) {
            try data.createCostVersion(
                recipeId: rec.id,
                name: "V2",
                choices: [
                    CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-selecta"),
                    CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-tres")
                ],
                ctx: ctx
            )
        }

        // 3. Marca de otro ingrediente (Zulka es de Azúcar, no de Harina)
        #expect(throws: DomainError.invalidReference(detail: "Esa marca no es de Harina de trigo")) {
            try data.createCostVersion(
                recipeId: rec.id,
                name: "V3",
                choices: [CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-zulka")],
                ctx: ctx
            )
        }

        // 4. Presentación inexistente
        #expect(throws: DomainError.invalidReference(detail: "Presentación no encontrada")) {
            try data.createCostVersion(
                recipeId: rec.id,
                name: "V4",
                choices: [CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-fantasma")],
                ctx: ctx
            )
        }
    }

    // MARK: - 12. Editar items de receta limpia elecciones en versiones

    @Test("Al editar items de una receta se quitan de sus versiones las elecciones de ingredientes retirados")
    func testUpdateRecipeItemsRemovesChoices() throws {
        var data = makeTestData()
        let ctx = makeContext()

        // Receta con Harina y Azúcar
        let rec = try data.createRecipe(
            name: "Pastel Completo",
            items: [
                RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "300"),
                RecipeItem(kind: .ingredient, refId: "ing-azucar", quantity: "100")
            ],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        // Versión con elecciones para ambos
        try data.createCostVersion(
            recipeId: rec.id,
            name: "Versión 1",
            choices: [
                CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-tres"),
                CostVersionChoice(ingredientId: "ing-azucar", presentationId: "pres-zulka")
            ],
            ctx: ctx
        )

        let before = try data.costVersions(for: rec.id)
        #expect(before[0].choices.count == 2)

        // Actualizar receta para que solo tenga Harina
        try data.updateRecipe(
            id: rec.id,
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "300")],
            ctx: ctx
        )

        // La versión ahora solo debe conservar la elección de Harina
        let after = try data.costVersions(for: rec.id)
        #expect(after[0].choices.count == 1)
        #expect(after[0].choices[0].ingredientId == "ing-harina")
    }

    // MARK: - 13. Borrar receta borra sus versiones

    @Test("Al borrar una receta se borran lógicamente sus versiones")
    func testDeleteRecipeSoftDeletesVersions() throws {
        var data = makeTestData()
        let ctx = makeContext()

        let rec = try data.createRecipe(
            name: "Receta a borrar",
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "100")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )

        let v = try data.createCostVersion(
            recipeId: rec.id,
            name: "V1",
            ctx: ctx
        )

        // Borrar receta
        try data.deleteRecipe(id: rec.id, ctx: ctx)

        // Consultar versiones de la receta borrada lanza notFound
        #expect(throws: DomainError.notFound(detail: "Receta no encontrada")) {
            try data.costVersions(for: rec.id)
        }

        // Verificar que en el arreglo de costVersions quedó con deletedAt
        let rawVersion = data.costVersions.first { $0.id == v.id }
        #expect(rawVersion?.deletedAt != nil)
    }

    // MARK: - 14. Atomicidad: Si una operación lanza, KitchenData queda igual que antes

    @Test("Una operación que lanza deja KitchenData exactamente igual que antes")
    func testAtomicOperationsOnFailure() throws {
        var data = makeTestData()
        let ctx = makeContext()

        let originalData = data

        // 1. createRecipe falla por nombre vacío
        #expect(throws: DomainError.invalidValue(detail: "El nombre no puede estar vacío")) {
            try data.createRecipe(name: "", yieldQuantity: "1", yieldUnit: .pz, ctx: ctx)
        }
        #expect(data == originalData)

        // 2. createRecipe falla por unidad no convertible
        #expect(throws: DomainError.unitNotConvertible(detail: "Define cuántos g tiene 1 taza de Harina de trigo")) {
            try data.createRecipe(
                name: "Galleta",
                items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "1", unitId: "sys.tz")],
                yieldQuantity: "1",
                yieldUnit: .pz,
                ctx: ctx
            )
        }
        #expect(data == originalData)

        // 3. Crear una receta válida como base de comparación
        let rec = try data.createRecipe(
            name: "Receta Base",
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "100")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            ctx: ctx
        )
        let stateAfterValidRecipe = data

        // 4. updateRecipe falla por ciclo
        #expect(throws: DomainError.recipeCycle(detail: "La receta se usaría a sí misma directa o indirectamente")) {
            try data.updateRecipe(
                id: rec.id,
                items: [RecipeItem(kind: .recipe, refId: rec.id, quantity: "10")],
                ctx: ctx
            )
        }
        #expect(data == stateAfterValidRecipe)

        // 5. createCostVersion falla por nombre reservado
        #expect(throws: DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")) {
            try data.createCostVersion(recipeId: rec.id, name: "Base", ctx: ctx)
        }
        #expect(data == stateAfterValidRecipe)

        // 6. createCostVersion falla por ingrediente ajeno
        #expect(throws: DomainError.invalidReference(detail: "El ingrediente no pertenece a la receta")) {
            try data.createCostVersion(
                recipeId: rec.id,
                name: "V1",
                choices: [CostVersionChoice(ingredientId: "ing-azucar", presentationId: "pres-zulka")],
                ctx: ctx
            )
        }
        #expect(data == stateAfterValidRecipe)

        // 7. Crear versión válida y verificar falla en updateCostVersion
        let v = try data.createCostVersion(recipeId: rec.id, name: "V1", ctx: ctx)
        let stateAfterVersion = data

        #expect(throws: DomainError.duplicateName(detail: "Ya tienes una versión con ese nombre")) {
            try data.updateCostVersion(recipeId: rec.id, versionId: v.id, name: "Base", ctx: ctx)
        }
        #expect(data == stateAfterVersion)
    }
}
