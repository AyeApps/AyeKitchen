import Foundation
import SwiftUI

enum PaymentMethodOption: String, CaseIterable, Identifiable, Sendable {
    case cash = "efectivo"
    case transfer = "transferencia"
    case card = "tarjeta"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: "Efectivo"
        case .transfer: "Transferencia"
        case .card: "Tarjeta"
        }
    }
}

/// Modelo de presentación para registrar un pago a un pedido (MVVM, Regla 5).
@Observable
final class RecordPaymentModel {
    let order: Order

    var amountText: String
    var selectedMethod: PaymentMethodOption = .cash
    var isSaving: Bool = false
    var errorMessage: String? = nil

    init(order: Order) {
        self.order = order
        self.amountText = CurrencyMath.formatForInput(cents: order.balanceCents)
    }

    var parsedCents: Int? {
        CurrencyMath.parseCents(from: amountText)
    }

    var canSubmit: Bool {
        guard let cents = parsedCents, cents > 0 else { return false }
        return !isSaving
    }

    func savePayment() async -> Order? {
        guard let cents = parsedCents else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let body = PaymentCreateBody(
                amountCents: cents,
                method: selectedMethod.rawValue
            )
            let updated: Order = try await NetworkService.shared.request(
                .post,
                "/orders/\(order.id)/payments",
                body: body
            )
            return updated
        } catch {
            if let apiError = error as? APIError, apiError.code == "PAYMENT_EXCEEDS_BALANCE" {
                errorMessage = "Eso es más de lo que te falta cobrar."
            } else {
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }
}
