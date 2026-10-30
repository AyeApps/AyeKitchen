import SwiftUI

/// Detalle del pedido según Bloque I2.
struct OrderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: OrderDetailModel
    @State private var showingEditSheet = false
    @State private var showingDeleteOrderConfirmation = false
    @State private var showingRecordPaymentSheet = false
    @State private var paymentToDelete: Payment?

    var onOrderUpdated: ((Order) -> Void)?
    var onOrderDeleted: ((String) -> Void)?

    init(
        order: Order,
        onOrderUpdated: ((Order) -> Void)? = nil,
        onOrderDeleted: ((String) -> Void)? = nil
    ) {
        _model = State(initialValue: OrderDetailModel(order: order))
        self.onOrderUpdated = onOrderUpdated
        self.onOrderDeleted = onOrderDeleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                headerSection
                productsSection
                financialSummaryCard
                paymentsSection
                notesSection
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .background(.canvasBackground)
        .navigationTitle(model.order.customerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Editar pedido", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteOrderConfirmation = true
                    } label: {
                        Label("Borrar pedido", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Opciones del pedido")
            }
        }
        .confirmationDialog(
            "¿Borrar este pedido?",
            isPresented: $showingDeleteOrderConfirmation,
            titleVisibility: .visible
        ) {
            Button("Borrar pedido", role: .destructive) {
                Task {
                    do {
                        let id = model.order.id
                        try await model.deleteOrder()
                        onOrderDeleted?(id)
                        dismiss()
                    } catch {
                        // Error visualizable
                    }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará el pedido de \(model.order.customerName). Esta acción no se puede deshacer.")
        }
        .confirmationDialog(
            "¿Borrar este pago?",
            isPresented: Binding(
                get: { paymentToDelete != nil },
                set: { if !$0 { paymentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Borrar pago", role: .destructive) {
                if let payment = paymentToDelete {
                    paymentToDelete = nil
                    Task {
                        do {
                            try await model.deletePayment(id: payment.id)
                            onOrderUpdated?(model.order)
                        } catch {
                            // model.errorMessage ya fue asignado en model.deletePayment
                        }
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                paymentToDelete = nil
            }
        } message: {
            if let payment = paymentToDelete {
                Text("Se eliminará el pago de \(Money.format(cents: payment.amountCents)).")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            OrderFormView(order: model.order) { updated in
                model.order = updated
                onOrderUpdated?(updated)
            }
        }
        .sheet(isPresented: $showingRecordPaymentSheet) {
            RecordPaymentSheet(order: model.order) { updated in
                model.order = updated
                onOrderUpdated?(updated)
            }
        }
        .alert("No se pudo guardar", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Encabezado

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(OrderDateFormatter.fullDateTime(for: model.order.deliveryAt))
                .font(.title2.weight(.heavy))
                .foregroundStyle(.inkPrimary)

            HStack(spacing: Spacing.md) {
                if let phone = model.order.customerPhone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
                    let cleanedPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    if let url = URL(string: "tel:\(cleanedPhone)") {
                        Link(destination: url) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "phone.fill")
                                    .imageScale(.small)
                                Text(phone)
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                        }
                    }
                }

                Spacer()

                statusMenu
            }
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(OrderStatus.allCases, id: \.self) { status in
                Button {
                    Task {
                        do {
                            try await model.updateStatus(status)
                            onOrderUpdated?(model.order)
                        } catch {
                            // model.errorMessage ya fue asignado en model.updateStatus
                        }
                    }
                } label: {
                    HStack {
                        Text(status.label)
                        if status == model.order.status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                StatusChip(status: model.order.status)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
        }
        .accessibilityLabel("Cambiar estado: \(model.order.status.label)")
    }

    // MARK: - Productos

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Productos")
                .sectionTitleStyle()

            RowGroup {
                ForEach(model.order.items, id: \.self) { item in
                    let subtotal = CurrencyMath.calculateSubtotalCents(
                        quantity: item.quantity,
                        unitPriceCents: item.unitPriceCents
                    )

                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(item.recipeName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.inkPrimary)

                                Text("\(Quantity.format(item.quantity)) × \(Money.format(cents: item.unitPriceCents))")
                                    .font(.subheadline)
                                    .foregroundStyle(.inkMuted)

                                Text(Money.format(cents: subtotal))
                                    .font(.body.weight(.heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(.inkPrimary)
                            }
                        } else {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(item.recipeName)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.inkPrimary)

                                    Text("\(Quantity.format(item.quantity)) × \(Money.format(cents: item.unitPriceCents))")
                                        .font(.subheadline)
                                        .foregroundStyle(.inkMuted)
                                }

                                Spacer()

                                Text(Money.format(cents: subtotal))
                                    .font(.body.weight(.heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(.inkPrimary)
                            }
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }

    // MARK: - Tarjeta crema de balance y costo

    private var financialSummaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Total")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: model.order.totalCents))
                            .font(.title2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Ya te pagaron")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: model.order.paidCents))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Te falta cobrar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: model.order.balanceCents))
                            .font(.title2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(model.order.balanceCents > 0 ? Color.accentColor : Color.inkPrimary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Total")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: model.order.totalCents))
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Ya te pagaron")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: model.order.paidCents))
                            .font(.body.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Te falta cobrar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: model.order.balanceCents))
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(model.order.balanceCents > 0 ? Color.accentColor : Color.inkPrimary)
                    }
                }
            }

            Rectangle()
                .fill(.dividerLine)
                .frame(height: 1)

            Text("Te cuesta \(Money.format(cents: model.order.costCents)) · Ganas \(Money.format(cents: model.order.profitCents))")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
        }
        .softCard()
    }

    // MARK: - Pagos

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pagos")
                .sectionTitleStyle()

            if model.order.payments.isEmpty {
                Text("No hay pagos registrados todavía.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            } else {
                RowGroup {
                    ForEach(model.order.payments) { payment in
                        paymentRow(payment: payment)
                            .contextMenu {
                                Button(role: .destructive) {
                                    paymentToDelete = payment
                                } label: {
                                    Label("Borrar pago", systemImage: "trash")
                                }
                            }
                            .accessibilityAction(named: "Borrar pago") {
                                paymentToDelete = payment
                            }
                    }
                }
            }

            if model.order.balanceCents > 0 {
                Button("Registrar pago") {
                    showingRecordPaymentSheet = true
                }
                .buttonStyle(.kitchenPrimary)
            }
        }
    }

    private func paymentRow(payment: Payment) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(Money.format(cents: payment.amountCents))
                    .font(.body.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.inkPrimary)

                HStack(spacing: Spacing.xs) {
                    Text(OrderDateFormatter.paymentDate(for: payment.paidAt))
                    if let method = payment.method, !method.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("·")
                        Text(method.capitalized(with: Locale(identifier: "es_MX")))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
            }

            Spacer()

            Button(role: .destructive) {
                paymentToDelete = payment
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Borrar pago de \(Money.format(cents: payment.amountCents))")
        }
        .padding(Spacing.lg)
    }

    // MARK: - Notas

    @ViewBuilder
    private var notesSection: some View {
        if let notes = model.order.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Notas")
                    .sectionTitleStyle()

                Text(notes)
                    .font(.body)
                    .foregroundStyle(.inkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.lg)
                    .background(.surfaceCard, in: .rect(cornerRadius: Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(.borderLine, lineWidth: 1)
                    }
            }
        }
    }
}

#if DEBUG
#Preview("Claro") {
    NavigationStack {
        OrderDetailView(order: .mockPendingToday)
    }
}

#Preview("Letra AX3") {
    NavigationStack {
        OrderDetailView(order: .mockPendingToday)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
