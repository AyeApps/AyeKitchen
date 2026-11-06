import SwiftUI
import KitchenDomain

/// Pestaña principal de Finanzas: gastos, ganancias del mes y costos de recetas (Bloque I22 local-first).
struct FinanceView: View {
    @State private var model: FinanceModel
    private let store: LocalStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingNewExpense = false
    @State private var expenseToEdit: Expense?
    @State private var expenseToDelete: Expense?
    @State private var showingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    init(store: LocalStore = .shared) {
        self.store = store
        self._model = State(initialValue: FinanceModel(store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.md)

                if model.selectedTab == .month {
                    monthView
                } else {
                    RecipeCostDashboardView(model: model, store: store)
                }
            }
            .background(.canvasBackground)
            .navigationTitle("Finanzas")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if model.selectedTab == .month {
                    ToolbarItem(placement: .topBarTrailing) {
                        AddToolbarButton(label: "Agregar gasto") {
                            showingNewExpense = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewExpense) {
                ExpenseFormView(store: store)
            }
            .sheet(item: $expenseToEdit) { expense in
                ExpenseFormView(expense: expense, store: store)
            }
            .confirmationDialog(
                "¿Borrar este gasto?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Borrar gasto", role: .destructive) {
                    if let exp = expenseToDelete {
                        do {
                            try model.deleteExpense(id: exp.id)
                            expenseToDelete = nil
                        } catch {
                            deleteErrorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancelar", role: .cancel) {
                    expenseToDelete = nil
                }
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
            .alert("No se pudo borrar el gasto", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("Aceptar", role: .cancel) {
                    deleteErrorMessage = nil
                }
            } message: {
                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                }
            }
        }
    }

    // MARK: - Encabezado

    private var headerView: some View {
        VStack(spacing: Spacing.md) {
            monthSelector
            tabPicker
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                model.previousMonth()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.bold))
                }
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Mes anterior")

            Spacer()

            Text(model.monthTitle)
                .font(.headline)
                .foregroundStyle(.inkPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                model.nextMonth()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.bold))
                }
                .foregroundStyle(model.canGoToNextMonth ? Color.accentColor : Color.inkMuted)
                .frame(width: 44, height: 44)
            }
            .disabled(!model.canGoToNextMonth)
            .accessibilityLabel("Mes siguiente")
        }
    }

    private var tabPicker: some View {
        Picker("Vista de Finanzas", selection: $model.selectedTab) {
            ForEach(FinanceTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Vista del Mes

    private var monthView: some View {
        List {
            Section {
                mainCard
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.xl, bottom: Spacing.lg, trailing: Spacing.xl))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                statsSection
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.xl, bottom: Spacing.section, trailing: Spacing.xl))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                if model.monthlyExpenses.isEmpty {
                    emptyExpensesView
                        .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.xl, bottom: Spacing.md, trailing: Spacing.xl))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.monthlyExpenses) { expense in
                        ExpenseRow(expense: expense, model: model)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                expenseToEdit = expense
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    expenseToDelete = expense
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Borrar", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                expensesHeader
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.xl, bottom: Spacing.sm, trailing: Spacing.xl))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Tarjeta Principal

    private var mainCard: some View {
        let summary = model.summary

        return VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Te quedó")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.inkMuted)

                Text(Money.format(cents: summary.netCents))
                    .font(.largeTitle.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            }

            Rectangle()
                .fill(.dividerLine)
                .frame(height: 1)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    cobrasteView(cents: summary.incomeCents)
                    gastasteView(cents: summary.expensesCents)
                }
            } else {
                HStack(spacing: Spacing.xl) {
                    cobrasteView(cents: summary.incomeCents)
                    Spacer()
                    gastasteView(cents: summary.expensesCents)
                    Spacer()
                }
            }
        }
        .softCard()
    }

    private func cobrasteView(cents: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Cobraste")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)

            Text(Money.format(cents: cents))
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.inkPrimary)
        }
    }

    private func gastasteView(cents: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Gastaste")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)

            Text(Money.format(cents: cents))
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.inkPrimary)
        }
    }

    // MARK: - Fila de Datos

    private var statsSection: some View {
        let summary = model.summary

        return RowGroup {
            statRow(
                title: "Vendiste",
                subtitle: summary.ordersDelivered == 1 ? "1 pedido entregado" : "\(summary.ordersDelivered) pedidos entregados",
                amountCents: summary.salesCents
            )

            statRow(
                title: "Ganancia estimada",
                subtitle: nil,
                amountCents: summary.estimatedProfitCents
            )

            statRow(
                title: "Por cobrar",
                subtitle: summary.ordersPending == 1 ? "1 pedido pendiente" : "\(summary.ordersPending) pedidos pendientes",
                amountCents: summary.receivableCents
            )

            pedidosStatRow(summary: summary)
        }
    }

    private func statRow(title: String, subtitle: String?, amountCents: Int) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.inkPrimary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                    }

                    Text(Money.format(cents: amountCents))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)
                }
            } else {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.inkPrimary)

                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.inkMuted)
                        }
                    }

                    Spacer()

                    Text(Money.format(cents: amountCents))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func pedidosStatRow(summary: SummaryMonthly) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Pedidos del mes")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.inkPrimary)

                    Text("\(summary.ordersDelivered) entregados · \(summary.ordersPending) pendientes")
                        .font(.subheadline)
                        .foregroundStyle(.inkSecondary)
                }
            } else {
                HStack {
                    Text("Pedidos del mes")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.inkPrimary)

                    Spacer()

                    Text("\(summary.ordersDelivered) entregados · \(summary.ordersPending) pendientes")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.inkSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Sección de Gastos

    private var expensesHeader: some View {
        HStack {
            Text("Gastos del mes")
                .sectionTitleStyle()

            Spacer()

            Button {
                showingNewExpense = true
            } label: {
                Label("Agregar gasto", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyExpensesView: some View {
        VStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: "cart")
                .font(.system(size: 36))
                .foregroundStyle(.inkMuted)

            Text("Todavía no registras gastos este mes. Agrega lo que compras para ver cuánto te queda.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .multilineTextAlignment(.center)

            Button {
                showingNewExpense = true
            } label: {
                Label("Agregar gasto", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.accentInk)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(.accentFill, in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Fila de Gasto

struct ExpenseRow: View {
    let expense: Expense
    let model: FinanceModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let expenseDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "d 'de' MMMM"
        return f
    }()

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(expense.description)
                        .font(.headline)
                        .foregroundStyle(.inkPrimary)

                    subtitle

                    Text(Money.format(cents: expense.amountCents))
                        .font(.headline.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(expense.description)
                            .font(.headline)
                            .foregroundStyle(.inkPrimary)

                        subtitle
                    }

                    Spacer()

                    Text(Money.format(cents: expense.amountCents))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.inkPrimary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var subtitle: some View {
        HStack(spacing: Spacing.xs) {
            Text(expenseDateFormatter.string(from: expense.spentAt))

            if let cat = expense.category, !cat.isEmpty {
                Text("·")
                Text(cat)
            }

            if let supName = model.supplierName(id: expense.supplierId) {
                Text("·")
                Text(supName)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.inkMuted)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Finanzas — Normal") {
    let store = LocalStore.preview()
    let now = Date()
    _ = try? store.mutate { data, ctx in
        try data.createExpense(
            description: "Harina bulto 25 kg",
            amountCents: 45000,
            spentAt: now,
            category: "Insumos",
            supplierId: "sup-costco",
            ctx: ctx
        )
        try data.createExpense(
            description: "Cajas y listón",
            amountCents: 12000,
            spentAt: now,
            category: "Empaque",
            ctx: ctx
        )
    }
    return FinanceView(store: store)
}

#Preview("Finanzas — AX3") {
    let store = LocalStore.preview()
    let now = Date()
    _ = try? store.mutate { data, ctx in
        try data.createExpense(
            description: "Harina bulto 25 kg",
            amountCents: 45000,
            spentAt: now,
            category: "Insumos",
            supplierId: "sup-costco",
            ctx: ctx
        )
    }
    return FinanceView(store: store)
        .dynamicTypeSize(.accessibility3)
}
#endif
