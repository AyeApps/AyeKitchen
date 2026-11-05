import SwiftUI
import KitchenDomain

/// Detalle del pedido (Bloque I18 local-first).
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
        orderId: String,
        store: LocalStore = .shared,
        onOrderUpdated: ((Order) -> Void)? = nil,
        onOrderDeleted: ((String) -> Void)? = nil
    ) {
        self._model = State(initialValue: OrderDetailModel(orderId: orderId, store: store))
        self.onOrderUpdated = onOrderUpdated
        self.onOrderDeleted = onOrderDeleted
    }

    init(
        order: Order,
        store: LocalStore = .shared,
        onOrderUpdated: ((Order) -> Void)? = nil,
        onOrderDeleted: ((String) -> Void)? = nil
    ) {
        self.init(
            orderId: order.id,
            store: store,
            onOrderUpdated: onOrderUpdated,
            onOrderDeleted: onOrderDeleted
        )
    }

    var body: some View {
        Group {
            if let order = model.order {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        headerSection(order: order)
                        productsSection(order: order)
                        financialSummaryCard(order: order)
                        paymentsSection(order: order)
                        notesSection(order: order)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                }
                .background(.canvasBackground)
                .navigationTitle(order.customerName)
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
                        do {
                            let id = order.id
                            try model.deleteOrder()
                            onOrderDeleted?(id)
                            dismiss()
                        } catch {
                            // Error visualizable
                        }
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Se eliminará el pedido de \(order.customerName). Esta acción no se puede deshacer.")
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
                            model.deletePayment(id: payment.id)
                            if let refreshed = model.order {
                                onOrderUpdated?(refreshed)
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
                    OrderFormView(mode: .edit(orderId: order.id), store: model.store) { updated in
                        onOrderUpdated?(updated)
                    }
                }
                .sheet(isPresented: $showingRecordPaymentSheet) {
                    RecordPaymentSheet(orderId: order.id, store: model.store) { updated in
                        onOrderUpdated?(updated)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Pedido no encontrado",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Este pedido fue eliminado.")
                )
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

    private func headerSection(order: Order) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(OrderDateFormatter.fullDateTime(for: order.deliveryAt))
                .font(.title2.weight(.heavy))
                .foregroundStyle(.inkPrimary)

            HStack(spacing: Spacing.md) {
                if let phone = order.customerPhone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
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

                statusMenu(order: order)
            }
        }
    }

    private func statusMenu(order: Order) -> some View {
        Menu {
            ForEach(OrderStatus.allCases, id: \.self) { status in
                Button {
                    model.updateStatus(status)
                    if let refreshed = model.order {
                        onOrderUpdated?(refreshed)
                    }
                } label: {
                    HStack {
                        Text(status.label)
                        if status == order.status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                OrderStatusChip(status: order.status)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.inkMuted)
            }
        }
        .accessibilityLabel("Cambiar estado: \(order.status.label)")
    }

    // MARK: - Productos

    private func productsSection(order: Order) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Productos")
                .sectionTitleStyle()

            RowGroup {
                ForEach(order.items, id: \.self) { item in
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

                                Text(itemQuantityPriceDescription(for: item))
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

                                    Text(itemQuantityPriceDescription(for: item))
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

    private func itemQuantityPriceDescription(for item: OrderItem) -> String {
        let mode = item.soldBy
        let qtyFormatted = Quantity.format(item.quantity)
        let priceFormatted = Money.format(cents: item.unitPriceCents)
        switch mode {
        case .unit:
            let unitText = item.unitLabel?.rawValue ?? "pz"
            return "\(qtyFormatted) \(unitText) × \(priceFormatted)"
        case .batch:
            let clean = item.quantity.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            let isSingular = (clean == "1" || clean == "1.0" || clean == "1.00" || clean == "1.000")
            let word = isSingular ? "tanda" : "tandas"
            return "\(qtyFormatted) \(word) × \(priceFormatted)"
        }
    }

    // MARK: - Tarjeta de balance y costo

    private func financialSummaryCard(order: Order) -> some View {
        let totals = order.totals
        return VStack(alignment: .leading, spacing: Spacing.md) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Total")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.totalCents))
                            .font(.title2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Ya te pagaron")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.paidCents))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Te falta cobrar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.balanceCents))
                            .font(.title2.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(totals.balanceCents > 0 ? Color.accentColor : Color.inkPrimary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Total")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.totalCents))
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Ya te pagaron")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.paidCents))
                            .font(.body.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.inkPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Te falta cobrar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.balanceCents))
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(totals.balanceCents > 0 ? Color.accentColor : Color.inkPrimary)
                    }
                }
            }

            Rectangle()
                .fill(.dividerLine)
                .frame(height: 1)

            Text("Te cuesta \(Money.format(cents: totals.costCents)) · Ganas \(Money.format(cents: totals.profitCents))")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
        }
        .softCard()
    }

    // MARK: - Pagos

    private func paymentsSection(order: Order) -> some View {
        let totals = order.totals
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pagos")
                .sectionTitleStyle()

            if order.payments.isEmpty {
                Text("No hay pagos registrados todavía.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            } else {
                RowGroup {
                    ForEach(order.payments) { payment in
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

            if totals.balanceCents > 0 {
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
    private func notesSection(order: Order) -> some View {
        if let notes = order.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
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

// MARK: - Previews

#if DEBUG
#Preview("Detalle con pago parcial — ord-1") {
    NavigationStack {
        OrderDetailView(orderId: "ord-1", store: .preview())
    }
}

#Preview("Detalle por pieza — ord-2") {
    NavigationStack {
        OrderDetailView(orderId: "ord-2", store: .preview())
    }
}

#Preview("Detalle entregado — ord-3") {
    NavigationStack {
        OrderDetailView(orderId: "ord-3", store: .preview())
    }
}

#Preview("Detalle AX3") {
    NavigationStack {
        OrderDetailView(orderId: "ord-1", store: .preview())
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
