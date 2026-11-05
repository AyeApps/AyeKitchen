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

@Suite("Reglas de Pedidos, Clientes, Pagos, Gastos y Resumen (K2c)")
struct OrderRulesTests {
    private let testNow = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!

    private func makeContext(prefix: String = "id") -> MutationContext {
        let gen = TestIdGenerator(prefix: prefix)
        return MutationContext(now: testNow, newId: { gen.next() })
    }

    // MARK: - Clientes

    @Test("CRUD de cliente: trim en nombre/teléfono, unicidad, edición y soft delete")
    func customerCRUD() throws {
        let ctx = makeContext(prefix: "cust")
        var data = KitchenData(deviceId: "test-dev")

        // 1. Crear con espacios en nombre y teléfono
        let created = try data.createCustomer(
            name: "  Carlos Santillana  ",
            phone: "  555-123-4567  ",
            notes: "Cliente frecuente",
            ctx: ctx
        )
        #expect(created.id == "cust-1")
        #expect(created.name == "Carlos Santillana")
        #expect(created.phone == "555-123-4567")
        #expect(created.notes == "Cliente frecuente")
        #expect(created.createdAt == testNow)
        #expect(created.updatedAt == testNow)

        // 2. Obtener por ID
        let fetched = try data.customer(id: created.id)
        #expect(fetched.id == created.id)
        #expect(fetched.name == "Carlos Santillana")

        // 3. Editar
        let updated = try data.updateCustomer(
            id: created.id,
            name: "Carlos S.",
            phone: "",
            notes: nil,
            ctx: ctx
        )
        #expect(updated.name == "Carlos S.")
        #expect(updated.phone == nil)
        #expect(updated.notes == "Cliente frecuente")

        // 4. Listar ordenado por nombre
        try data.createCustomer(name: "Ana Bertha", ctx: ctx)
        try data.createCustomer(name: "Zacarías", ctx: ctx)

        let names = data.listCustomers().map(\.name)
        #expect(names == ["Ana Bertha", "Carlos S.", "Zacarías"])

        // 5. Borrar (soft delete)
        try data.deleteCustomer(id: created.id, ctx: ctx)

        // 6. Verificar que ya no está activo
        #expect(throws: DomainError.notFound(detail: "Cliente no encontrado")) {
            try data.customer(id: created.id)
        }
        #expect(!data.listCustomers().contains { $0.id == created.id })

        // 7. ID inexistente lanza notFound
        #expect(throws: DomainError.notFound(detail: "Cliente no encontrado")) {
            try data.customer(id: "no-existe")
        }
    }

    @Test("Nombre duplicado en clientes (DUPLICATE_NAME): creación y renombrado")
    func customerDuplicateName() throws {
        let ctx = makeContext(prefix: "cust")
        var data = KitchenData(deviceId: "test-dev")

        try data.createCustomer(name: "Don Pedro", ctx: ctx)

        // Duplicado en creación (insensible a mayúsculas y espacios)
        #expect(throws: DomainError.duplicateName(detail: "Ya existe un cliente con ese nombre")) {
            try data.createCustomer(name: "  don pedro  ", ctx: ctx)
        }

        let c2 = try data.createCustomer(name: "Doña María", ctx: ctx)

        // Renombrar c2 al nombre de c1
        #expect(throws: DomainError.duplicateName(detail: "Ya existe un cliente con ese nombre")) {
            try data.updateCustomer(id: c2.id, name: "DON PEDRO", ctx: ctx)
        }

        // Renombrar a su mismo nombre sí se permite
        let same = try data.updateCustomer(id: c2.id, name: "doña maría", ctx: ctx)
        #expect(same.name == "doña maría")
    }

    @Test("Búsqueda de clientes por subcadena de nombre o teléfono")
    func customerSearch() throws {
        let ctx = makeContext(prefix: "cust")
        var data = KitchenData(deviceId: "test-dev")

        try data.createCustomer(name: "Carlos Mendoza", phone: "5551234567", ctx: ctx)
        try data.createCustomer(name: "Ana Torres", phone: "5559876543", ctx: ctx)
        try data.createCustomer(name: "Roberto Gómez", phone: "3331112233", ctx: ctx)

        #expect(data.listCustomers(query: "carlos").map(\.name) == ["Carlos Mendoza"])
        #expect(data.listCustomers(query: "TORRES").map(\.name) == ["Ana Torres"])
        #expect(data.listCustomers(query: "987").map(\.name) == ["Ana Torres"])
        #expect(data.listCustomers(query: "555").map(\.name) == ["Ana Torres", "Carlos Mendoza"])
        #expect(data.listCustomers(query: "inexistente").isEmpty)
    }

    @Test("Renombrar o cambiar teléfono actualiza pedidos activos asociados")
    func customerUpdatePropagatesToOrders() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let cust = try data.createCustomer(name: "Sofía Ruiz", phone: "5551111", ctx: ctx)
        let rec = Recipe(
            id: "rec-1",
            name: "Gelatina",
            items: [],
            extraCosts: [ExtraCost(name: "Base", costCents: 500)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        let order = try data.createOrder(
            customerId: cust.id,
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 500)],
            ctx: ctx
        )

        // Pedido borrado para confirmar que no se toca
        let delOrder = try data.createOrder(
            customerId: cust.id,
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 500)],
            ctx: ctx
        )
        try data.deleteOrder(id: delOrder.id, ctx: ctx)

        let futureNow = testNow.addingTimeInterval(3600)
        let ctxLater = MutationContext(now: futureNow)

        try data.updateCustomer(
            id: cust.id,
            name: "Sofía Ruiz de Velasco",
            phone: "5559999",
            ctx: ctxLater
        )

        let ordFetched = try data.order(id: order.id)
        #expect(ordFetched.customerName == "Sofía Ruiz de Velasco")
        #expect(ordFetched.customerPhone == "5559999")
        #expect(ordFetched.customerId == cust.id)
        #expect(ordFetched.updatedAt == futureNow)

        // El pedido borrado no se actualizó
        let delOrdRaw = data.orders.first { $0.id == delOrder.id }!
        #expect(delOrdRaw.customerName == "Sofía Ruiz")
        #expect(delOrdRaw.updatedAt == testNow)
    }

    @Test("Borrar cliente deja customerId nulo en pedidos activos sin tocar el nombre")
    func customerDeleteUnlinksOrders() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let cust = try data.createCustomer(name: "Marcos Valdés", phone: "5557777", ctx: ctx)
        let rec = Recipe(
            id: "rec-flan",
            name: "Flan Casero",
            items: [],
            extraCosts: [ExtraCost(name: "Base", costCents: 300)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        let order = try data.createOrder(
            customerId: cust.id,
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 300)],
            ctx: ctx
        )

        let futureNow = testNow.addingTimeInterval(1800)
        let ctxLater = MutationContext(now: futureNow)

        try data.deleteCustomer(id: cust.id, ctx: ctxLater)

        let ordFetched = try data.order(id: order.id)
        #expect(ordFetched.customerId == nil)
        #expect(ordFetched.customerName == "Marcos Valdés")
        #expect(ordFetched.customerPhone == "5557777")
        #expect(ordFetched.updatedAt == futureNow)
    }

    // MARK: - Pedidos

    @Test("Crear pedido sin precio toma el sugerido y guarda snapshot de costo")
    func createOrderWithoutPrice() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let harina = Ingredient(id: "ing-harina", name: "Harina Pedidos", baseUnit: .g, createdAt: testNow, updatedAt: testNow)
        let selecta = Presentation(id: "pres-selecta", ingredientId: harina.id, brand: "Selecta", packageQuantity: "1000", createdAt: testNow, updatedAt: testNow)
        let precio = PriceRecord(id: "pr-1", presentationId: selecta.id, priceCents: 2350, recordedAt: testNow, createdAt: testNow, updatedAt: testNow)

        // 300 g a 2.35 c/g = 705 costo. Margen default 40% -> 705 * 1.40 = 987
        let receta = Recipe(
            id: "rec-pastel",
            name: "Pastel Vainilla Pedido",
            items: [RecipeItem(kind: .ingredient, refId: harina.id, quantity: "300")],
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow
        )

        data.ingredients.append(harina)
        data.presentations.append(selecta)
        data.priceRecords.append(precio)
        data.recipes.append(receta)

        let order = try data.createOrder(
            customerName: "Ana Gómez",
            customerPhone: "5551234567",
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: receta.id, quantity: "2")],
            notes: "Sin nuez",
            ctx: ctx
        )

        #expect(order.customerName == "Ana Gómez")
        #expect(order.items.count == 1)
        #expect(order.items[0].recipeName == "Pastel Vainilla Pedido")
        #expect(order.items[0].unitPriceCents == 987)
        #expect(order.items[0].unitCostCentsSnapshot == 705)

        let totals = order.totals
        #expect(totals.totalCents == 1974)
        #expect(totals.costCents == 1410)
        #expect(totals.profitCents == 564)
        #expect(totals.paidCents == 0)
        #expect(totals.balanceCents == 1974)

        // Cambiar el precio del ingrediente después NO altera el snapshot del pedido
        let precioNuevo = PriceRecord(
            id: "pr-2",
            presentationId: selecta.id,
            priceCents: 5000,
            recordedAt: testNow.addingTimeInterval(3600),
            createdAt: testNow.addingTimeInterval(3600),
            updatedAt: testNow.addingTimeInterval(3600)
        )
        data.priceRecords.append(precioNuevo)

        let orderAfter = try data.order(id: order.id)
        #expect(orderAfter.items[0].unitCostCentsSnapshot == 705)
        #expect(orderAfter.totals.costCents == 1410)
        #expect(orderAfter.totals.totalCents == 1974)
    }

    @Test("B7: venta por pieza (soldBy: .unit) con snapshot y precio sugerido por unidad")
    func orderSoldByUnitLineB7() throws {
        // Ejemplo canónico de B7: receta de 12 pz, tanda de $120 de costo (12000 centavos), margen 30%
        // -> por tanda 15600, por pieza 1300; 4 pz -> total 5200, costo 4000, profit 1200
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(
            id: "rec-galletas-12",
            name: "Galletas 12 pz",
            extraCosts: [ExtraCost(name: "Insumos", costCents: 12000)],
            yieldQuantity: "12",
            yieldUnit: .pz,
            marginPercent: 30,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        let order = try data.createOrder(
            customerName: "Carlos Galletas",
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, soldBy: .unit, quantity: "4")],
            ctx: ctx
        )

        #expect(order.items.count == 1)
        let item = order.items[0]
        #expect(item.soldBy == .unit)
        #expect(item.unitLabel == .pz)
        #expect(item.unitPriceCents == 1300)
        #expect(item.unitCostCentsSnapshot == 1000)
        #expect(item.quantity == "4")

        let totals = order.totals
        #expect(totals.totalCents == 5200)
        #expect(totals.costCents == 4000)
        #expect(totals.profitCents == 1200)
        #expect(totals.paidCents == 0)
        #expect(totals.balanceCents == 5200)
    }

    @Test("Validaciones de creación de pedido: cliente, receta y cantidades")
    func orderCreateValidations() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(
            id: "rec-base",
            name: "Base",
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        // 1. Sin líneas
        #expect(throws: DomainError.invalidValue(detail: "El pedido debe tener al menos una línea")) {
            try data.createOrder(customerName: "Ana", deliveryAt: testNow, items: [], ctx: ctx)
        }

        // 2. Cantidad <= 0
        #expect(throws: DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")) {
            try data.createOrder(
                customerName: "Ana",
                deliveryAt: testNow,
                items: [OrderItemDraft(recipeId: rec.id, quantity: "0")],
                ctx: ctx
            )
        }
        #expect(throws: DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")) {
            try data.createOrder(
                customerName: "Ana",
                deliveryAt: testNow,
                items: [OrderItemDraft(recipeId: rec.id, quantity: "-1.5")],
                ctx: ctx
            )
        }

        // 3. Receta que no existe
        #expect(throws: DomainError.invalidReference(detail: "Receta no encontrada: rec-fantasma")) {
            try data.createOrder(
                customerName: "Ana",
                deliveryAt: testNow,
                items: [OrderItemDraft(recipeId: "rec-fantasma", quantity: "1")],
                ctx: ctx
            )
        }

        // 4. Cliente inexistente por ID
        #expect(throws: DomainError.invalidReference(detail: "Cliente no encontrado")) {
            try data.createOrder(
                customerId: "cust-fantasma",
                deliveryAt: testNow,
                items: [OrderItemDraft(recipeId: rec.id, quantity: "1")],
                ctx: ctx
            )
        }

        // 5. Sin cliente ni nombre
        #expect(throws: DomainError.customerRequired(detail: "Elige un cliente o escribe su nombre")) {
            try data.createOrder(
                customerId: nil,
                customerName: "   ",
                deliveryAt: testNow,
                items: [OrderItemDraft(recipeId: rec.id, quantity: "1")],
                ctx: ctx
            )
        }
    }

    @Test("Edición de pedido: conserva líneas existentes con su snapshot, label, recipeName y precio convenido")
    func orderUpdatePreservesLines() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec1 = Recipe(
            id: "rec-1",
            name: "Receta Uno",
            extraCosts: [ExtraCost(name: "Base", costCents: 400)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 0,
            createdAt: testNow,
            updatedAt: testNow
        )
        let rec2 = Recipe(
            id: "rec-2",
            name: "Receta Dos",
            extraCosts: [ExtraCost(name: "Base", costCents: 800)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 0,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec1)
        data.recipes.append(rec2)

        // Pedido con receta 1 a precio acordado de $10.00 (1000c)
        let order = try data.createOrder(
            customerName: "Carlos Pérez",
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec1.id, quantity: "1", unitPriceCents: 1000)],
            ctx: ctx
        )
        #expect(order.items[0].unitCostCentsSnapshot == 400)
        #expect(order.items[0].unitPriceCents == 1000)

        // Supongamos que los costos de rec1 suben en la receta
        data.recipes[0].extraCosts = [ExtraCost(name: "Base", costCents: 900)]

        // Al editar el pedido agregando rec2 pero sin pasar unitPrice para rec1:
        let updated = try data.updateOrder(
            id: order.id,
            items: [
                OrderItemDraft(recipeId: rec1.id, quantity: "2"), // No pasa unitPrice: debe conservar 1000 y snapshot 400
                OrderItemDraft(recipeId: rec2.id, quantity: "1")  // Línea nueva: costo 800, precio 800
            ],
            ctx: ctx
        )

        #expect(updated.items.count == 2)
        let line1 = updated.items.first { $0.recipeId == rec1.id }!
        #expect(line1.recipeName == "Receta Uno")
        #expect(line1.unitPriceCents == 1000)
        #expect(line1.unitCostCentsSnapshot == 400)
        #expect(line1.quantity == "2")

        let line2 = updated.items.first { $0.recipeId == rec2.id }!
        #expect(line2.recipeName == "Receta Dos")
        #expect(line2.unitPriceCents == 800)
        #expect(line2.unitCostCentsSnapshot == 800)
    }

    @Test("Edición de pedido: PAYMENT_EXCEEDS_BALANCE si el nuevo total queda por debajo de lo pagado")
    func orderUpdatePaymentExceedsBalance() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(
            id: "rec-1",
            name: "Panque",
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        let order = try data.createOrder(
            customerName: "Luisa",
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "2", unitPriceCents: 1000)], // total 2000
            ctx: ctx
        )

        // Registrar pago de 1500
        try data.addPayment(orderId: order.id, amountCents: 1500, ctx: ctx)

        // Intentar reducir cantidad a 1 (nuevo total 1000 < pagado 1500)
        #expect(throws: DomainError.paymentExceedsBalance(detail: "El total quedaría por debajo de lo que ya te pagaron")) {
            try data.updateOrder(
                id: order.id,
                items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 1000)],
                ctx: ctx
            )
        }
    }

    @Test("Un pedido conserva recipeName aunque la receta se borre")
    func orderPreservesRecipeNameWhenRecipeDeleted() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(
            id: "rec-especial",
            name: "Pastel Especial de Moras",
            yieldQuantity: "1",
            yieldUnit: .pz,
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        let order = try data.createOrder(
            customerName: "Mariana",
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 1500)],
            ctx: ctx
        )
        #expect(order.items[0].recipeName == "Pastel Especial de Moras")

        // Borrar receta
        data.recipes[0].deletedAt = testNow.addingTimeInterval(3600)

        // El pedido sigue leyendo recipeName sin error
        let fetchedOrder = try data.order(id: order.id)
        #expect(fetchedOrder.items[0].recipeName == "Pastel Especial de Moras")
    }

    @Test("Listado de pedidos con filtros por status, deliveryAt y customerId")
    func orderListFilters() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(id: "r1", name: "R1", yieldQuantity: "1", yieldUnit: .pz, createdAt: testNow, updatedAt: testNow)
        data.recipes.append(rec)

        let cust1 = try data.createCustomer(name: "Cliente 1", ctx: ctx)
        let cust2 = try data.createCustomer(name: "Cliente 2", ctx: ctx)

        let d1 = KitchenCoding.parseDate("2026-11-01T10:00:00.000Z")!
        let d2 = KitchenCoding.parseDate("2026-11-05T10:00:00.000Z")!
        let d3 = KitchenCoding.parseDate("2026-11-10T10:00:00.000Z")!

        let o1 = try data.createOrder(customerId: cust1.id, deliveryAt: d2, items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 100)], ctx: ctx)
        let o2 = try data.createOrder(customerId: cust2.id, deliveryAt: d1, items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 100)], ctx: ctx)
        let o3 = try data.createOrder(customerId: cust1.id, deliveryAt: d3, items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 100)], ctx: ctx)

        try data.updateOrder(id: o1.id, status: .entregado, ctx: ctx)

        // Orden deliveryAt asc
        let all = data.listOrders()
        #expect(all.map(\.id) == [o2.id, o1.id, o3.id])

        // Filtro por status
        let entregados = data.listOrders(status: .entregado)
        #expect(entregados.map(\.id) == [o1.id])

        // Filtro por cliente
        let deCust1 = data.listOrders(customerId: cust1.id)
        #expect(deCust1.map(\.id) == [o1.id, o3.id])

        // Filtro por rango
        let rango = data.listOrders(from: d1, to: d2)
        #expect(rango.map(\.id) == [o2.id, o1.id])

        // Paginado
        let page = data.listOrders(page: 1, limit: 2)
        #expect(page.items.count == 2)
        #expect(page.total == 3)
        #expect(page.pages == 2)
    }

    // MARK: - Pagos

    @Test("Pagos: agregar, validación de exceso y eliminación")
    func paymentsFlow() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(id: "r1", name: "R1", yieldQuantity: "1", yieldUnit: .pz, createdAt: testNow, updatedAt: testNow)
        data.recipes.append(rec)

        let order = try data.createOrder(
            customerName: "Beto",
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 5000)],
            ctx: ctx
        )

        // Monto <= 0
        #expect(throws: DomainError.invalidValue(detail: "El monto debe ser mayor que cero")) {
            try data.addPayment(orderId: order.id, amountCents: 0, ctx: ctx)
        }

        // Pago 1: 2000
        let p1 = try data.addPayment(orderId: order.id, amountCents: 2000, method: "efectivo", ctx: ctx)
        #expect(p1.amountCents == 2000)
        #expect(p1.method == "efectivo")

        var ord = try data.order(id: order.id)
        #expect(ord.totals.paidCents == 2000)
        #expect(ord.totals.balanceCents == 3000)

        // Intentar pagar más del saldo restante (3001 > 3000)
        #expect(throws: DomainError.paymentExceedsBalance(detail: "El pago excede el saldo pendiente")) {
            try data.addPayment(orderId: order.id, amountCents: 3001, ctx: ctx)
        }

        // Pago 2: saldo exacto 3000
        _ = try data.addPayment(orderId: order.id, amountCents: 3000, method: "transferencia", ctx: ctx)
        ord = try data.order(id: order.id)
        #expect(ord.totals.paidCents == 5000)
        #expect(ord.totals.balanceCents == 0)

        // Quitar pago 1
        try data.deletePayment(orderId: order.id, paymentId: p1.id, ctx: ctx)
        ord = try data.order(id: order.id)
        #expect(ord.totals.paidCents == 3000)
        #expect(ord.totals.balanceCents == 2000)

        // Quitar pago inexistente
        #expect(throws: DomainError.notFound(detail: "Pago no encontrado")) {
            try data.deletePayment(orderId: order.id, paymentId: "no-existe", ctx: ctx)
        }
    }

    // MARK: - Gastos

    @Test("Gastos: CRUD, validación de proveedor y filtros por categoría/fecha")
    func expensesFlow() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let supp = Supplier(id: "supp-1", name: "Central de Abastos", createdAt: testNow, updatedAt: testNow)
        data.suppliers.append(supp)

        // Validación de proveedor inexistente
        #expect(throws: DomainError.invalidReference(detail: "Proveedor no encontrado: supp-fantasma")) {
            try data.createExpense(
                description: "Insumos",
                amountCents: 1000,
                supplierId: "supp-fantasma",
                ctx: ctx
            )
        }

        let oct15 = KitchenCoding.parseDate("2026-10-15T10:00:00.000Z")!
        let nov02 = KitchenCoding.parseDate("2026-11-02T10:00:00.000Z")!

        let exp1 = try data.createExpense(
            description: "Bulto de Harina 50kg",
            amountCents: 45000,
            spentAt: oct15,
            category: "Insumos",
            supplierId: supp.id,
            ctx: ctx
        )
        #expect(exp1.amountCents == 45000)
        #expect(exp1.category == "Insumos")
        #expect(exp1.supplierId == supp.id)

        let exp2 = try data.createExpense(
            description: "Recibo de Gas",
            amountCents: 12000,
            spentAt: nov02,
            category: "Servicios",
            ctx: ctx
        )

        // Filtro por categoría
        let serv = data.listExpenses(category: "Servicios")
        #expect(serv.map(\.id) == [exp2.id])

        // Filtro por fecha (octubre)
        let octStart = KitchenCoding.parseDate("2026-10-01T00:00:00.000Z")!
        let octEnd = KitchenCoding.parseDate("2026-10-31T23:59:59.000Z")!
        let octItems = data.listExpenses(from: octStart, to: octEnd)
        #expect(octItems.map(\.id) == [exp1.id])

        // Actualizar gasto
        let updated = try data.updateExpense(
            id: exp1.id,
            description: "Bulto Harina Extra Fina",
            amountCents: 48000,
            ctx: ctx
        )
        #expect(updated.description == "Bulto Harina Extra Fina")
        #expect(updated.amountCents == 48000)

        // Borrar gasto (soft delete)
        try data.deleteExpense(id: exp1.id, ctx: ctx)
        #expect(!data.listExpenses().contains { $0.id == exp1.id })
        #expect(throws: DomainError.notFound(detail: "Gasto no encontrado")) {
            try data.expense(id: exp1.id)
        }
    }

    // MARK: - Resumen Mensual

    @Test("Resumen mensual: validaciones de rango de año y mes")
    func summaryValidation() throws {
        let data = KitchenData(deviceId: "test-dev")

        #expect(throws: DomainError.invalidValue(detail: "El año debe estar entre 2000 y 2100")) {
            try data.monthlySummary(year: 1999, month: 10)
        }
        #expect(throws: DomainError.invalidValue(detail: "El año debe estar entre 2000 y 2100")) {
            try data.monthlySummary(year: 2101, month: 10)
        }
        #expect(throws: DomainError.invalidValue(detail: "El mes debe estar entre 1 y 12")) {
            try data.monthlySummary(year: 2026, month: 0)
        }
        #expect(throws: DomainError.invalidValue(detail: "El mes debe estar entre 1 y 12")) {
            try data.monthlySummary(year: 2026, month: 13)
        }

        let empty = try data.monthlySummary(year: 2026, month: 10)
        #expect(empty.incomeCents == 0)
        #expect(empty.expensesCents == 0)
        #expect(empty.netCents == 0)
        #expect(empty.ordersDelivered == 0)
        #expect(empty.ordersPending == 0)
        #expect(empty.salesCents == 0)
        #expect(empty.estimatedProfitCents == 0)
        #expect(empty.receivableCents == 0)
    }

    @Test("Resumen mensual: ingresos, gastos y pedidos por fecha de entrega vs fecha de pago")
    func summaryIncomeAndSalesTiming() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(
            id: "rec-resumen",
            name: "Pastel Resumen",
            extraCosts: [ExtraCost(name: "Base", costCents: 20000)],
            yieldQuantity: "1",
            yieldUnit: .pz,
            marginPercent: 50, // Costo 20000, sugerido 30000
            createdAt: testNow,
            updatedAt: testNow
        )
        data.recipes.append(rec)

        // Pedido con entrega en Noviembre (total 30000, costo snapshot 20000)
        let nov15 = KitchenCoding.parseDate("2026-11-15T16:00:00.000Z")!
        let order = try data.createOrder(
            customerName: "Ana Noviembre",
            deliveryAt: nov15,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1")],
            ctx: ctx
        )

        // Pago anticipado recibido en Octubre ($100.00 = 10000c)
        let oct25 = KitchenCoding.parseDate("2026-10-25T14:00:00.000Z")!
        try data.addPayment(orderId: order.id, amountCents: 10000, paidAt: oct25, method: "transferencia", ctx: ctx)

        // Gasto en Octubre ($20.00 = 2000c)
        let oct20 = KitchenCoding.parseDate("2026-10-20T10:00:00.000Z")!
        try data.createExpense(description: "Capacillos", amountCents: 2000, spentAt: oct20, ctx: ctx)

        // 1. Resumen de Octubre
        let octSummary = try data.monthlySummary(year: 2026, month: 10)
        #expect(octSummary.incomeCents == 10000)
        #expect(octSummary.expensesCents == 2000)
        #expect(octSummary.netCents == 8000)
        #expect(octSummary.ordersDelivered == 0)
        #expect(octSummary.ordersPending == 0)
        #expect(octSummary.salesCents == 0)
        #expect(octSummary.estimatedProfitCents == 0)
        #expect(octSummary.receivableCents == 0)

        // 2. Resumen de Noviembre ANTES de entregar
        let novPre = try data.monthlySummary(year: 2026, month: 11)
        #expect(novPre.incomeCents == 0)
        #expect(novPre.ordersPending == 1)
        #expect(novPre.ordersDelivered == 0)
        #expect(novPre.salesCents == 0)
        #expect(novPre.receivableCents == 20000) // Saldo pendiente

        // 3. Entregar el pedido en Noviembre
        try data.updateOrder(id: order.id, status: .entregado, ctx: ctx)

        let novPost = try data.monthlySummary(year: 2026, month: 11)
        #expect(novPost.ordersDelivered == 1)
        #expect(novPost.ordersPending == 0)
        #expect(novPost.salesCents == 30000)
        #expect(novPost.estimatedProfitCents == 10000)
        #expect(novPost.receivableCents == 20000)
    }

    @Test("Resumen mensual: límites de mes en la timezone del workspace (America/Mexico_City)")
    func summaryTimezoneBoundary() throws {
        // La timezone es America/Mexico_City (UTC-6)
        // 23:30 del 31 de octubre de 2026 en Mexico City = 05:30 del 1 de noviembre de 2026 UTC
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev", settings: KitchenSettings(timezone: "America/Mexico_City"))

        let rec = Recipe(id: "r1", name: "R1", yieldQuantity: "1", yieldUnit: .pz, createdAt: testNow, updatedAt: testNow)
        data.recipes.append(rec)

        let nov05 = KitchenCoding.parseDate("2026-11-05T12:00:00.000Z")!
        let order = try data.createOrder(
            customerName: "Carlos Noche",
            deliveryAt: nov05,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 20000)],
            ctx: ctx
        )

        // Pago a las 05:30 UTC del 1 de nov -> 23:30 del 31 de oct local
        let boundaryPaidAt = KitchenCoding.parseDate("2026-11-01T05:30:00.000Z")!
        try data.addPayment(orderId: order.id, amountCents: 15000, paidAt: boundaryPaidAt, ctx: ctx)

        let octSummary = try data.monthlySummary(year: 2026, month: 10)
        #expect(octSummary.incomeCents == 15000)

        let novSummary = try data.monthlySummary(year: 2026, month: 11)
        #expect(novSummary.incomeCents == 0)
    }

    @Test("Resumen mensual: pedidos cancelados se excluyen de ingresos, ventas y saldo")
    func summaryCancelledOrdersExcluded() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let rec = Recipe(id: "r1", name: "R1", yieldQuantity: "1", yieldUnit: .pz, createdAt: testNow, updatedAt: testNow)
        data.recipes.append(rec)

        let nov10 = KitchenCoding.parseDate("2026-11-10T12:00:00.000Z")!
        let order = try data.createOrder(
            customerName: "Cancelado",
            deliveryAt: nov10,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 5000)],
            ctx: ctx
        )
        try data.addPayment(orderId: order.id, amountCents: 2000, paidAt: nov10, ctx: ctx)
        try data.updateOrder(id: order.id, status: .cancelado, ctx: ctx)

        let novSummary = try data.monthlySummary(year: 2026, month: 11)
        #expect(novSummary.incomeCents == 0)
        #expect(novSummary.salesCents == 0)
        #expect(novSummary.ordersDelivered == 0)
        #expect(novSummary.ordersPending == 0)
        #expect(novSummary.receivableCents == 0)
    }

    // MARK: - Invariante Transaccional

    @Test("Invariante: una operación que lanza deja KitchenData exactamente igual que antes")
    func operationsLeaveDataUnchangedOnThrow() throws {
        let ctx = MutationContext(now: testNow)
        var data = KitchenData(deviceId: "test-dev")

        let cust = try data.createCustomer(name: "Cliente Base", ctx: ctx)
        let rec = Recipe(id: "r1", name: "Receta", yieldQuantity: "1", yieldUnit: .pz, createdAt: testNow, updatedAt: testNow)
        data.recipes.append(rec)

        let order = try data.createOrder(
            customerId: cust.id,
            deliveryAt: testNow,
            items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 1000)],
            ctx: ctx
        )
        try data.addPayment(orderId: order.id, amountCents: 500, ctx: ctx)

        let snapshotBefore = data

        // 1. Fallo en createCustomer
        #expect(throws: DomainError.self) {
            try data.createCustomer(name: "Cliente Base", ctx: ctx)
        }
        #expect(data == snapshotBefore)

        // 2. Fallo en updateCustomer
        #expect(throws: DomainError.self) {
            try data.updateCustomer(id: cust.id, name: "", ctx: ctx)
        }
        #expect(data == snapshotBefore)

        // 3. Fallo en createOrder
        #expect(throws: DomainError.self) {
            try data.createOrder(customerName: "X", deliveryAt: testNow, items: [], ctx: ctx)
        }
        #expect(data == snapshotBefore)

        // 4. Fallo en updateOrder (total < pagado)
        #expect(throws: DomainError.self) {
            try data.updateOrder(
                id: order.id,
                items: [OrderItemDraft(recipeId: rec.id, quantity: "1", unitPriceCents: 100)], // 100 < 500 pagado
                ctx: ctx
            )
        }
        #expect(data == snapshotBefore)

        // 5. Fallo en addPayment (exceso de saldo)
        #expect(throws: DomainError.self) {
            try data.addPayment(orderId: order.id, amountCents: 99999, ctx: ctx)
        }
        #expect(data == snapshotBefore)

        // 6. Fallo en createExpense (proveedor no existente)
        #expect(throws: DomainError.self) {
            try data.createExpense(description: "Gasto", amountCents: 100, supplierId: "no-supp", ctx: ctx)
        }
        #expect(data == snapshotBefore)
    }
}
