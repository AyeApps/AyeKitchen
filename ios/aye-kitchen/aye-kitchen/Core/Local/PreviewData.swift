#if DEBUG
import Foundation
import KitchenDomain

extension KitchenData {
    /// Un negocio de ejemplo para previews: catálogo con marcas (una con precio viejo y un
    /// ingrediente sin marcas), recetas con subreceta y versión, clientes y pedidos con pagos.
    /// Usar con `LocalStore.preview()`.
    static var previewSample: KitchenData {
        let now = Date()
        func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }
        func daysAhead(_ days: Int) -> Date { now.addingTimeInterval(Double(days) * 86_400) }

        let walmart = Supplier(id: "sup-walmart", name: "Walmart", createdAt: daysAgo(60), updatedAt: daysAgo(60))
        let costco = Supplier(id: "sup-costco", name: "Costco", createdAt: daysAgo(60), updatedAt: daysAgo(60))

        let harina = Ingredient(id: "ing-harina", name: "Harina de trigo", baseUnit: .g, group: "Harinas",
                                conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "125")],
                                createdAt: daysAgo(60), updatedAt: daysAgo(60))
        let azucar = Ingredient(id: "ing-azucar", name: "Azúcar", baseUnit: .g, group: "Endulzantes",
                                conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "200")],
                                createdAt: daysAgo(60), updatedAt: daysAgo(60))
        let mantequilla = Ingredient(id: "ing-mantequilla", name: "Mantequilla", baseUnit: .g, group: "Lácteos",
                                     createdAt: daysAgo(60), updatedAt: daysAgo(60))
        let leche = Ingredient(id: "ing-leche", name: "Leche entera", baseUnit: .ml, group: "Lácteos",
                               createdAt: daysAgo(60), updatedAt: daysAgo(60))
        let huevo = Ingredient(id: "ing-huevo", name: "Huevo", baseUnit: .pz, group: "Básicos",
                               createdAt: daysAgo(60), updatedAt: daysAgo(60))
        let chispas = Ingredient(id: "ing-chispas", name: "Chispas de chocolate", baseUnit: .g, group: "Chocolates",
                                 createdAt: daysAgo(60), updatedAt: daysAgo(60))

        func brand(_ id: String, _ ingredient: String, _ name: String, _ supplier: String?, _ qty: String) -> Presentation {
            Presentation(id: id, ingredientId: ingredient, brand: name, supplierId: supplier, packageQuantity: qty,
                         createdAt: daysAgo(60), updatedAt: daysAgo(60))
        }
        func price(_ id: String, _ presentation: String, _ cents: Int, _ age: Int) -> PriceRecord {
            PriceRecord(id: id, presentationId: presentation, priceCents: cents, recordedAt: daysAgo(age),
                        createdAt: daysAgo(age), updatedAt: daysAgo(age))
        }

        let presentations = [
            brand("pres-selecta", "ing-harina", "Selecta", walmart.id, "1000"),
            brand("pres-tres", "ing-harina", "Tres Estrellas", costco.id, "1000"),
            brand("pres-zulka", "ing-azucar", "Zulka", walmart.id, "2000"),
            brand("pres-lala-barra", "ing-mantequilla", "Lala barra 90 g", walmart.id, "90"),
            brand("pres-gloria", "ing-mantequilla", "Gloria 1 kg", costco.id, "1000"),
            brand("pres-lala-leche", "ing-leche", "Lala", walmart.id, "1000"),
            brand("pres-sanjuan", "ing-huevo", "San Juan 30 pz", costco.id, "30"),
        ]
        let prices = [
            price("price-1", "pres-selecta", 2350, 2),
            price("price-2", "pres-tres", 3000, 120),
            price("price-3", "pres-zulka", 6400, 5),
            price("price-4", "pres-lala-barra", 2900, 3),
            price("price-5", "pres-gloria", 21500, 10),
            price("price-6", "pres-lala-leche", 2800, 1),
            price("price-7", "pres-sanjuan", 9900, 7),
        ]

        let betun = Recipe(id: "rec-betun", name: "Betún de mantequilla",
                           items: [RecipeItem(kind: .ingredient, refId: "ing-mantequilla", quantity: "250"),
                                   RecipeItem(kind: .ingredient, refId: "ing-azucar", quantity: "500")],
                           yieldQuantity: "800", yieldUnit: .g, createdAt: daysAgo(30), updatedAt: daysAgo(30))
        let galletas = Recipe(id: "rec-galletas", name: "Galletas con chispas",
                              items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "2", unitId: "sys.tz"),
                                      RecipeItem(kind: .ingredient, refId: "ing-azucar", quantity: "1", unitId: "sys.tz"),
                                      RecipeItem(kind: .ingredient, refId: "ing-mantequilla", quantity: "180",
                                                 pinnedPresentationId: "pres-lala-barra"),
                                      RecipeItem(kind: .ingredient, refId: "ing-huevo", quantity: "2"),
                                      RecipeItem(kind: .ingredient, refId: "ing-chispas", quantity: "150")],
                              extraCosts: [ExtraCost(name: "Bolsitas", costCents: 600)],
                              yieldQuantity: "12", yieldUnit: .pz, servings: 12,
                              createdAt: daysAgo(30), updatedAt: daysAgo(30))
        let pastel = Recipe(id: "rec-pastel", name: "Pastel de vainilla", description: "Para 16 personas",
                            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "300"),
                                    RecipeItem(kind: .ingredient, refId: "ing-leche", quantity: "1", unitId: "sys.tz"),
                                    RecipeItem(kind: .ingredient, refId: "ing-huevo", quantity: "4"),
                                    RecipeItem(kind: .recipe, refId: "rec-betun", quantity: "400")],
                            extraCosts: [ExtraCost(name: "Caja", costCents: 3500)],
                            yieldQuantity: "1", yieldUnit: .pz, servings: 16, marginPercent: 40,
                            createdAt: daysAgo(30), updatedAt: daysAgo(30))
        let version = CostVersion(id: "ver-tres", recipeId: "rec-pastel", name: "Con Tres Estrellas",
                                  choices: [CostVersionChoice(ingredientId: "ing-harina", presentationId: "pres-tres")],
                                  createdAt: daysAgo(10), updatedAt: daysAgo(10))

        let ana = Customer(id: "cus-ana", name: "Ana López", phone: "5512345678", createdAt: daysAgo(20), updatedAt: daysAgo(20))
        let luis = Customer(id: "cus-luis", name: "Luis Pérez", createdAt: daysAgo(20), updatedAt: daysAgo(20))

        let orders = [
            Order(id: "ord-1", customerId: ana.id, customerName: ana.name, customerPhone: ana.phone, deliveryAt: daysAhead(1),
                  items: [OrderItem(recipeId: "rec-pastel", recipeName: "Pastel de vainilla", quantity: "1",
                                    unitPriceCents: 16618, unitCostCentsSnapshot: 11870)],
                  payments: [Payment(id: "pay-1", amountCents: 8309, paidAt: daysAgo(1), method: "efectivo")],
                  notes: "Cumpleaños", createdAt: daysAgo(2), updatedAt: daysAgo(1)),
            Order(id: "ord-2", customerId: luis.id, customerName: luis.name, deliveryAt: daysAhead(3),
                  items: [OrderItem(recipeId: "rec-galletas", recipeName: "Galletas con chispas", soldBy: .unit, unitLabel: .pz,
                                    quantity: "4", unitPriceCents: 1300, unitCostCentsSnapshot: 1000)],
                  status: .enProceso, createdAt: daysAgo(1), updatedAt: daysAgo(1)),
            Order(id: "ord-3", customerId: ana.id, customerName: ana.name, deliveryAt: daysAgo(5),
                  items: [OrderItem(recipeId: "rec-galletas", recipeName: "Galletas con chispas", quantity: "2",
                                    unitPriceCents: 15600, unitCostCentsSnapshot: 12000)],
                  payments: [Payment(id: "pay-2", amountCents: 31200, paidAt: daysAgo(5), method: "transferencia")],
                  status: .entregado, createdAt: daysAgo(8), updatedAt: daysAgo(5)),
        ]

        return KitchenData(
            deviceId: "preview",
            ingredients: [harina, azucar, mantequilla, leche, huevo, chispas],
            suppliers: [walmart, costco],
            presentations: presentations,
            priceRecords: prices,
            recipes: [betun, galletas, pastel],
            costVersions: [version],
            customers: [ana, luis],
            orders: orders
        )
    }
}
#endif
