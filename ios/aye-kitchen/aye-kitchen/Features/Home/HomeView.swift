import SwiftUI
import KitchenDomain

/// Inicio (artboard "Inicio — iPhone"). No muestra dinero: eso es de Finanzas.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: HomeModel
    @State private var showingNewOrder = false

    @ScaledMetric(relativeTo: .headline) private var warningIconSize: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var stepIconSize: CGFloat = 20

    init(store: LocalStore = .shared) {
        self._model = State(initialValue: HomeModel(store: store))
    }

    init(model: HomeModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    header

                    if !model.overdueOrders.isEmpty {
                        overdueBanner
                    }

                    if model.shouldShowFirstSteps {
                        firstStepsCard
                    }

                    nextOrderCard

                    thisWeekSection

                    if model.hasReviewItems {
                        toReviewSection
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
            .background(.canvasBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenu(store: model.store)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AddToolbarButton(label: "Nuevo pedido") {
                        showingNewOrder = true
                    }
                }
            }
            .sheet(isPresented: $showingNewOrder) {
                OrderFormView(.create, store: model.store)
            }
            .task(id: model.store.revision) {
                model.recalculateIfNeeded()
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

    // MARK: - "Primeros pasos" (Bloque I24)

    private var firstStepsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            firstStepsHeader

            FirstStepsProgressBar(
                completed: model.completedFirstStepsCount,
                total: model.firstSteps.count
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(model.firstSteps) { step in
                    firstStepRow(step)
                }
            }
        }
        .softCard()
    }

    @ViewBuilder
    private var firstStepsHeader: some View {
        let countText = "\(model.completedFirstStepsCount) de \(model.firstSteps.count)"

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Primeros pasos")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.accentTextDeep)

                Text(countText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.inkMuted)

                Button("Cerrar") {
                    withAnimation {
                        model.dismissFirstSteps()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .buttonStyle(.plain)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("Primeros pasos")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.accentTextDeep)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    Text(countText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.inkMuted)

                    Button("Cerrar") {
                        withAnimation {
                            model.dismissFirstSteps()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func firstStepRow(_ step: FirstSteps.Step) -> some View {
        if step.isDone {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.tint)
                    .frame(width: stepIconSize)
                    .accessibilityHidden(true)

                Text(step.title)
                    .font(.body)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(step.title), hecho")
        } else {
            Button {
                AppRouter.shared.selectedTab = step.tab
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    Image(systemName: "circle")
                        .font(.body)
                        .foregroundStyle(.inkMuted)
                        .frame(width: stepIconSize)
                        .accessibilityHidden(true)

                    Text(step.title)
                        .font(.body)
                        .foregroundStyle(.inkPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(step.title), pendiente")
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
                        OrderStatusChip(status: order.status)
                    }
                } else {
                    HStack {
                        Text("Lo que sigue")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.accentTextDeep)
                        Spacer()
                        OrderStatusChip(status: order.status)
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
                    OrderDetailView(orderId: order.id, store: model.store)
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

    private static let deliveryMomentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE d"
        return formatter
    }()

    private func formatDeliveryMoment(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = OrderDateFormatter.timeString(for: date)
        if calendar.isDateInToday(date) {
            return "Hoy, \(time)"
        } else if calendar.isDateInTomorrow(date) {
            return "Mañana, \(time)"
        } else {
            let str = Self.deliveryMomentFormatter.string(from: date)
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
                            OrderDetailView(orderId: order.id, store: model.store)
                        } label: {
                            OrderRow(orderId: order.id, store: model.store)
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
                        RecipeDetailView(recipeId: item.id, store: model.store)
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
                    NavigationLink {
                        BrandDetailView(presentationId: stale.presentation.id, store: model.store)
                    } label: {
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

// MARK: - Barra de progreso de Primeros pasos

/// Barra de progreso horizontal para "Primeros pasos" con tokens de diseño.
private struct FirstStepsProgressBar: View {
    let completed: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            let progress = total > 0 ? CGFloat(completed) / CGFloat(total) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.accentSoftTrack)
                    .frame(height: 6)

                Capsule()
                    .fill(.tint)
                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * progress)), height: 6)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Botón de Cuenta

/// Botón que abre Cuenta y ajustes (Bloque I21).
private struct AccountMenu: View {
    var store: LocalStore = .shared
    @State private var showingSettings = false

    var body: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.title3)
        }
        .accessibilityLabel("Tu cuenta")
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Con pedidos y por revisar - Claro") {
    HomeView(store: .preview())
        .environment(SessionStore())
}

#Preview("Primeros pasos — Negocio vacío") {
    HomeView(store: .preview(KitchenData.empty(deviceId: "preview")))
        .environment(SessionStore())
}

#Preview("Datos de ejemplo — Sin tarjeta") {
    var data = KitchenData.previewSample
    data.expenses = [
        Expense(
            id: "exp-preview",
            description: "Renta del taller",
            amountCents: 500000,
            spentAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
    return HomeView(store: .preview(data))
        .environment(SessionStore())
}

#Preview("Con atrasados - Claro") {
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    var data = KitchenData.previewSample
    data.orders.append(
        Order(
            id: "ord-overdue",
            customerName: "Ana Gómez",
            deliveryAt: yesterday,
            items: [
                OrderItem(
                    recipeId: "rec-pastel",
                    recipeName: "Pastel de vainilla",
                    quantity: "1",
                    unitPriceCents: 15000,
                    unitCostCentsSnapshot: 10000
                )
            ],
            status: .pendiente,
            createdAt: yesterday,
            updatedAt: yesterday
        )
    )
    return HomeView(store: .preview(data))
        .environment(SessionStore())
}

#Preview("Primeros pasos — Letra AX3") {
    HomeView(store: .preview(KitchenData.empty(deviceId: "preview")))
        .environment(SessionStore())
        .dynamicTypeSize(.accessibility3)
}
#endif
