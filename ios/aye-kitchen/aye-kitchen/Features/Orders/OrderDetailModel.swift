import Foundation
import SwiftUI

/// Cuerpo de la petición para cambiar de estado un pedido.
nonisolated struct OrderStatusPatch: Encodable, Sendable {
    let status: OrderStatus
}

/// Cuerpo de la petición para registrar un pago.
nonisolated struct PaymentCreateBody: Encodable, Sendable {
    let amountCents: Int
    let method: String?
}

/// Modelo de presentación para el detalle de un pedido (MVVM, Regla 5).
@Observable
final class OrderDetailModel {
    var order: Order
    var isWorking = false
    var errorMessage: String?

    init(order: Order) {
        self.order = order
    }

    /// Cambia el estado del pedido:
    /// PATCH /orders/{id} solo con status.
    func updateStatus(_ newStatus: OrderStatus) async throws {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let body = OrderStatusPatch(status: newStatus)
            let updated: Order = try await NetworkService.shared.request(
                .patch,
                "/orders/\(order.id)",
                body: body
            )
            self.order = updated
        } catch {
            self.errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            throw error
        }
    }

    /// Borra el pedido:
    /// DELETE /orders/{id} (204)
    func deleteOrder() async throws {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await NetworkService.shared.requestNoContent(.delete, "/orders/\(order.id)")
        } catch {
            self.errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            throw error
        }
    }

    /// Borra un pago registrado:
    /// DELETE /orders/{id}/payments/{payment_id} (devuelve el Order actualizado)
    func deletePayment(id: String) async throws {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let updated: Order = try await NetworkService.shared.request(
                .delete,
                "/orders/\(order.id)/payments/\(id)"
            )
            self.order = updated
        } catch {
            self.errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            throw error
        }
    }

    /// Registra un nuevo pago en el pedido:
    /// POST /orders/{id}/payments (devuelve el Order actualizado)
    func addPayment(amountCents: Int, method: String) async throws {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let body = PaymentCreateBody(
                amountCents: amountCents,
                method: method
            )
            let updated: Order = try await NetworkService.shared.request(
                .post,
                "/orders/\(order.id)/payments",
                body: body
            )
            self.order = updated
        } catch {
            self.errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            throw error
        }
    }
}
