import Foundation
import SwiftUI

/// Elemento de entrada para cada línea del pedido al crear o editar.
nonisolated struct OrderItemInput: Encodable, Sendable {
    let recipeId: String
    let soldBy: RemoteOrderSoldBy
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
    let status: RemoteOrderStatus?
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
    var soldBy: RemoteOrderSoldBy
    var yieldQuantity: Decimal?
    var yieldUnit: RemoteBaseUnit
    var quantityText: String
    var unitPriceText: String
    var suggestedPriceBatchCents: Int?
    var suggestedPriceUnitCents: Int?
    var costCalculationFailed: Bool

    init(
        id: UUID = UUID(),
        recipeId: String,
        recipeName: String,
        soldBy: RemoteOrderSoldBy = .batch,
        yieldQuantity: Decimal? = nil,
        yieldUnit: RemoteBaseUnit = .pz,
        quantityText: String = "1",
        unitPriceText: String = "",
        suggestedPriceBatchCents: Int? = nil,
        suggestedPriceUnitCents: Int? = nil,
        costCalculationFailed: Bool = false
    ) {
        self.id = id
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.soldBy = soldBy
        self.yieldQuantity = yieldQuantity
        self.yieldUnit = yieldUnit
        self.quantityText = quantityText
        self.unitPriceText = unitPriceText
        self.suggestedPriceBatchCents = suggestedPriceBatchCents
        self.suggestedPriceUnitCents = suggestedPriceUnitCents
        self.costCalculationFailed = costCalculationFailed
    }

    /// La receta rinde más de 1 unidad.
    var yieldsMultiple: Bool {
        guard let yield = yieldQuantity else { return false }
        return yield > 1
    }

    /// Título de la primera opción del selector de modo según yieldUnit ("Por pieza", "Por g", "Por ml").
    var unitOptionTitle: String {
        switch yieldUnit {
        case .pz:
            return "Por pieza"
        case .g:
            return "Por g"
        case .ml:
            return "Por ml"
        }
    }

    /// Etiqueta del campo de cantidad según el modo elegido.
    var quantityLabel: String {
        switch soldBy {
        case .unit:
            switch yieldUnit {
            case .pz:
                return "Piezas"
            case .g:
                return "Gramos"
            case .ml:
                return "Mililitros"
            }
        case .batch:
            return "Tandas"
        }
    }

    /// Texto "1 tanda = 12 pz" con lo que rinde la receta.
    var yieldSummary: String? {
        guard let yield = yieldQuantity else { return nil }
        let formatted = Quantity.format(DraftOrderItem.formatQuantityForInput(yield))
        return "1 tanda = \(formatted) \(yieldUnit.rawValue)"
    }

    /// Etiqueta del campo de precio según el modo elegido.
    var priceLabel: String {
        switch soldBy {
        case .unit:
            switch yieldUnit {
            case .pz:
                return "Precio por pieza"
            case .g:
                return "Precio por g"
            case .ml:
                return "Precio por ml"
            }
        case .batch:
            return "Precio por tanda"
        }
    }

    /// Precio sugerido correspondiente al modo actual.
    var currentSuggestedPriceCents: Int? {
        switch soldBy {
        case .unit:
            return suggestedPriceUnitCents
        case .batch:
            return suggestedPriceBatchCents
        }
    }

    /// Cantidad parseada con Quantity.parse; nil si no es un número > 0.
    var parsedQuantity: Decimal? {
        guard let valid = Quantity.parse(quantityText) else { return nil }
        return Decimal(string: valid, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Validez de la cantidad para guardar.
    var isQuantityValid: Bool {
        Quantity.parse(quantityText) != nil
    }

    /// Cantidad inválida o cero para marcar el campo en la vista.
    var isQuantityInvalid: Bool {
        !isQuantityValid
    }

    /// El botón decrementar del Stepper se desactiva cuando la cantidad es 1 o menor.
    var canDecrementQuantity: Bool {
        guard let current = parsedQuantity else { return false }
        return current > 1
    }

    mutating func incrementQuantity() {
        if let current = parsedQuantity {
            let next = current + 1
            quantityText = DraftOrderItem.formatQuantityForInput(next)
        } else {
            quantityText = "1"
        }
    }

    mutating func decrementQuantity() {
        guard let current = parsedQuantity, current > 1 else { return }
        let next = max(Decimal(1), current - 1)
        quantityText = DraftOrderItem.formatQuantityForInput(next)
    }

    /// Cambia el modo entre .batch y .unit según la regla del bloque I12.
    mutating func changeMode(to newMode: RemoteOrderSoldBy) {
        guard newMode != soldBy else { return }
        soldBy = newMode
        switch newMode {
        case .batch:
            quantityText = "1"
            if let suggested = suggestedPriceBatchCents {
                unitPriceText = CurrencyMath.formatForInput(cents: suggested)
            } else {
                unitPriceText = ""
            }
        case .unit:
            if let yield = yieldQuantity {
                quantityText = DraftOrderItem.formatQuantityForInput(yield)
            } else {
                quantityText = "1"
            }
            if let suggested = suggestedPriceUnitCents {
                unitPriceText = CurrencyMath.formatForInput(cents: suggested)
            } else {
                unitPriceText = ""
            }
        }
    }

    static func formatQuantityForInput(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Modelo de presentación para el formulario de nuevo o editar pedido (MVVM, Regla 5).
@Observable
final class OrderFormModel {
    let editingOrder: RemoteOrder?

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
            guard item.isQuantityValid else { return false }
        }
        return !isSaving
    }

    init(order: RemoteOrder? = nil, draftItems: [DraftOrderItem]? = nil) {
        self.editingOrder = order

        if let order {
            self.customerId = order.customerId
            self.customerName = order.customerName
            self.customerPhone = order.customerPhone ?? ""
            self.deliveryAt = order.deliveryAt
            self.notes = order.notes ?? ""
            // Al editar, conserva su precio acordado y su cantidad; soldBy nulo se trata como tanda.
            self.items = order.items.map { item in
                let soldBy = item.soldBy ?? .batch
                let unitLabel = item.unitLabel ?? .pz
                return DraftOrderItem(
                    recipeId: item.recipeId,
                    recipeName: item.recipeName,
                    soldBy: soldBy,
                    yieldQuantity: nil,
                    yieldUnit: unitLabel,
                    quantityText: item.quantity,
                    unitPriceText: CurrencyMath.formatForInput(cents: item.unitPriceCents),
                    suggestedPriceBatchCents: nil,
                    suggestedPriceUnitCents: nil,
                    costCalculationFailed: false
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

        if let draftItems {
            self.items = draftItems
        }
    }

    /// Selecciona un cliente del catálogo (Bloque I7b).
    func selectCustomer(_ customer: RemoteCustomer) {
        self.customerId = customer.id
        self.customerName = customer.name
        self.customerPhone = customer.phone ?? ""
    }

    /// Pide el rendimiento y costos de las recetas para las líneas existentes al editar.
    /// Si falla, la línea se edita sin selector.
    func loadRecipeDetailsForEditing() async {
        guard isEditing else { return }

        await withTaskGroup(of: (UUID, RemoteRecipe?, RemoteRecipeCost?).self) { group in
            for item in items {
                group.addTask {
                    do {
                        async let recipeReq: RemoteRecipe = NetworkService.shared.request(
                            .get,
                            "/recipes/\(item.recipeId)"
                        )
                        async let costReq: RemoteRecipeCost = NetworkService.shared.request(
                            .get,
                            "/recipes/\(item.recipeId)/cost"
                        )
                        let (recipe, cost) = try await (recipeReq, costReq)
                        return (item.id, recipe, cost)
                    } catch where error.isCancellation {
                        return (item.id, nil, nil)
                    } catch {
                        return (item.id, nil, nil)
                    }
                }
            }

            for await (id, recipe, cost) in group {
                guard let recipe = recipe,
                      let idx = items.firstIndex(where: { $0.id == id }) else { continue }
                let yieldDec = Decimal(string: recipe.yieldQuantity, locale: Locale(identifier: "en_US_POSIX")) ?? 1
                items[idx].yieldQuantity = yieldDec
                items[idx].yieldUnit = recipe.yieldUnit
                if let cost = cost {
                    items[idx].suggestedPriceBatchCents = cost.suggestedPriceCents
                    items[idx].suggestedPriceUnitCents = cost.suggestedPricePerYieldUnitCents
                }
            }
        }
    }

    /// Agrega una receta seleccionada:
    /// Si yieldQuantity > 1, empieza por pieza con cantidad igual al rendimiento y precio por unidad.
    /// Si rinde 1, empieza por tanda con cantidad 1 y precio por tanda.
    func addRecipe(_ recipeItem: RemoteRecipeListItem) async {
        let recipe = recipeItem.recipe
        let yieldQty = Decimal(string: recipe.yieldQuantity, locale: Locale(identifier: "en_US_POSIX")) ?? 1
        let startsAsUnit = yieldQty > 1
        let initialSoldBy: RemoteOrderSoldBy = startsAsUnit ? .unit : .batch
        let initialQuantityText = startsAsUnit ? DraftOrderItem.formatQuantityForInput(yieldQty) : "1"

        do {
            let cost: RemoteRecipeCost = try await NetworkService.shared.request(
                .get,
                "/recipes/\(recipe.id)/cost"
            )

            let initialPriceCents = startsAsUnit ? cost.suggestedPricePerYieldUnitCents : cost.suggestedPriceCents
            let initialPriceText: String
            if let cents = initialPriceCents {
                initialPriceText = CurrencyMath.formatForInput(cents: cents)
            } else {
                initialPriceText = ""
            }

            let draft = DraftOrderItem(
                recipeId: recipe.id,
                recipeName: recipe.name,
                soldBy: initialSoldBy,
                yieldQuantity: yieldQty,
                yieldUnit: recipe.yieldUnit,
                quantityText: initialQuantityText,
                unitPriceText: initialPriceText,
                suggestedPriceBatchCents: cost.suggestedPriceCents,
                suggestedPriceUnitCents: cost.suggestedPricePerYieldUnitCents,
                costCalculationFailed: false
            )
            items.append(draft)
        } catch where error.isCancellation {
            return
        } catch {
            let draft = DraftOrderItem(
                recipeId: recipe.id,
                recipeName: recipe.name,
                soldBy: initialSoldBy,
                yieldQuantity: yieldQty,
                yieldUnit: recipe.yieldUnit,
                quantityText: initialQuantityText,
                unitPriceText: "",
                suggestedPriceBatchCents: nil,
                suggestedPriceUnitCents: nil,
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
    func save() async throws -> RemoteOrder {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let payloadItems = items.compactMap { item -> OrderItemInput? in
            guard let cents = CurrencyMath.parseCents(from: item.unitPriceText) else { return nil }
            guard let quantityString = Quantity.parse(item.quantityText) else { return nil }
            return OrderItemInput(
                recipeId: item.recipeId,
                soldBy: item.soldBy,
                quantity: quantityString,
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
                let updated: RemoteOrder = try await NetworkService.shared.request(
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
                let created: RemoteOrder = try await NetworkService.shared.request(
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
