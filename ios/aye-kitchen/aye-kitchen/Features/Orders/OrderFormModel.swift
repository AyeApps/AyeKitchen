import Foundation
import SwiftUI
import KitchenDomain
import Observation

/// Línea de producto en el borrador del formulario (Bloque I18 local-first).
struct DraftOrderItem: Identifiable, Hashable {
    let id: UUID
    var recipeId: String
    var recipeName: String
    var soldBy: OrderSoldBy
    var yieldQuantity: Decimal?
    var yieldUnit: BaseUnit
    var quantityText: String
    var unitPriceText: String
    var suggestedPriceBatchCents: Int?
    var suggestedPriceUnitCents: Int?
    var costCalculationFailed: Bool

    init(
        id: UUID = UUID(),
        recipeId: String,
        recipeName: String,
        soldBy: OrderSoldBy = .batch,
        yieldQuantity: Decimal? = nil,
        yieldUnit: BaseUnit = .pz,
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

    /// Cambia el modo entre .batch y .unit según la regla del bloque I12 / I18.
    mutating func changeMode(to newMode: OrderSoldBy) {
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

/// Modelo de presentación para el formulario de nuevo o editar pedido (MVVM, Regla 5 / Bloque I18 local-first).
@Observable
final class OrderFormModel {
    enum Mode: Equatable, Sendable {
        case create
        case edit(orderId: String)
    }

    let mode: Mode
    var store: LocalStore

    var customerId: String? = nil
    var customerName: String = ""
    var customerPhone: String = ""
    var deliveryAt: Date
    var notes: String = ""
    var items: [DraftOrderItem] = []

    var isSaving = false
    var errorMessage: String?

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var editingOrderId: String? {
        if case .edit(let id) = mode { return id }
        return nil
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

    init(
        mode: Mode = .create,
        store: LocalStore = .shared,
        draftItems: [DraftOrderItem]? = nil
    ) {
        self.mode = mode
        self.store = store

        switch mode {
        case .create:
            self.customerId = nil
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date.now) ?? Date.now
            self.deliveryAt = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            self.items = []

        case .edit(let orderId):
            if let order = try? store.data.order(id: orderId) {
                self.customerId = order.customerId
                self.customerName = order.customerName
                self.customerPhone = order.customerPhone ?? ""
                self.deliveryAt = order.deliveryAt
                self.notes = order.notes ?? ""

                let costing = store.data.costingIndex()
                self.items = order.items.map { item in
                    let rec = store.data.recipe(id: item.recipeId)
                    let yieldDec = rec.flatMap { Decimal(string: $0.yieldQuantity, locale: Locale(identifier: "en_US_POSIX")) }
                    let yieldUnit = rec?.yieldUnit ?? (item.unitLabel ?? .pz)

                    var batchCost: Int? = nil
                    var unitCost: Int? = nil
                    if let rec {
                        if let cost = try? costing.calculateRecipeCost(recipe: rec, version: nil, now: Date()) {
                            batchCost = cost.suggestedPriceCents
                            unitCost = cost.suggestedPricePerYieldUnitCents
                        }
                    }

                    return DraftOrderItem(
                        recipeId: item.recipeId,
                        recipeName: item.recipeName,
                        soldBy: item.soldBy,
                        yieldQuantity: yieldDec,
                        yieldUnit: yieldUnit,
                        quantityText: item.quantity,
                        unitPriceText: CurrencyMath.formatForInput(cents: item.unitPriceCents),
                        suggestedPriceBatchCents: batchCost,
                        suggestedPriceUnitCents: unitCost,
                        costCalculationFailed: false
                    )
                }
            } else {
                self.deliveryAt = Date.now
                self.items = []
            }
        }

        if let draftItems {
            self.items = draftItems
        }
    }

    /// Selecciona un cliente de KitchenKit.
    func selectCustomer(_ customer: Customer) {
        self.customerId = customer.id
        self.customerName = customer.name
        self.customerPhone = customer.phone ?? ""
    }

    /// Agrega una receta seleccionada:
    /// Si yieldQuantity > 1, empieza por pieza con cantidad igual al rendimiento y precio por unidad.
    /// Si rinde 1, empieza por tanda con cantidad 1 y precio por tanda.
    func addRecipe(_ recipeItem: RecipeListItem) {
        let recipe = recipeItem.recipe
        let yieldQty = Decimal(string: recipe.yieldQuantity, locale: Locale(identifier: "en_US_POSIX")) ?? 1
        let startsAsUnit = yieldQty > 1
        let initialSoldBy: OrderSoldBy = startsAsUnit ? .unit : .batch
        let initialQuantityText = startsAsUnit ? DraftOrderItem.formatQuantityForInput(yieldQty) : "1"

        let costing = store.data.costingIndex()
        let cost = try? costing.calculateRecipeCost(recipe: recipe, version: nil, now: Date())

        let initialPriceCents = startsAsUnit ? cost?.suggestedPricePerYieldUnitCents : cost?.suggestedPriceCents
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
            suggestedPriceBatchCents: cost?.suggestedPriceCents,
            suggestedPriceUnitCents: cost?.suggestedPricePerYieldUnitCents,
            costCalculationFailed: cost == nil
        )
        items.append(draft)
    }

    /// Elimina una línea de producto.
    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Guarda el pedido aplicando las reglas de KitchenKit.
    func save() throws -> Order {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let payloadItems = items.compactMap { item -> OrderItemDraft? in
            guard let cents = CurrencyMath.parseCents(from: item.unitPriceText) else { return nil }
            guard let quantityString = Quantity.parse(item.quantityText) else { return nil }
            return OrderItemDraft(
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
            if let editingOrderId {
                let updated = try store.mutate { data, ctx in
                    try data.updateOrder(
                        id: editingOrderId,
                        customerId: customerId,
                        customerName: trimmedName.isEmpty ? nil : trimmedName,
                        customerPhone: phoneValue,
                        deliveryAt: deliveryAt,
                        status: nil,
                        notes: notesValue,
                        items: payloadItems,
                        ctx: ctx
                    )
                }
                return updated
            } else {
                let created = try store.mutate { data, ctx in
                    try data.createOrder(
                        customerId: customerId,
                        customerName: trimmedName.isEmpty ? nil : trimmedName,
                        customerPhone: phoneValue,
                        deliveryAt: deliveryAt,
                        items: payloadItems,
                        notes: notesValue,
                        ctx: ctx
                    )
                }
                return created
            }
        } catch let domainError as DomainError {
            switch domainError.code {
            case "PAYMENT_EXCEEDS_BALANCE":
                errorMessage = "Con este cambio el total quedaría por debajo de lo que ya te pagaron."
            case "CUSTOMER_REQUIRED":
                errorMessage = "Elige un cliente o escribe su nombre."
            case "INVALID_REFERENCE":
                errorMessage = "Una de las recetas ya no existe."
            default:
                errorMessage = domainError.detail
            }
            throw domainError
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
