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

/// Hoja para registrar un pago a un pedido según Bloque I2.
struct RecordPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let order: Order
    let onPaymentSaved: (Order) -> Void

    @State private var amountText: String
    @State private var selectedMethod: PaymentMethodOption = .cash
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(order: Order, onPaymentSaved: @escaping (Order) -> Void) {
        self.order = order
        self.onPaymentSaved = onPaymentSaved
        _amountText = State(initialValue: CurrencyMath.formatForInput(cents: order.balanceCents))
    }

    private var parsedCents: Int? {
        CurrencyMath.parseCents(from: amountText)
    }

    private var canSubmit: Bool {
        guard let cents = parsedCents, cents > 0 else { return false }
        return !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Saldo pendiente")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)

                        Text(Money.format(cents: order.balanceCents))
                            .font(.largeTitle.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                    }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        KitchenTextField(
                            label: "Monto del pago",
                            text: $amountText,
                            keyboard: .decimalPad
                        )

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Método")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.inkPrimary)

                            Picker("Método de pago", selection: $selectedMethod) {
                                ForEach(PaymentMethodOption.allCases) { method in
                                    Text(method.label).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.warningText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                    }

                    Button {
                        Task { await savePayment() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.accentInk)
                        } else {
                            Text("Guardar pago")
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!canSubmit)
                }
                .padding(Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvasBackground)
            .navigationTitle("Registrar pago")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    private func savePayment() async {
        guard let cents = parsedCents else { return }
        isSaving = true
        errorMessage = nil

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
            onPaymentSaved(updated)
            dismiss()
        } catch {
            if let apiError = error as? APIError, apiError.code == "PAYMENT_EXCEEDS_BALANCE" {
                errorMessage = "Eso es más de lo que te falta cobrar."
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isSaving = false
    }
}

#if DEBUG
#Preview("Claro") {
    RecordPaymentSheet(order: .mockPendingToday) { _ in }
}

#Preview("Letra AX3") {
    RecordPaymentSheet(order: .mockPendingToday) { _ in }
        .dynamicTypeSize(.accessibility3)
}
#endif
