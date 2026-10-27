import SwiftUI

/// Lista de pedidos según Bloque I2 y artboard "Inicio — iPhone".
struct OrdersView: View {
    @State private var model = OrdersModel()
    @State private var showingNewOrder = false

    var body: some View {
        NavigationStack {
            content
                .background(.canvasBackground)
                .navigationTitle("Pedidos")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Nuevo pedido") {
                            showingNewOrder = true
                        }
                    }
                }
                .navigationDestination(for: Order.self) { order in
                    OrderDetailView(
                        order: order,
                        onOrderUpdated: { updated in
                            model.updateOrder(updated)
                        },
                        onOrderDeleted: { id in
                            model.removeOrder(id: id)
                        }
                    )
                }
                .sheet(isPresented: $showingNewOrder) {
                    OrderFormView(order: nil) { newOrder in
                        model.updateOrder(newOrder)
                    }
                }
                .task {
                    if model.state == .loading {
                        await model.load()
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading where model.isEmpty:
            VStack {
                pickerView
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.md)
                Spacer()
                ProgressView()
                    .tint(Color.accentColor)
                Spacer()
            }
        case .error(let message) where model.isEmpty:
            VStack {
                pickerView
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.md)
                Spacer()
                ErrorStateView(message: message) {
                    Task { await model.load() }
                }
                Spacer()
            }
        default:
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
            .refreshable {
                await model.load()
            }
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
                        NavigationLink(value: order) {
                            OrderRow(order: order)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Fila individual de pedido con soporte para Dynamic Type y accesibilidad.
struct OrderRow: View {
    let order: Order
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
    }

    private var standardLayout: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            dateColumn
                .frame(width: 44)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(order.customerName)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusChip(status: order.status)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            dateBadge

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(order.customerName)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.leading)
            }

            StatusChip(status: order.status)
        }
    }

    private var dateColumn: some View {
        VStack(spacing: 2) {
            Text(OrderDateFormatter.dayAbbreviation(for: order.deliveryAt))
                .font(.footnote.weight(.heavy))
                .foregroundStyle(.tint)
            Text(OrderDateFormatter.dayNumber(for: order.deliveryAt))
                .font(.title3.weight(.heavy))
                .foregroundStyle(.inkPrimary)
        }
    }

    private var dateBadge: some View {
        HStack(spacing: Spacing.xs) {
            Text(OrderDateFormatter.dayAbbreviation(for: order.deliveryAt))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.tint)
            Text(OrderDateFormatter.dayNumber(for: order.deliveryAt))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.inkPrimary)
        }
    }

    private var subtitle: String {
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

#if DEBUG
#Preview("Claro") {
    OrdersViewMockContainer()
}

#Preview("Letra AX3") {
    OrdersViewMockContainer()
        .dynamicTypeSize(.accessibility3)
}

private struct OrdersViewMockContainer: View {
    @State private var model = OrdersModel(mockOrders: [
        .mockOverdue,
        .mockPendingToday,
        .mockPendingTomorrow,
        .mockDelivered
    ])

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    Picker("Filtro de pedidos", selection: $model.filter) {
                        ForEach(OrdersFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForEach(model.sections) { section in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(section.title)
                                .sectionTitleStyle()

                            RowGroup {
                                ForEach(section.orders) { order in
                                    OrderRow(order: order)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .background(.canvasBackground)
            .navigationTitle("Pedidos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddToolbarButton(label: "Nuevo pedido") {}
                }
            }
        }
    }
}
#endif
