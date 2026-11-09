import Foundation
import KitchenDomain
import Observation

/// Modelo de presentación para el detalle de un pedido (MVVM, Regla 5 / Bloque I18 local-first).
@Observable
final class OrderDetailModel {
    let orderId: String
    var store: LocalStore
    var isWorking = false
    var errorMessage: String?

    init(orderId: String, store: LocalStore = .shared) {
        self.orderId = orderId
        self.store = store
    }

    var order: Order? {
        try? store.data.order(id: orderId)
    }

    /// Tandas necesarias y sobrante calculados para este pedido.
    var batchNeeds: [BatchNeed] {
        guard let order else { return [] }
        return store.data.batchNeeds(for: order)
    }

    /// Cambia el estado del pedido.
    func updateStatus(_ newStatus: OrderStatus) {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try store.mutate { data, ctx in
                try data.updateOrder(id: orderId, status: newStatus, ctx: ctx)
            }
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Borra el pedido en modo soft delete.
    func deleteOrder() throws {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        try store.mutate { data, ctx in
            try data.deleteOrder(id: orderId, ctx: ctx)
        }
    }

    /// Borra un pago registrado.
    func deletePayment(id: String) {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try store.mutate { data, ctx in
                try data.deletePayment(orderId: orderId, paymentId: id, ctx: ctx)
            }
        } catch let domainError as DomainError {
            errorMessage = domainError.detail
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
