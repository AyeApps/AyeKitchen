import SwiftUI
import KitchenDomain

/// Inicio (artboard "Inicio — iPhone"). No muestra dinero: eso es de Finanzas.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: HomeModel
    @State private var showingNewOrder = false

    @ScaledMetric(relativeTo: .headline) private var warningIconSize: CGFloat = 36

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
                    AccountMenu()
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

    private nonisolated(unsafe) static let deliveryMomentFormatter: DateFormatter = {
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

// MARK: - Menú de Cuenta (Conservado)

/// Cuenta y cerrar sesión.
private struct AccountMenu: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Menu {
            if let me = session.me {
                Text(me.email)
            }
            #if DEBUG
            Button("Copiar sesión (DEBUG)", systemImage: "doc.on.clipboard") {
                copySessionForScripts()
            }
            #endif
            Button("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await session.signOut() }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.title3)
        }
        .accessibilityLabel("Tu cuenta")
    }

    #if DEBUG
    /// Solo desarrollo: copia los tokens de la sesión como JSON (`access_token`, `refresh_token`)
    /// para que los scripts de prueba llamen a la API con esta cuenta. Con el portapapeles
    /// universal llega directo a la Mac (`pbpaste`). Nunca existe en builds de release.
    private func copySessionForScripts() {
        guard let tokens = KeychainStore.load() else { return }
        let payload = ["access_token": tokens.accessToken, "refresh_token": tokens.refreshToken]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = json
    }
    #endif
}

// MARK: - Previews

#if DEBUG
#Preview("Con pedidos y por revisar - Claro") {
    HomeView(store: .preview())
        .environment(SessionStore())
}

#Preview("Sin pedidos - Claro") {
    HomeView(store: .preview(KitchenData.empty(deviceId: "preview")))
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

#Preview("Letra AX3") {
    HomeView(store: .preview())
        .environment(SessionStore())
        .dynamicTypeSize(.accessibility3)
}
#endif
