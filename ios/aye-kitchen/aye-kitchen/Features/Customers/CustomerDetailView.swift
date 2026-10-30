import SwiftUI

/// Vista de Detalle de Cliente según Bloque I7a.
struct CustomerDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: CustomerDetailModel
    @State private var showingEditSheet = false

    var onCustomerUpdated: ((Customer) -> Void)?
    var onCustomerDeleted: ((String) -> Void)?

    init(
        customer: Customer,
        mockOrders: [Order]? = nil,
        isMock: Bool = false,
        onCustomerUpdated: ((Customer) -> Void)? = nil,
        onCustomerDeleted: ((String) -> Void)? = nil
    ) {
        self._model = State(initialValue: CustomerDetailModel(
            customer: customer,
            mockOrders: mockOrders,
            isMock: isMock
        ))
        self.onCustomerUpdated = onCustomerUpdated
        self.onCustomerDeleted = onCustomerDeleted
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
        .navigationTitle(model.customer.name)
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
            CustomerFormView(customer: model.customer, isMock: model.isMock) { updated in
                model.updateCustomer(updated)
                onCustomerUpdated?(updated)
            }
        }
        .navigationDestination(for: Order.self) { order in
            OrderDetailView(
                order: order,
                onOrderUpdated: { _ in
                    Task { await model.loadOrders() }
                },
                onOrderDeleted: { _ in
                    Task { await model.loadOrders() }
                }
            )
        }
        .task {
            await model.loadOrders()
        }
        .refreshable {
            await model.loadOrders()
        }
    }

    // MARK: - Secciones

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let phone = model.customer.phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
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

            if let notes = model.customer.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
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

    @ViewBuilder
    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pedidos")
                .sectionTitleStyle()

            if model.isLoadingOrders && model.orders.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.accentColor)
                    Spacer()
                }
                .padding(.vertical, Spacing.lg)
            } else if let error = model.ordersErrorMessage, model.orders.isEmpty {
                ErrorStateView(message: error) {
                    Task { await model.loadOrders() }
                }
            } else if model.orders.isEmpty {
                Text("Todavía no tiene pedidos.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xs)
            } else {
                RowGroup {
                    ForEach(model.orders) { order in
                        NavigationLink(value: order) {
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
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                StatusChip(status: order.status)

                Text(OrderDateFormatter.fullDateTime(for: order.deliveryAt))
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)

                HStack(spacing: Spacing.sm) {
                    Text(Money.format(cents: order.totalCents))
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)

                    if order.balanceCents > 0 {
                        Text("Saldo: \(Money.format(cents: order.balanceCents))")
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

                    StatusChip(status: order.status)
                }

                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(Money.format(cents: order.totalCents))
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)

                    if order.balanceCents > 0 {
                        Text("Saldo: \(Money.format(cents: order.balanceCents))")
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
private let mockCustomerPreview = Customer(
    id: "mock_cust_preview",
    name: "Ana Ruiz",
    phone: "55 1234 5678",
    notes: "Le gusta poco dulce, recoge en la tarde",
    createdAt: Date(),
    updatedAt: Date()
)

private let mockOrdersSample: [Order] = [
    Order(
        id: "mock_ord_1",
        customerId: "mock_cust_preview",
        customerName: "Ana Ruiz",
        customerPhone: "55 1234 5678",
        deliveryAt: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
        status: .inProgress,
        notes: nil,
        items: [],
        payments: [],
        totalCents: 85000,
        paidCents: 50000,
        balanceCents: 35000,
        costCents: 32000,
        profitCents: 53000,
        createdAt: Date(),
        updatedAt: Date()
    ),
    Order(
        id: "mock_ord_2",
        customerId: "mock_cust_preview",
        customerName: "Ana Ruiz",
        customerPhone: "55 1234 5678",
        deliveryAt: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
        status: .delivered,
        notes: nil,
        items: [],
        payments: [],
        totalCents: 120000,
        paidCents: 120000,
        balanceCents: 0,
        costCents: 45000,
        profitCents: 75000,
        createdAt: Date(),
        updatedAt: Date()
    )
]

#Preview("Detalle con pedidos") {
    NavigationStack {
        CustomerDetailView(
            customer: mockCustomerPreview,
            mockOrders: mockOrdersSample,
            isMock: true
        )
    }
}

#Preview("Sin pedidos") {
    NavigationStack {
        CustomerDetailView(
            customer: mockCustomerPreview,
            mockOrders: [],
            isMock: true
        )
    }
}

#Preview("Letra AX3") {
    NavigationStack {
        CustomerDetailView(
            customer: mockCustomerPreview,
            mockOrders: mockOrdersSample,
            isMock: true
        )
        .dynamicTypeSize(.accessibility3)
    }
}
#endif
