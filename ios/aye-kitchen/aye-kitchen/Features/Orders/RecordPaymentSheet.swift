import SwiftUI

/// Hoja para registrar un pago a un pedido según Bloque I2.
struct RecordPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: RecordPaymentModel
    let onPaymentSaved: (Order) -> Void

    init(order: Order, onPaymentSaved: @escaping (Order) -> Void) {
        _model = State(initialValue: RecordPaymentModel(order: order))
        self.onPaymentSaved = onPaymentSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Saldo pendiente")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)

                        Text(Money.format(cents: model.order.balanceCents))
                            .font(.largeTitle.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                    }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        KitchenTextField(
                            label: "Monto del pago",
                            text: $model.amountText,
                            keyboard: .decimalPad
                        )

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Método")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.inkPrimary)

                            Picker("Método de pago", selection: $model.selectedMethod) {
                                ForEach(PaymentMethodOption.allCases) { method in
                                    Text(method.label).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.warningText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
                    }

                    Button {
                        Task {
                            if let updated = await model.savePayment() {
                                onPaymentSaved(updated)
                                dismiss()
                            }
                        }
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .tint(.accentInk)
                        } else {
                            Text("Guardar pago")
                        }
                    }
                    .buttonStyle(.kitchenPrimary)
                    .disabled(!model.canSubmit)
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
