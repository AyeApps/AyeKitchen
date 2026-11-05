import Foundation
import SwiftUI
import KitchenDomain
import Observation

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

/// Modelo de presentación para registrar un pago a un pedido (MVVM, Regla 5 / Bloque I18 local-first).
@Observable
final class RecordPaymentModel {
    let orderId: String
    var store: LocalStore

    var amountText: String
    var selectedMethod: PaymentMethodOption = .cash
    var isSaving: Bool = false
    var errorMessage: String? = nil

    init(orderId: String, store: LocalStore = .shared) {
        self.orderId = orderId
        self.store = store

        if let ord = try? store.data.order(id: orderId) {
            let balance = ord.totals.balanceCents
            self.amountText = CurrencyMath.formatForInput(cents: max(0, balance))
        } else {
            self.amountText = ""
        }
    }

    var order: Order? {
        try? store.data.order(id: orderId)
    }

    var parsedCents: Int? {
        CurrencyMath.parseCents(from: amountText)
    }

    var canSubmit: Bool {
        guard let cents = parsedCents, cents > 0 else { return false }
        return !isSaving
    }

    @discardableResult
    func savePayment() -> Order? {
        guard let cents = parsedCents else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try store.mutate { data, ctx in
                try data.addPayment(
                    orderId: orderId,
                    amountCents: cents,
                    method: selectedMethod.rawValue,
                    ctx: ctx
                )
            }
            return try? store.data.order(id: orderId)
        } catch let domainError as DomainError {
            if domainError.code == "PAYMENT_EXCEEDS_BALANCE" {
                errorMessage = "Eso es más de lo que te falta cobrar."
            } else {
                errorMessage = domainError.detail
            }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
