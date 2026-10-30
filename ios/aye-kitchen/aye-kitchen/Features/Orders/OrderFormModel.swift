import Foundation
import SwiftUI

/// Elemento de entrada para cada línea del pedido al crear o editar.
nonisolated struct OrderItemInput: Encodable, Sendable {
    let recipeId: String
    let quantity: String
    let unitPriceCents: Int?
}

/// Cuerpo de la petición para crear un pedido (POST /orders/).
nonisolated struct OrderCreateBody: Encodable, Sendable {
    let customerId: String?
    let customerName: String
    let customerPhone: String?
    let deliveryAt: Date
    let items: [OrderItemInput]
    let notes: String?
}

/// Cuerpo de la petición para editar un pedido (PATCH /orders/{id}).
nonisolated struct OrderUpdateBody: Encodable, Sendable {
    let customerId: String?
    let customerName: String?
    let customerPhone: String?
    let deliveryAt: Date?
    let status: OrderStatus?
    let notes: String?
    let items: [OrderItemInput]?

    enum CodingKeys: String, CodingKey {
        case customerId
        case customerName
        case customerPhone
        case deliveryAt
        case status
        case notes
        case items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(customerId, forKey: .customerId)
        try container.encodeIfPresent(customerName, forKey: .customerName)
        if let customerPhone {
            try container.encode(customerPhone, forKey: .customerPhone)
        } else {
            try container.encodeNil(forKey: .customerPhone)
        }
        try container.encodeIfPresent(deliveryAt, forKey: .deliveryAt)
        try container.encodeIfPresent(status, forKey: .status)
        if let notes {
            try container.encode(notes, forKey: .notes)
        } else {
            try container.encodeNil(forKey: .notes)
        }
        try container.encodeIfPresent(items, forKey: .items)
    }
}

/// Línea de producto en el borrador del formulario.
struct DraftOrderItem: Identifiable, Hashable {
    let id: UUID
    var recipeId: String
    var recipeName: String
    var quantity: Decimal
    var unitPriceText: String
    var suggestedPriceCents: Int?
    var costCalculationFailed: Bool

    var quantityString: String {
        NSDecimalNumber(decimal: quantity).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    init(
        id: UUID = UUID(),
        recipeId: String,
        recipeName: String,
        quantity: Decimal = 1,
        unitPriceText: String = "",
        suggestedPriceCents: Int? = nil,
        costCalculationFailed: Bool = false
    ) {
        self.id = id
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.quantity = quantity
        self.unitPriceText = unitPriceText
        self.suggestedPriceCents = suggestedPriceCents
        self.costCalculationFailed = costCalculationFailed
    }
}

/// Modelo de presentación para el formulario de nuevo o editar pedido (MVVM, Regla 5).
@Observable
final class OrderFormModel {
    let editingOrder: Order?

    var customerId: String? = nil
    var customerName: String = ""
    var customerPhone: String = ""
    var deliveryAt: Date
    var notes: String = ""
    var items: [DraftOrderItem] = []

    var isSaving = false
    var errorMessage: String?

    var isEditing: Bool {
        editingOrder != nil
    }

    var canSave: Bool {
        let hasValidCustomer = (customerId != nil) || (isEditing && !customerName.trimmingCharacters(in: .whitespaces).isEmpty)
        guard hasValidCustomer else { return false }
        guard !items.isEmpty else { return false }
        for item in items {
            guard let cents = CurrencyMath.parseCents(from: item.unitPriceText), cents >= 0 else {
                return false
            }
            guard item.quantity > 0 else { return false }
        }
        return !isSaving
    }

    init(order: Order? = nil) {
        self.editingOrder = order

        if let order {
            self.customerId = order.customerId
            self.customerName = order.customerName
            self.customerPhone = order.customerPhone ?? ""
            self.deliveryAt = order.deliveryAt
            self.notes = order.notes ?? ""
            // Al editar, conserva su precio acordado y no pide el costo de nuevo
            self.items = order.items.map { item in
                let qty = Decimal(string: item.quantity, locale: Locale(identifier: "en_US_POSIX")) ?? 1
                return DraftOrderItem(
                    recipeId: item.recipeId,
                    recipeName: item.recipeName,
                    quantity: qty,
                    unitPriceText: CurrencyMath.formatForInput(cents: item.unitPriceCents),
                    suggestedPriceCents: nil
                )
            }
        } else {
            self.customerId = nil
            // Para uno nuevo: mañana a las 4:00 pm
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date.now) ?? Date.now
            self.deliveryAt = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            self.items = []
        }
    }

    /// Selecciona un cliente del catálogo (Bloque I7b).
    func selectCustomer(_ customer: Customer) {
        self.customerId = customer.id
        self.customerName = customer.name
        self.customerPhone = customer.phone ?? ""
    }

    /// Agrega una receta seleccionada:
    /// Pide GET /recipes/{id}/cost y escribe en el campo de precio el suggested_price_cents.
    /// Si el costo falla, la línea se agrega igual con precio vacío y aviso de error.
    func addRecipe(_ recipeItem: RecipeListItem) async {
        do {
            let cost: RecipeCost = try await NetworkService.shared.request(
                .get,
                "/recipes/\(recipeItem.recipe.id)/cost"
            )

            let draft = DraftOrderItem(
                recipeId: recipeItem.recipe.id,
                recipeName: recipeItem.recipe.name,
                quantity: 1,
                unitPriceText: CurrencyMath.formatForInput(cents: cost.suggestedPriceCents),
                suggestedPriceCents: cost.suggestedPriceCents,
                costCalculationFailed: false
            )
            items.append(draft)
        } catch {
            let draft = DraftOrderItem(
                recipeId: recipeItem.recipe.id,
                recipeName: recipeItem.recipe.name,
                quantity: 1,
                unitPriceText: "",
                suggestedPriceCents: nil,
                costCalculationFailed: true
            )
            items.append(draft)
        }
    }

    /// Elimina una línea de producto.
    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Guarda el pedido (POST /orders/ o PATCH /orders/{id}).
    func save() async throws -> Order {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let payloadItems = items.compactMap { item -> OrderItemInput? in
            guard let cents = CurrencyMath.parseCents(from: item.unitPriceText) else { return nil }
            return OrderItemInput(
                recipeId: item.recipeId,
                quantity: item.quantityString,
                unitPriceCents: cents
            )
        }

        let trimmedName = customerName.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = customerPhone.trimmingCharacters(in: .whitespaces)
        let phoneValue = trimmedPhone.isEmpty ? nil : trimmedPhone
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let notesValue = trimmedNotes.isEmpty ? nil : trimmedNotes

        do {
            if let order = editingOrder {
                // Editar pedido
                let body = OrderUpdateBody(
                    customerId: customerId,
                    customerName: trimmedName,
                    customerPhone: phoneValue,
                    deliveryAt: deliveryAt,
                    status: nil,
                    notes: notesValue,
                    items: payloadItems
                )
                let updated: Order = try await NetworkService.shared.request(
                    .patch,
                    "/orders/\(order.id)",
                    body: body
                )
                return updated
            } else {
                // Crear pedido
                let body = OrderCreateBody(
                    customerId: customerId,
                    customerName: trimmedName,
                    customerPhone: phoneValue,
                    deliveryAt: deliveryAt,
                    items: payloadItems,
                    notes: notesValue
                )
                let created: Order = try await NetworkService.shared.request(
                    .post,
                    "/orders/",
                    body: body
                )
                return created
            }
        } catch {
            if let apiError = error as? APIError {
                if apiError.code == "PAYMENT_EXCEEDS_BALANCE" {
                    errorMessage = "Con este cambio el total quedaría por debajo de lo que ya te pagaron."
                } else if apiError.code == "INVALID_REFERENCE" {
                    errorMessage = "Una de las recetas ya no existe."
                } else {
                    errorMessage = apiError.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
}
