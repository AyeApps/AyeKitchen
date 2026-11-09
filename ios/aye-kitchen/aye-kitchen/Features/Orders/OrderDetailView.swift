import SwiftUI
import KitchenDomain

/// Detalle del pedido (Bloque I18 local-first).
struct OrderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconBoxSize: CGFloat = 40

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
                        batchNeedsSection(order: order)
                        financialSummaryCard(order: order)
                        paymentsSection(order: order)
                        notesSection(order: order)
                        ReferencesSection(owner: .order(order.id), store: model.store)
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

    // MARK: - Para este pedido

    @ViewBuilder
    private func batchNeedsSection(order: Order) -> some View {
        let needs = model.batchNeeds
        if !needs.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Para este pedido")
                    .sectionTitleStyle()

                RowGroup {
                    ForEach(needs) { need in
                        batchNeedRow(need: need)
                    }
                }
            }
        }
    }

    private func batchNeedRow(need: BatchNeed) -> some View {
        let leftoverDec = Qty.decimal(need.leftoverUnits) ?? 0
        let isZeroLeftover = (leftoverDec == 0)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        batchNeedIcon
                        Text(need.recipeName)
                            .font(.body.weight(.bold))
                            .foregroundStyle(.inkPrimary)
                    }

                    if isZeroLeftover {
                        let batchWord = need.wholeBatches == 1 ? "tanda" : "tandas"
                        Text("Haz \(need.wholeBatches) \(batchWord)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.inkPrimary)
                            .monospacedDigit()
                    } else {
                        let exactFormatted = Quantity.format(need.exactBatches)
                        let batchWord = (need.exactBatches == "1" || need.exactBatches == "1.0") ? "tanda" : "tandas"
                        Text("Necesitas \(exactFormatted) \(batchWord)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.inkPrimary)
                            .monospacedDigit()

                        Text(leftoverDescription(for: need))
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .monospacedDigit()
                    }
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.md) {
                    batchNeedIcon

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if isZeroLeftover {
                            let batchWord = need.wholeBatches == 1 ? "tanda" : "tandas"
                            Text("Haz \(need.wholeBatches) \(batchWord) de \(need.recipeName)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.inkPrimary)
                                .monospacedDigit()
                        } else {
                            let exactFormatted = Quantity.format(need.exactBatches)
                            let batchWord = (need.exactBatches == "1" || need.exactBatches == "1.0") ? "tanda" : "tandas"
                            Text("Necesitas \(exactFormatted) \(batchWord) de \(need.recipeName)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.inkPrimary)
                                .monospacedDigit()

                            Text(leftoverDescription(for: need))
                                .font(.subheadline)
                                .foregroundStyle(.inkMuted)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(batchNeedAccessibilityLabel(for: need, isZeroLeftover: isZeroLeftover))
    }

    private var batchNeedIcon: some View {
        Image(systemName: "fork.knife")
            .font(.body.weight(.bold))
            .foregroundStyle(.accentTextDeep)
            .frame(width: iconBoxSize, height: iconBoxSize)
            .background(Color.accentSoftStrong, in: .rect(cornerRadius: Radius.control))
            .accessibilityHidden(true)
    }

    private func leftoverDescription(for need: BatchNeed) -> String {
        let unitWord = leftoverUnitWord(for: need)
        let formattedLeftover = Quantity.format(need.leftoverUnits)
        let valueText: String
        if let cents = need.leftoverValueCents {
            valueText = " (unos \(Money.format(cents: cents)))"
        } else {
            valueText = ""
        }
        return "Si haces \(need.wholeBatches), te sobran \(formattedLeftover) \(unitWord) para vender\(valueText)"
    }

    private func leftoverUnitWord(for need: BatchNeed) -> String {
        let clean = need.leftoverUnits.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let isSingular = (clean == "1" || clean == "1.0" || clean == "1.00" || clean == "1.000")
        switch need.yieldUnit {
        case .pz:
            return isSingular ? "pieza" : "piezas"
        case .g:
            return "g"
        case .ml:
            return "ml"
        }
    }

    private func batchNeedAccessibilityLabel(for need: BatchNeed, isZeroLeftover: Bool) -> String {
        if isZeroLeftover {
            let batchWord = need.wholeBatches == 1 ? "tanda" : "tandas"
            return "Haz \(need.wholeBatches) \(batchWord) de \(need.recipeName)"
        } else {
            let exactFormatted = Quantity.format(need.exactBatches)
            let batchWord = (need.exactBatches == "1" || need.exactBatches == "1.0") ? "tanda" : "tandas"
            let unitWord = leftoverUnitWord(for: need)
            let formattedLeftover = Quantity.format(need.leftoverUnits)
            let valueText: String
            if let cents = need.leftoverValueCents {
                valueText = ", unos \(Money.format(cents: cents))"
            } else {
                valueText = ""
            }
            return "Necesitas \(exactFormatted) \(batchWord) de \(need.recipeName). Si haces \(need.wholeBatches), te sobran \(formattedLeftover) \(unitWord) para vender\(valueText)"
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.inkPrimary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Ya te pagaron")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.paidCents))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.inkPrimary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Te falta cobrar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.inkMuted)
                        Text(Money.format(cents: totals.balanceCents))
                            .font(.title2.weight(.heavy))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(totals.balanceCents > 0 ? Color.accentColor : Color.inkPrimary)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Total")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.inkMuted)
                            Text(Money.format(cents: totals.totalCents))
                                .font(.title3.weight(.heavy))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(totals.balanceCents > 0 ? Color.accentColor : Color.inkPrimary)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Total")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.inkMuted)
                            Text(Money.format(cents: totals.totalCents))
                                .font(.title2.weight(.heavy))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(.inkPrimary)
                        }

                        HStack(alignment: .top, spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Ya te pagaron")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.inkMuted)
                                Text(Money.format(cents: totals.paidCents))
                                    .font(.body.weight(.bold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(totals.balanceCents > 0 ? Color.accentColor : Color.inkPrimary)
                            }
                        }
                    }
                }
            }

            Rectangle()
                .fill(.dividerLine)
                .frame(height: 1)

            if totals.profitCents < 0 {
                Text("Te cuesta \(Money.format(cents: totals.costCents)) · Pierdes \(Money.format(cents: abs(totals.profitCents)))")
                    .font(.subheadline)
                    .foregroundStyle(.warningText)
                    .monospacedDigit()
            } else if let pct = totals.profitPercent {
                Text("Te cuesta \(Money.format(cents: totals.costCents)) · Ganas \(Money.format(cents: totals.profitCents)) (\(pct) %)")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .monospacedDigit()
            } else {
                Text("Te cuesta \(Money.format(cents: totals.costCents)) · Ganas \(Money.format(cents: totals.profitCents))")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .monospacedDigit()
            }
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
private enum PreviewOrderScenario {
    case onePointFiveBatches
    case exactBatches
    case loss
}

private func makeOrderPreviewStore(scenario: PreviewOrderScenario) -> LocalStore {
    var data = KitchenData.previewSample

    switch scenario {
    case .onePointFiveBatches:
        let recipe10 = Recipe(
            id: "rec-preview-10",
            name: "Galletas de avena",
            items: [RecipeItem(kind: .ingredient, refId: "ing-harina", quantity: "200")],
            yieldQuantity: "10",
            yieldUnit: .pz,
            servings: 10,
            salePriceCents: 1500,
            salePriceSoldBy: .unit,
            createdAt: Date(),
            updatedAt: Date()
        )
        let order15 = Order(
            id: "ord-preview-1-5",
            customerId: "cus-ana",
            customerName: "Ana López",
            deliveryAt: Date().addingTimeInterval(86400),
            items: [
                OrderItem(
                    recipeId: recipe10.id,
                    recipeName: recipe10.name,
                    soldBy: .unit,
                    unitLabel: .pz,
                    quantity: "15",
                    unitPriceCents: 1500,
                    unitCostCentsSnapshot: 990
                )
            ],
            createdAt: Date(),
            updatedAt: Date()
        )
        data.recipes.append(recipe10)
        data.orders.append(order15)

    case .exactBatches:
        let order18 = Order(
            id: "ord-preview-18",
            customerId: "cus-ana",
            customerName: "Ana López",
            deliveryAt: Date().addingTimeInterval(86400),
            items: [
                OrderItem(
                    recipeId: "rec-pastel",
                    recipeName: "Pastel de vainilla",
                    soldBy: .batch,
                    quantity: "18",
                    unitPriceCents: 16618,
                    unitCostCentsSnapshot: 11870
                )
            ],
            createdAt: Date(),
            updatedAt: Date()
        )
        data.orders.append(order18)

    case .loss:
        let orderLoss = Order(
            id: "ord-preview-loss",
            customerId: "cus-ana",
            customerName: "Ana López",
            deliveryAt: Date().addingTimeInterval(86400),
            items: [
                OrderItem(
                    recipeId: "rec-pastel",
                    recipeName: "Pastel de vainilla",
                    soldBy: .batch,
                    quantity: "1",
                    unitPriceCents: 5000,
                    unitCostCentsSnapshot: 11870
                )
            ],
            createdAt: Date(),
            updatedAt: Date()
        )
        data.orders.append(orderLoss)
    }

    return LocalStore.preview(data)
}

#Preview("Pedido con 1.5 tandas") {
    NavigationStack {
        OrderDetailView(orderId: "ord-preview-1-5", store: makeOrderPreviewStore(scenario: .onePointFiveBatches))
    }
}

#Preview("Pedido con tandas exactas") {
    NavigationStack {
        OrderDetailView(orderId: "ord-preview-18", store: makeOrderPreviewStore(scenario: .exactBatches))
    }
}

#Preview("Pedido con pérdida") {
    NavigationStack {
        OrderDetailView(orderId: "ord-preview-loss", store: makeOrderPreviewStore(scenario: .loss))
    }
}

#Preview("Detalle con pago parcial — ord-1") {
    NavigationStack {
        OrderDetailView(orderId: "ord-1", store: .preview())
    }
}

#Preview("Detalle AX3 (1.5 tandas)") {
    NavigationStack {
        OrderDetailView(orderId: "ord-preview-1-5", store: makeOrderPreviewStore(scenario: .onePointFiveBatches))
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
