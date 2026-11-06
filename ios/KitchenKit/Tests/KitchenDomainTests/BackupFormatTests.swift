import Foundation
import Testing
@testable import KitchenDomain

@Suite("Formato del archivo y del respaldo")
struct BackupFormatTests {
    private let date = KitchenCoding.parseDate("2026-11-05T16:56:13.264Z")!

    private func sample() -> KitchenData {
        KitchenData(
            exportedAt: date,
            deviceId: "device-1",
            ingredients: [
                Ingredient(id: "ing-1", name: "Harina de trigo", baseUnit: .g, group: "Harinas",
                           conversions: [IngredientConversion(unitId: "sys.tz", quantityInBase: "125")],
                           referenceIds: ["ref-1"], createdAt: date, updatedAt: date),
            ],
            presentations: [
                Presentation(id: "pres-1", ingredientId: "ing-1", brand: "Selecta", packageQuantity: "1000",
                             createdAt: date, updatedAt: date),
            ],
            priceRecords: [
                PriceRecord(id: "price-1", presentationId: "pres-1", priceCents: 2350, recordedAt: date,
                            createdAt: date, updatedAt: date),
            ],
            recipes: [
                Recipe(id: "rec-1", name: "Galletas", items: [RecipeItem(kind: .ingredient, refId: "ing-1", quantity: "300")],
                       yieldQuantity: "12", yieldUnit: .pz, createdAt: date, updatedAt: date),
            ],
            orders: [
                Order(id: "ord-1", customerName: "Ana", deliveryAt: date,
                      items: [OrderItem(recipeId: "rec-1", recipeName: "Galletas", soldBy: .unit, unitLabel: .pz,
                                        quantity: "4", unitPriceCents: 1300, unitCostCentsSnapshot: 1000)],
                      status: .enProceso, createdAt: date, updatedAt: date),
            ]
        )
    }

    @Test("Ida y vuelta sin perder nada")
    func roundTrip() throws {
        let original = sample()
        let decoded = try KitchenCoding.decode(KitchenCoding.encode(original))
        #expect(decoded == original)
    }

    @Test("Llaves en snake_case y fechas ISO con milisegundos, como el contrato")
    func wireFormat() throws {
        let json = try #require(String(data: KitchenCoding.encode(sample()), encoding: .utf8))
        #expect(json.contains("\"schema_version\":1"))
        #expect(json.contains("\"price_records\""))
        #expect(json.contains("\"unit_cost_cents_snapshot\":1000"))
        #expect(json.contains("\"status\":\"en_proceso\""))
        #expect(json.contains("\"exported_at\":\"2026-11-05T16:56:13.264Z\""))
    }

    @Test("Lee fechas como las manda Python: sin zona y con microsegundos")
    func pythonDates() {
        #expect(KitchenCoding.parseDate("2026-11-05T16:56:13.264000") == date)
        #expect(KitchenCoding.parseDate("2026-11-05T16:56:13.264+00:00") == date)
        #expect(KitchenCoding.parseDate("basura") == nil)
    }

    @Test("Un archivo de una versión más nueva no se lee a medias")
    func newerSchema() throws {
        var data = sample()
        data.schemaVersion = KitchenData.currentSchemaVersion + 1
        let encoded = try KitchenCoding.encode(data)
        #expect(throws: KitchenCodingError.newerSchema(KitchenData.currentSchemaVersion + 1)) {
            try KitchenCoding.decode(encoded)
        }
    }

    @Test("Unidades del sistema con ids estables")
    func systemUnits() {
        #expect(SystemUnits.byId["sys.kg"]?.factorToBase == "1000")
        #expect(SystemUnits.byId["sys.fl_oz"]?.baseUnit == .ml)
        #expect(SystemUnits.all.count == 12)
    }
}
