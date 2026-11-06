import Foundation
import Testing
@testable import KitchenDomain

private final class TestIdGenerator: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()
    private let prefix: String

    init(prefix: String = "ref") {
        self.prefix = prefix
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return "\(prefix)-\(count)"
    }
}

@Suite("Reglas de Imágenes de Referencia (K4)")
struct ReferenceRulesTests {
    private let testNow = KitchenCoding.parseDate("2026-11-06T12:00:00.000Z")!
    private let laterDate = KitchenCoding.parseDate("2026-11-06T13:00:00.000Z")!

    private func makeContext(now: Date? = nil, prefix: String = "ref") -> MutationContext {
        let gen = TestIdGenerator(prefix: prefix)
        return MutationContext(now: now ?? testNow, newId: { gen.next() })
    }

    private func makeSampleImage(id: String, sha: String = "sha256-mock") -> ReferenceImage {
        ReferenceImage(
            id: id,
            contentType: "image/jpeg",
            sizeBytes: 150_000,
            width: 1200,
            height: 900,
            sha256: sha,
            createdAt: testNow,
            updatedAt: testNow
        )
    }

    private func makeDataWithOwners() -> (KitchenData, (ingId: String, presId: String, recId: String, ordId: String, expId: String)) {
        let ing = Ingredient(
            id: "ing-1",
            name: "Harina",
            baseUnit: .g,
            createdAt: testNow,
            updatedAt: testNow
        )
        let pres = Presentation(
            id: "pres-1",
            ingredientId: "ing-1",
            brand: "Selecta",
            packageQuantity: "1000",
            createdAt: testNow,
            updatedAt: testNow
        )
        let rec = Recipe(
            id: "rec-1",
            name: "Pastel",
            items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "500")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow
        )
        let ord = Order(
            id: "ord-1",
            customerName: "Juan",
            deliveryAt: testNow,
            items: [OrderItem(recipeId: "rec-1", recipeName: "Pastel", soldBy: .unit, unitLabel: .pz, quantity: "1", unitPriceCents: 2000, unitCostCentsSnapshot: 1000)],
            status: .pendiente,
            createdAt: testNow,
            updatedAt: testNow
        )
        let exp = Expense(
            id: "exp-1",
            description: "Domo para pastel",
            amountCents: 500,
            spentAt: testNow,
            createdAt: testNow,
            updatedAt: testNow
        )

        let data = KitchenData(
            exportedAt: testNow,
            deviceId: "dev-test",
            ingredients: [ing],
            presentations: [pres],
            recipes: [rec],
            orders: [ord],
            expenses: [exp]
        )
        return (data, ("ing-1", "pres-1", "rec-1", "ord-1", "exp-1"))
    }

    // MARK: - 1. Agregar a cada tipo de dueño

    @Test("Agregar referencia a cada tipo de dueño (ingrediente, marca, receta, pedido, gasto)")
    func addReferenceToEachOwnerType() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext(now: laterDate)

        let owners: [ReferenceOwner] = [
            .ingredient(ids.ingId),
            .presentation(ids.presId),
            .recipe(ids.recId),
            .order(ids.ordId),
            .expense(ids.expId)
        ]

        for (i, owner) in owners.enumerated() {
            let img = makeSampleImage(id: "ref-\(i + 1)")
            try data.addReference(img, to: owner, ctx)

            let refs = data.references(of: owner)
            #expect(refs.count == 1)
            #expect(refs.first?.id == img.id)
            #expect(refs.first?.createdAt == laterDate)
            #expect(refs.first?.updatedAt == laterDate)
            #expect(refs.first?.deletedAt == nil)
        }

        #expect(data.references.count == 5)
        #expect(data.activeReferences().count == 5)
        #expect(data.deletedReferenceIds().isEmpty)

        // Verificar que referenceIds de cada dueño tiene el ID y updatedAt se actualizó
        #expect(data.ingredients[0].referenceIds == ["ref-1"])
        #expect(data.ingredients[0].updatedAt == laterDate)

        #expect(data.presentations[0].referenceIds == ["ref-2"])
        #expect(data.presentations[0].updatedAt == laterDate)

        #expect(data.recipes[0].referenceIds == ["ref-3"])
        #expect(data.recipes[0].updatedAt == laterDate)

        #expect(data.orders[0].referenceIds == ["ref-4"])
        #expect(data.orders[0].updatedAt == laterDate)

        #expect(data.expenses[0].referenceIds == ["ref-5"])
        #expect(data.expenses[0].updatedAt == laterDate)
    }

    // MARK: - 2. Límite de 5 y atomicidad

    @Test("El sexto intento de agregar falla con invalidValue y no cambia nada")
    func maximumFiveReferencesAndAtomicity() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext()
        let owner = ReferenceOwner.recipe(ids.recId)

        // Agregar 5 referencias válidas
        for i in 1...5 {
            try data.addReference(makeSampleImage(id: "ref-\(i)"), to: owner, ctx)
        }

        #expect(data.references(of: owner).count == 5)
        #expect(data.references.count == 5)
        let snapshotBeforeSixth = data

        // Intentar agregar la sexta
        let sixth = makeSampleImage(id: "ref-6")
        #expect(throws: DomainError.invalidValue(detail: "Puedes guardar hasta 5 fotos")) {
            try data.addReference(sixth, to: owner, ctx)
        }

        // Invariante: nada cambió
        #expect(data == snapshotBeforeSixth)
        #expect(data.references(of: owner).count == 5)
        #expect(data.references.count == 5)
    }

    @Test("Id de referencia duplicado lanza invalidValue y no cambia nada")
    func duplicateImageIdFails() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext()
        let owner = ReferenceOwner.ingredient(ids.ingId)

        try data.addReference(makeSampleImage(id: "ref-dup"), to: owner, ctx)

        let snapshot = data
        let otherOwner = ReferenceOwner.recipe(ids.recId)
        #expect(throws: DomainError.invalidValue(detail: "Ya existe una referencia con ese id")) {
            try data.addReference(makeSampleImage(id: "ref-dup"), to: otherOwner, ctx)
        }
        #expect(data == snapshot)
    }

    // MARK: - 3. Quitar referencias

    @Test("Quitar referencia deja nil cuando ya no quedan en el dueño y marca deletedAt")
    func removeReferenceLeavesNilWhenEmpty() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx1 = makeContext(now: testNow)
        let owner = ReferenceOwner.order(ids.ordId)

        let img1 = makeSampleImage(id: "ref-1")
        let img2 = makeSampleImage(id: "ref-2")

        try data.addReference(img1, to: owner, ctx1)
        try data.addReference(img2, to: owner, ctx1)

        #expect(data.references(of: owner).map(\.id) == ["ref-1", "ref-2"])
        #expect(data.orders[0].referenceIds == ["ref-1", "ref-2"])

        // Quitar la primera: quedan elementos, referenceIds no es nil
        let ctx2 = makeContext(now: laterDate)
        try data.removeReference("ref-1", from: owner, ctx2)

        #expect(data.orders[0].referenceIds == ["ref-2"])
        #expect(data.orders[0].updatedAt == laterDate)
        #expect(data.references(of: owner).map(\.id) == ["ref-2"])
        #expect(data.deletedReferenceIds() == ["ref-1"])

        // Verificar deletedAt en KitchenData.references
        let deletedRef = try #require(data.references.first { $0.id == "ref-1" })
        #expect(deletedRef.deletedAt == laterDate)
        #expect(deletedRef.updatedAt == laterDate)

        // Quitar la segunda: la lista queda vacía, referenceIds debe ser nil
        try data.removeReference("ref-2", from: owner, ctx2)

        #expect(data.orders[0].referenceIds == nil)
        #expect(data.references(of: owner).isEmpty)
        #expect(data.deletedReferenceIds().sorted() == ["ref-1", "ref-2"])
        #expect(data.activeReferences().isEmpty)
    }

    @Test("Quitar referencia no perteneciente al dueño lanza notFound")
    func removeReferenceNotInOwnerThrowsNotFound() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext()
        let owner1 = ReferenceOwner.ingredient(ids.ingId)
        let owner2 = ReferenceOwner.recipe(ids.recId)

        try data.addReference(makeSampleImage(id: "ref-1"), to: owner1, ctx)

        // Intentar quitar ref-1 desde owner2
        #expect(throws: DomainError.notFound(detail: "Referencia no encontrada")) {
            try data.removeReference("ref-1", from: owner2, ctx)
        }

        // Intentar quitar id inexistente
        #expect(throws: DomainError.notFound(detail: "Referencia no encontrada")) {
            try data.removeReference("ref-404", from: owner1, ctx)
        }
    }

    // MARK: - 4. Dueño inexistente o borrado

    @Test("Operaciones con dueño inexistente lanzan notFound y consultas regresan vacío")
    func nonExistentOwner() throws {
        var (data, _) = makeDataWithOwners()
        let ctx = makeContext()
        let ghostOwner = ReferenceOwner.ingredient("ing-inexistente")

        #expect(data.references(of: ghostOwner).isEmpty)

        #expect(throws: DomainError.notFound(detail: "Ingrediente no encontrado")) {
            try data.addReference(makeSampleImage(id: "ref-ghost"), to: ghostOwner, ctx)
        }

        #expect(throws: DomainError.notFound(detail: "Ingrediente no encontrado")) {
            try data.removeReference("ref-ghost", from: ghostOwner, ctx)
        }

        #expect(throws: DomainError.notFound(detail: "Ingrediente no encontrado")) {
            try data.moveReference("ref-ghost", in: ghostOwner, toIndex: 0, ctx)
        }
    }

    @Test("Al borrar el dueño, sus referencias siguen existiendo pero ya no se consultan por ese dueño")
    func softDeletedOwnerBehavior() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext(now: testNow)
        let owner = ReferenceOwner.recipe(ids.recId)

        let img = makeSampleImage(id: "ref-cake")
        try data.addReference(img, to: owner, ctx)

        #expect(data.references(of: owner).count == 1)

        // Soft-delete del dueño
        data.recipes[0].deletedAt = laterDate

        // Ya no se consultan por ese dueño
        #expect(data.references(of: owner).isEmpty)

        // Pero la referencia sigue activa en KitchenData y en activeReferences()
        #expect(data.activeReferences().contains { $0.id == "ref-cake" })
        #expect(data.deletedReferenceIds().isEmpty)

        // Modificaciones con el dueño borrado lanzan notFound
        let ctx2 = makeContext(now: laterDate)
        #expect(throws: DomainError.notFound(detail: "Receta no encontrada")) {
            try data.addReference(makeSampleImage(id: "ref-cake-2"), to: owner, ctx2)
        }
        #expect(throws: DomainError.notFound(detail: "Receta no encontrada")) {
            try data.removeReference("ref-cake", from: owner, ctx2)
        }
        #expect(throws: DomainError.notFound(detail: "Receta no encontrada")) {
            try data.moveReference("ref-cake", in: owner, toIndex: 0, ctx2)
        }
    }

    // MARK: - 5. Reordenar referencias

    @Test("Reordenar referencias cambia el orden de referenceIds y respeta límites")
    func moveReferenceTest() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext(now: testNow)
        let owner = ReferenceOwner.expense(ids.expId)

        try data.addReference(makeSampleImage(id: "r1"), to: owner, ctx)
        try data.addReference(makeSampleImage(id: "r2"), to: owner, ctx)
        try data.addReference(makeSampleImage(id: "r3"), to: owner, ctx)

        #expect(data.references(of: owner).map(\.id) == ["r1", "r2", "r3"])

        // Mover "r1" al final (índice 2)
        let ctxLater = makeContext(now: laterDate)
        try data.moveReference("r1", in: owner, toIndex: 2, ctxLater)

        #expect(data.references(of: owner).map(\.id) == ["r2", "r3", "r1"])
        #expect(data.expenses[0].referenceIds == ["r2", "r3", "r1"])
        #expect(data.expenses[0].updatedAt == laterDate)

        // Mover "r1" de regreso al inicio (índice 0)
        try data.moveReference("r1", in: owner, toIndex: 0, ctxLater)
        #expect(data.references(of: owner).map(\.id) == ["r1", "r2", "r3"])

        // Índice fuera de rango lanza invalidValue y no cambia nada
        let snapshot = data
        #expect(throws: DomainError.invalidValue(detail: "Índice fuera de rango")) {
            try data.moveReference("r1", in: owner, toIndex: 3, ctxLater)
        }
        #expect(throws: DomainError.invalidValue(detail: "Índice fuera de rango")) {
            try data.moveReference("r1", in: owner, toIndex: -1, ctxLater)
        }
        #expect(data == snapshot)

        // Referencia no existente en el dueño lanza notFound
        #expect(throws: DomainError.notFound(detail: "Referencia no encontrada")) {
            try data.moveReference("r-ghost", in: owner, toIndex: 0, ctxLater)
        }
    }

    // MARK: - 6. deletedReferenceIds

    @Test("deletedReferenceIds reporta exactamente las referencias marcadas con deletedAt")
    func deletedReferenceIdsReporting() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext()
        let owner = ReferenceOwner.presentation(ids.presId)

        try data.addReference(makeSampleImage(id: "p1"), to: owner, ctx)
        try data.addReference(makeSampleImage(id: "p2"), to: owner, ctx)
        try data.addReference(makeSampleImage(id: "p3"), to: owner, ctx)

        #expect(data.deletedReferenceIds().isEmpty)
        #expect(data.activeReferences().count == 3)

        try data.removeReference("p2", from: owner, ctx)

        #expect(data.deletedReferenceIds() == ["p2"])
        #expect(data.activeReferences().map(\.id).sorted() == ["p1", "p3"])
    }

    // MARK: - 7. Ida y vuelta por KitchenCoding

    @Test("Ida y vuelta por KitchenCoding con referencias")
    func roundTripCodingWithReferences() throws {
        var (data, ids) = makeDataWithOwners()
        let ctx = makeContext()

        try data.addReference(makeSampleImage(id: "ref-ing"), to: .ingredient(ids.ingId), ctx)
        try data.addReference(makeSampleImage(id: "ref-pres"), to: .presentation(ids.presId), ctx)
        try data.addReference(makeSampleImage(id: "ref-rec"), to: .recipe(ids.recId), ctx)
        try data.addReference(makeSampleImage(id: "ref-ord"), to: .order(ids.ordId), ctx)
        try data.addReference(makeSampleImage(id: "ref-exp"), to: .expense(ids.expId), ctx)

        // Quitar una para tener tanto activas como borradas
        try data.removeReference("ref-pres", from: .presentation(ids.presId), ctx)

        let encoded = try KitchenCoding.encode(data)
        let jsonString = try #require(String(data: encoded, encoding: .utf8))

        // Validar formato snake_case esperado
        #expect(jsonString.contains("\"references\":["))
        #expect(jsonString.contains("\"reference_ids\":[\"ref-ing\"]"))
        #expect(jsonString.contains("\"content_type\":"))
        #expect(jsonString.contains("\"size_bytes\":150000"))
        #expect(jsonString.contains("\"deleted_at\":"))

        // Decodificar y verificar equivalencia exacta
        let decoded = try KitchenCoding.decode(encoded)
        #expect(decoded == data)
        #expect(decoded.references.count == 5)
        #expect(decoded.activeReferences().count == 4)
        #expect(decoded.deletedReferenceIds() == ["ref-pres"])
        #expect(decoded.references(of: .ingredient(ids.ingId)).map(\.id) == ["ref-ing"])
        #expect(decoded.references(of: .presentation(ids.presId)).isEmpty)
    }
}
