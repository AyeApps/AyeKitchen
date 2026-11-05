import SwiftUI
import KitchenDomain

// MARK: - Chips de Estado de Pedido

extension OrderStatus {
    var label: String {
        switch self {
        case .pendiente: "Pendiente"
        case .enProceso: "En proceso"
        case .entregado: "Entregado"
        case .cancelado: "Cancelado"
        }
    }

    var chipTone: ChipTone {
        switch self {
        case .pendiente, .cancelado: .neutral
        case .enProceso: .inProgress
        case .entregado: .success
        }
    }
}

struct OrderStatusChip: View {
    let status: OrderStatus

    var body: some View {
        Chip(status.label, tone: status.chipTone)
            .accessibilityLabel("Estado: \(status.label)")
    }
}

// MARK: - Vista Principal de Pedidos

/// Lista de pedidos (Bloque I18 local-first).
struct OrdersView: View {
    @State private var model: OrdersModel
    @State private var showingNewOrder = false
    @State private var showingCustomers = false

    init(store: LocalStore = .shared) {
        self._model = State(initialValue: OrdersModel(store: store))
    }

    init(model: OrdersModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Pedidos")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingCustomers = true
                        } label: {
                            Image(systemName: "person.2")
                        }
                        .accessibilityLabel("Clientes")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Nuevo pedido") {
                            showingNewOrder = true
                        }
                    }
                }
                .sheet(isPresented: $showingCustomers) {
                    CustomersView(store: model.store)
                }
                .sheet(isPresented: $showingNewOrder) {
                    OrderFormView(.create, store: model.store)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                pickerView

                if model.isEmpty {
                    ContentUnavailableView(
                        "Todavía no hay pedidos",
                        systemImage: "list.clipboard",
                        description: Text("Toca + para anotar el primero.")
                    )
                    .padding(.top, 40)
                } else {
                    ordersList
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
    }

    private var pickerView: some View {
        Picker("Filtro de pedidos", selection: $model.filter) {
            ForEach(OrdersFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var ordersList: some View {
        ForEach(model.sections) { section in
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(section.title)
                    .sectionTitleStyle()

                RowGroup {
                    ForEach(section.orders) { order in
                        NavigationLink {
                            OrderDetailView(orderId: order.id, store: model.store)
                        } label: {
                            OrderRow(order: order)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Fila de Pedido

/// Fila individual de pedido con soporte para Dynamic Type y accesibilidad.
struct OrderRow: View {
    let order: Order?
    let orderId: String
    private let store: LocalStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(order: Order, store: LocalStore = .shared) {
        self.order = order
        self.orderId = order.id
        self.store = store
    }

    init(orderId: String, store: LocalStore = .shared) {
        self.order = nil
        self.orderId = orderId
        self.store = store
    }

    private var currentOrder: Order? {
        order ?? (try? store.data.order(id: orderId))
    }

    var body: some View {
        if let currentOrder {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLayout(order: currentOrder)
                } else {
                    standardLayout(order: currentOrder)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
    }

    private func standardLayout(order: Order) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            dateColumn(order: order)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(order.customerName)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)
                    .multilineTextAlignment(.leading)

                Text(subtitle(order: order))
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OrderStatusChip(status: order.status)
        }
    }

    private func accessibilityLayout(order: Order) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            dateBadge(order: order)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(order.customerName)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)
                    .multilineTextAlignment(.leading)

                Text(subtitle(order: order))
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.leading)
            }

            OrderStatusChip(status: order.status)
        }
    }

    private func dateColumn(order: Order) -> some View {
        VStack(spacing: 2) {
            Text(OrderDateFormatter.dayAbbreviation(for: order.deliveryAt))
                .font(.footnote.weight(.heavy))
                .foregroundStyle(.tint)
            Text(OrderDateFormatter.dayNumber(for: order.deliveryAt))
                .font(.title3.weight(.heavy))
                .foregroundStyle(.inkPrimary)
        }
    }

    private func dateBadge(order: Order) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(OrderDateFormatter.dayAbbreviation(for: order.deliveryAt))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.tint)
            Text(OrderDateFormatter.dayNumber(for: order.deliveryAt))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.inkPrimary)
        }
    }

    private func subtitle(order: Order) -> String {
        let time = OrderDateFormatter.timeString(for: order.deliveryAt)
        guard let first = order.items.first else {
            return time
        }
        let qty = Quantity.format(first.quantity)
        var cakeDesc = "\(first.recipeName) × \(qty)"
        let extra = order.items.count - 1
        if extra > 0 {
            cakeDesc += ", y \(extra) más"
        }
        return "\(time) · \(cakeDesc)"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Claro") {
    OrdersView(store: .preview())
}

#Preview("Letra AX3") {
    OrdersView(store: .preview())
        .dynamicTypeSize(.accessibility3)
}
#endif
