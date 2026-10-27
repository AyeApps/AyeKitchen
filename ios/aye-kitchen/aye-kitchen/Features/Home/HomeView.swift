import SwiftUI

/// Inicio (artboard "Inicio — iPhone"). No muestra dinero: eso es de Finanzas.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: HomeModel
    @State private var showingNewOrder = false

    @ScaledMetric(relativeTo: .headline) private var warningIconSize: CGFloat = 36

    init(model: HomeModel = HomeModel()) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    header

                    if let errorMessage = model.errorMessage {
                        ErrorStateView(message: errorMessage) {
                            Task { await model.load() }
                        }
                        .padding(.vertical, Spacing.lg)
                    } else {
                        if !model.overdueOrders.isEmpty {
                            overdueBanner
                        }

                        nextOrderCard

                        thisWeekSection

                        if model.hasReviewItems {
                            toReviewSection
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
            .background(.canvasBackground)
            .refreshable {
                await model.load()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AddToolbarButton(label: "Nuevo pedido") {
                        showingNewOrder = true
                    }
                }
            }
            .sheet(isPresented: $showingNewOrder) {
                OrderFormView(order: nil) { _ in
                    Task {
                        await model.load()
                    }
                }
            }
            .task {
                await model.load()
            }
        }
    }

    // MARK: - Encabezado

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_MX"))).capitalized(with: Locale(identifier: "es_MX")))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.inkMuted)

            Text("Hola, \(session.me?.firstName ?? "")")
                .font(.largeTitle.weight(.heavy))
                .accessibilityAddTraits(.isHeader)

            Text(deliveriesSubtitle)
                .font(.body)
                .foregroundStyle(.inkMuted)
        }
    }

    private var deliveriesSubtitle: String {
        let count = model.deliveriesThisWeekCount
        if count == 0 {
            return "No tienes entregas esta semana."
        } else if count == 1 {
            return "Tienes 1 entrega esta semana."
        } else {
            return "Tienes \(count) entregas esta semana."
        }
    }

    // MARK: - Banner de atrasados

    private var overdueBanner: some View {
        Group {
            let count = model.overdueOrders.count
            let chipLabel = count == 1 ? "1 atrasado" : "\(count) atrasados"

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Chip(chipLabel, tone: .warning)
                    Text("Revísalos en Pedidos")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    Chip(chipLabel, tone: .warning)
                    Text("Revísalos en Pedidos")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    Spacer()
                }
            }
        }
    }

    // MARK: - "Lo que sigue"

    private var nextOrderCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let order = model.nextOrder {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Lo que sigue")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.accentTextDeep)
                        StatusChip(status: order.status)
                    }
                } else {
                    HStack {
                        Text("Lo que sigue")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.accentTextDeep)
                        Spacer()
                        StatusChip(status: order.status)
                    }
                }

                Text(formatDeliveryMoment(order.deliveryAt))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(order.customerName)
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                let cakesText = order.items.map { "\($0.recipeName) × \(Quantity.format($0.quantity))" }.joined(separator: " · ")
                if !cakesText.isEmpty {
                    Text(cakesText)
                        .font(.callout)
                        .foregroundStyle(.inkOnSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                NavigationLink {
                    OrderDetailView(
                        order: order,
                        onOrderUpdated: { _ in Task { await model.load() } },
                        onOrderDeleted: { _ in Task { await model.load() } }
                    )
                } label: {
                    Text("Ver pedido")
                        .font(.body.weight(.heavy))
                        .foregroundStyle(.inkPrimary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.surfaceCard, in: .rect(cornerRadius: Radius.control))
                }
                .buttonStyle(.plain)
            } else {
                Text("No tienes entregas pendientes.")
                    .font(.headline)
                    .foregroundStyle(.inkPrimary)

                Button {
                    showingNewOrder = true
                } label: {
                    Text("Anotar un pedido")
                        .font(.body.weight(.heavy))
                        .foregroundStyle(.inkPrimary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.surfaceCard, in: .rect(cornerRadius: Radius.control))
                }
                .buttonStyle(.plain)
            }
        }
        .softCard()
    }

    private func formatDeliveryMoment(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = OrderDateFormatter.timeString(for: date)
        if calendar.isDateInToday(date) {
            return "Hoy, \(time)"
        } else if calendar.isDateInTomorrow(date) {
            return "Mañana, \(time)"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_MX")
            formatter.timeZone = .current
            formatter.dateFormat = "EEEE d"
            let str = formatter.string(from: date)
            let capitalized = str.prefix(1).uppercased() + str.dropFirst()
            return "\(capitalized), \(time)"
        }
    }

    // MARK: - "Esta semana"

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Esta semana")
                .sectionTitleStyle()

            if model.remainingWeekOrders.isEmpty {
                Text("Nada más esta semana.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .padding(.vertical, Spacing.xs)
            } else {
                RowGroup {
                    ForEach(model.remainingWeekOrders) { order in
                        NavigationLink {
                            OrderDetailView(
                                order: order,
                                onOrderUpdated: { _ in Task { await model.load() } },
                                onOrderDeleted: { _ in Task { await model.load() } }
                            )
                        } label: {
                            OrderRow(order: order)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - "Por revisar"

    private var toReviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Por revisar")
                .sectionTitleStyle()

            RowGroup {
                ForEach(model.incompleteRecipes.prefix(3)) { item in
                    NavigationLink {
                        RecipeDetailView(recipeId: item.id)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            warningIconSquare

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(item.recipe.name)
                                    .font(.headline)
                                    .foregroundStyle(.inkPrimary)
                                    .multilineTextAlignment(.leading)
                                Text("Le faltan precios")
                                    .font(.subheadline)
                                    .foregroundStyle(.inkMuted)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(model.stalePresentations.prefix(3)) { stale in
                    HStack(spacing: Spacing.md) {
                        warningIconSquare

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("\(stale.presentation.ingredientName) · \(stale.presentation.brand)")
                                .font(.headline)
                                .foregroundStyle(.inkPrimary)
                                .multilineTextAlignment(.leading)

                            let daysText: String = {
                                if let days = stale.presentation.priceAgeDays {
                                    return "Precio de hace \(days) días"
                                } else {
                                    return "Precio viejo"
                                }
                            }()
                            Text(daysText)
                                .font(.subheadline)
                                .foregroundStyle(.inkMuted)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if model.incompleteRecipes.count > 3 {
                    HStack {
                        Text("Ver todas en Recetas")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tint)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var warningIconSquare: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.warningText)
            .frame(width: warningIconSize, height: warningIconSize)
            .background(.warningSoft, in: .rect(cornerRadius: Radius.control))
            .accessibilityHidden(true)
    }
}

// MARK: - Menú de Cuenta (Conservado)

/// Cuenta y cerrar sesión.
private struct AccountMenu: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Menu {
            if let me = session.me {
                Text(me.email)
            }
            Button("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await session.signOut() }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.title3)
        }
        .accessibilityLabel("Tu cuenta")
    }
}

// MARK: - Previews

#if DEBUG
private func makeMockOrder(
    id: String,
    customer: String,
    date: Date,
    status: OrderStatus,
    recipe: String,
    quantity: String
) -> Order {
    Order(
        id: id,
        customerName: customer,
        customerPhone: nil,
        deliveryAt: date,
        status: status,
        notes: nil,
        items: [
            OrderItem(recipeId: "r_1", recipeName: recipe, quantity: quantity, unitPriceCents: 0, unitCostCentsSnapshot: 0)
        ],
        payments: [],
        totalCents: 0,
        paidCents: 0,
        balanceCents: 0,
        costCents: 0,
        profitCents: 0,
        createdAt: Date(),
        updatedAt: Date()
    )
}

private func makeMockRecipeListItem(id: String, name: String, complete: Bool) -> RecipeListItem {
    let json = """
    {
        "id": "\(id)",
        "name": "\(name)",
        "description": null,
        "items": [],
        "extra_costs": [],
        "yield_quantity": "1",
        "yield_unit": "pz",
        "servings": 12,
        "margin_percent": 30,
        "created_at": "2026-10-01T12:00:00Z",
        "updated_at": "2026-10-01T12:00:00Z",
        "complete": \(complete)
    }
    """.data(using: .utf8)!
    return try! JSONCoding.decode(RecipeListItem.self, from: json)
}

private func makeMockStalePresentation(id: String, ingredient: String, brand: String, days: Int) -> StalePresentation {
    let json = """
    {
        "id": "\(id)",
        "ingredient_id": "ing_\(id)",
        "ingredient_name": "\(ingredient)",
        "brand": "\(brand)",
        "package_quantity": "1000",
        "base_unit": "g",
        "is_current": true,
        "price_age_days": \(days),
        "price_is_stale": true,
        "used_in_recipes": 1,
        "created_at": "2026-10-01T12:00:00Z",
        "updated_at": "2026-10-01T12:00:00Z"
    }
    """.data(using: .utf8)!
    return try! JSONCoding.decode(StalePresentation.self, from: json)
}

private let previewTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
private let previewIn3Days = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
private let previewYesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

private let mockHomeModelWithData = HomeModel(
    pendingOrders: [
        makeMockOrder(id: "o_1", customer: "María López", date: previewTomorrow, status: .pending, recipe: "Pastel de chocolate", quantity: "1"),
        makeMockOrder(id: "o_2", customer: "Carlos Ruiz", date: previewIn3Days, status: .pending, recipe: "Tres leches", quantity: "2")
    ],
    inProgressOrders: [],
    recipes: [
        makeMockRecipeListItem(id: "r_1", name: "Pastel de zanahoria", complete: false)
    ],
    stalePresentations: [
        makeMockStalePresentation(id: "sp_1", ingredient: "Harina de trigo", brand: "Selecta", days: 45)
    ]
)

private let mockHomeModelEmpty = HomeModel(
    pendingOrders: [],
    inProgressOrders: [],
    recipes: [],
    stalePresentations: []
)

private let mockHomeModelOverdue = HomeModel(
    pendingOrders: [
        makeMockOrder(id: "o_overdue", customer: "Ana Gómez", date: previewYesterday, status: .pending, recipe: "Pay de limón", quantity: "1"),
        makeMockOrder(id: "o_1", customer: "María López", date: previewTomorrow, status: .pending, recipe: "Pastel de chocolate", quantity: "1")
    ],
    inProgressOrders: [],
    recipes: [],
    stalePresentations: []
)

#Preview("Con pedidos y por revisar - Claro") {
    HomeView(model: mockHomeModelWithData)
        .environment(SessionStore())
}

#Preview("Sin pedidos - Claro") {
    HomeView(model: mockHomeModelEmpty)
        .environment(SessionStore())
}

#Preview("Con atrasados - Claro") {
    HomeView(model: mockHomeModelOverdue)
        .environment(SessionStore())
}

#Preview("Letra AX3") {
    HomeView(model: mockHomeModelWithData)
        .environment(SessionStore())
        .dynamicTypeSize(.accessibility3)
}
#endif
