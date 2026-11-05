import SwiftUI
import KitchenDomain

/// Vista de Detalle de Cliente (Bloque I18 local-first).
struct CustomerDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: CustomerDetailModel
    @State private var showingEditSheet = false

    var onCustomerUpdated: ((Customer) -> Void)?
    var onCustomerDeleted: ((String) -> Void)?

    init(
        customerId: String,
        store: LocalStore = .shared,
        onCustomerUpdated: ((Customer) -> Void)? = nil,
        onCustomerDeleted: ((String) -> Void)? = nil
    ) {
        self._model = State(initialValue: CustomerDetailModel(
            customerId: customerId,
            store: store
        ))
        self.onCustomerUpdated = onCustomerUpdated
        self.onCustomerDeleted = onCustomerDeleted
    }

    init(
        customer: Customer,
        store: LocalStore = .shared,
        onCustomerUpdated: ((Customer) -> Void)? = nil,
        onCustomerDeleted: ((String) -> Void)? = nil
    ) {
        self.init(
            customerId: customer.id,
            store: store,
            onCustomerUpdated: onCustomerUpdated,
            onCustomerDeleted: onCustomerDeleted
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                headerSection
                ordersSection
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .background(.canvasBackground)
        .navigationTitle(model.customer?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") {
                    showingEditSheet = true
                }
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let customer = model.customer {
                CustomerFormView(customer: customer, store: model.store) { updated in
                    onCustomerUpdated?(updated)
                }
            }
        }
    }

    // MARK: - Secciones

    @ViewBuilder
    private var headerSection: some View {
        if let customer = model.customer {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let phone = customer.phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
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

                if let notes = customer.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Notas")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)

                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.inkPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .softCard()
                }
            }
        }
    }

    @ViewBuilder
    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pedidos")
                .sectionTitleStyle()

            if model.orders.isEmpty {
                Text("Todavía no tiene pedidos.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xs)
            } else {
                RowGroup {
                    ForEach(model.orders) { order in
                        NavigationLink {
                            OrderDetailView(orderId: order.id, store: model.store)
                        } label: {
                            orderRow(order)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.md)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func orderRow(_ order: Order) -> some View {
        let totals = order.totals
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                OrderStatusChip(status: order.status)

                Text(OrderDateFormatter.fullDateTime(for: order.deliveryAt))
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)

                HStack(spacing: Spacing.sm) {
                    Text(Money.format(cents: totals.totalCents))
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)

                    if totals.balanceCents > 0 {
                        Text("Saldo: \(Money.format(cents: totals.balanceCents))")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.warningText)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(OrderDateFormatter.fullDateTime(for: order.deliveryAt))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.inkPrimary)

                    Spacer()

                    OrderStatusChip(status: order.status)
                }

                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(Money.format(cents: totals.totalCents))
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)

                    if totals.balanceCents > 0 {
                        Text("Saldo: \(Money.format(cents: totals.balanceCents))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.warningText)
                    }

                    Spacer()
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Detalle de cliente") {
    NavigationStack {
        CustomerDetailView(customerId: "cus-ana", store: .preview())
    }
}

#Preview("Detalle AX3") {
    NavigationStack {
        CustomerDetailView(customerId: "cus-ana", store: .preview())
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
