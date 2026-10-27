#if DEBUG
import Foundation

extension Order {
    static let mockPendingToday = Order(
        id: "order-pending-1",
        customerName: "Mariana Rojas",
        customerPhone: "5512345678",
        deliveryAt: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date.now) ?? Date.now,
        status: .inProgress,
        notes: "Sin nueces, muy importante por alergia.",
        items: [
            OrderItem(
                recipeId: "rec-1",
                recipeName: "Pastel de chocolate",
                quantity: "2",
                unitPriceCents: 45000,
                unitCostCentsSnapshot: 18000
            ),
            OrderItem(
                recipeId: "rec-2",
                recipeName: "Cupcakes de vainilla",
                quantity: "12",
                unitPriceCents: 3500,
                unitCostCentsSnapshot: 1500
            )
        ],
        payments: [
            Payment(
                id: "pay-1",
                amountCents: 50000,
                paidAt: Date.now.addingTimeInterval(-86400),
                method: "transferencia"
            )
        ],
        totalCents: 132000,
        paidCents: 50000,
        balanceCents: 82000,
        costCents: 54000,
        profitCents: 78000,
        createdAt: Date.now.addingTimeInterval(-172800),
        updatedAt: Date.now
    )

    static let mockPendingTomorrow = Order(
        id: "order-pending-2",
        customerName: "Carlos Benítez",
        customerPhone: "5587654321",
        deliveryAt: {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date.now) ?? Date.now
            return Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        }(),
        status: .pending,
        notes: "Pagar con tarjeta al recibir.",
        items: [
            OrderItem(
                recipeId: "rec-3",
                recipeName: "Tres leches tradicional",
                quantity: "1",
                unitPriceCents: 38000,
                unitCostCentsSnapshot: 14500
            )
        ],
        payments: [],
        totalCents: 38000,
        paidCents: 0,
        balanceCents: 38000,
        costCents: 14500,
        profitCents: 23500,
        createdAt: Date.now.addingTimeInterval(-3600),
        updatedAt: Date.now
    )

    static let mockOverdue = Order(
        id: "order-overdue-1",
        customerName: "Lucía Morales",
        customerPhone: "5599887766",
        deliveryAt: Calendar.current.date(byAdding: .day, value: -1, to: Date.now) ?? Date.now,
        status: .pending,
        notes: nil,
        items: [
            OrderItem(
                recipeId: "rec-4",
                recipeName: "Cheesecake de frutos rojos",
                quantity: "1",
                unitPriceCents: 52000,
                unitCostCentsSnapshot: 21000
            )
        ],
        payments: [
            Payment(
                id: "pay-overdue-1",
                amountCents: 20000,
                paidAt: Date.now.addingTimeInterval(-100000),
                method: "efectivo"
            )
        ],
        totalCents: 52000,
        paidCents: 20000,
        balanceCents: 32000,
        costCents: 21000,
        profitCents: 31000,
        createdAt: Date.now.addingTimeInterval(-200000),
        updatedAt: Date.now
    )

    static let mockDelivered = Order(
        id: "order-delivered-1",
        customerName: "Andrea Gómez",
        customerPhone: nil,
        deliveryAt: Calendar.current.date(byAdding: .day, value: -2, to: Date.now) ?? Date.now,
        status: .delivered,
        notes: "Cliente frecuente.",
        items: [
            OrderItem(
                recipeId: "rec-1",
                recipeName: "Pastel de chocolate",
                quantity: "1",
                unitPriceCents: 45000,
                unitCostCentsSnapshot: 18000
            )
        ],
        payments: [
            Payment(
                id: "pay-del-1",
                amountCents: 45000,
                paidAt: Date.now.addingTimeInterval(-172800),
                method: "tarjeta"
            )
        ],
        totalCents: 45000,
        paidCents: 45000,
        balanceCents: 0,
        costCents: 18000,
        profitCents: 27000,
        createdAt: Date.now.addingTimeInterval(-250000),
        updatedAt: Date.now
    )
}

extension RecipeListItem {
    static let mockChocolate = RecipeListItem.makeMock(
        id: "rec-1",
        name: "Pastel de chocolate",
        batchCostCents: 18000,
        complete: true
    )

    static let mockVainilla = RecipeListItem.makeMock(
        id: "rec-2",
        name: "Cupcakes de vainilla",
        batchCostCents: 1500,
        complete: true
    )

    static let mockIncomplete = RecipeListItem.makeMock(
        id: "rec-incomplete",
        name: "Pastel de zanahoria",
        batchCostCents: nil,
        complete: false
    )

    private static func makeMock(id: String, name: String, batchCostCents: Int?, complete: Bool) -> RecipeListItem {
        let json = """
        {
            "id": "\(id)",
            "name": "\(name)",
            "description": null,
            "items": [],
            "extra_costs": [],
            "yield_quantity": "1",
            "yield_unit": "pz",
            "servings": null,
            "margin_percent": 30,
            "created_at": "2026-10-01T12:00:00Z",
            "updated_at": "2026-10-01T12:00:00Z",
            "batch_cost_cents": \(batchCostCents.map { String($0) } ?? "null"),
            "complete": \(complete)
        }
        """.data(using: .utf8)!
        return try! JSONCoding.decode(RecipeListItem.self, from: json)
    }
}
#endif
