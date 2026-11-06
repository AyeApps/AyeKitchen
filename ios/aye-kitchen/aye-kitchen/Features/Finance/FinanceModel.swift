import Foundation
import KitchenDomain
import Observation

/// Pestañas disponibles en la sección Finanzas.
enum FinanceTab: String, CaseIterable, Identifiable, Sendable {
    case month = "Mes"
    case recipes = "Recetas"

    var id: String { rawValue }
}

extension CostDashboardSortOrder {
    var label: String {
        switch self {
        case .needsReview: "Por revisar"
        case .suggestedProfit: "Mayor ganancia"
        case .batchCost: "Mayor costo"
        case .name: "Nombre"
        }
    }
}

/// Modelo de presentación para la pestaña Finanzas (MVVM, Bloque I22 local-first).
@Observable
final class FinanceModel {
    let store: LocalStore

    var selectedTab: FinanceTab = .month
    var selectedYear: Int
    var selectedMonth: Int

    var recipeDashboardSort: CostDashboardSortOrder = .needsReview

    private var cachedDashboard: CostDashboard?
    private var cachedRevision: Int = -1
    private var cachedSort: CostDashboardSortOrder = .needsReview

    init(store: LocalStore = .shared) {
        self.store = store
        let now = Date()
        let cal = Calendar.current
        self.selectedYear = cal.component(.year, from: now)
        self.selectedMonth = cal.component(.month, from: now)
    }

    // MARK: - Navegación de Mes

    /// No permite navegar a meses futuros con respecto al calendario actual.
    var canGoToNextMonth: Bool {
        let now = Date()
        let cal = Calendar.current
        let curYear = cal.component(.year, from: now)
        let curMonth = cal.component(.month, from: now)
        if selectedYear < curYear { return true }
        if selectedYear == curYear { return selectedMonth < curMonth }
        return false
    }

    func previousMonth() {
        if selectedMonth == 1 {
            if selectedYear > 2000 {
                selectedYear -= 1
                selectedMonth = 12
            }
        } else {
            selectedMonth -= 1
        }
    }

    func nextMonth() {
        guard canGoToNextMonth else { return }
        if selectedMonth == 12 {
            selectedYear += 1
            selectedMonth = 1
        } else {
            selectedMonth += 1
        }
    }

    /// Título formateado del mes seleccionado ("noviembre 2026").
    var monthTitle: String {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        if let date = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_MX")
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        return "\(selectedMonth)/\(selectedYear)"
    }

    // MARK: - Resumen Mensual

    var summary: SummaryMonthly {
        (try? store.data.monthlySummary(year: selectedYear, month: selectedMonth))
            ?? SummaryMonthly(
                year: selectedYear,
                month: selectedMonth,
                incomeCents: 0,
                expensesCents: 0,
                netCents: 0,
                ordersDelivered: 0,
                ordersPending: 0,
                salesCents: 0,
                estimatedProfitCents: 0,
                receivableCents: 0
            )
    }

    // MARK: - Gastos del Mes

    private func monthBounds(year: Int, month: Int) -> (start: Date, end: Date)? {
        let tz = TimeZone(identifier: store.data.settings.timezone)
            ?? TimeZone(identifier: "America/Mexico_City")
            ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let startComponents = DateComponents(year: year, month: month, day: 1, hour: 0, minute: 0, second: 0)
        let nextYear = (month == 12) ? year + 1 : year
        let nextMonth = (month == 12) ? 1 : month + 1
        let endComponents = DateComponents(year: nextYear, month: nextMonth, day: 1, hour: 0, minute: 0, second: 0)

        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(from: endComponents) else {
            return nil
        }
        return (start, end)
    }

    /// Lista de gastos activos del mes seleccionado, ordenados del más reciente al más antiguo.
    var monthlyExpenses: [Expense] {
        guard let bounds = monthBounds(year: selectedYear, month: selectedMonth) else {
            return []
        }
        return store.data.expenses
            .filter { $0.isActive && $0.spentAt >= bounds.start && $0.spentAt < bounds.end }
            .sorted { a, b in
                if a.spentAt != b.spentAt {
                    return a.spentAt > b.spentAt
                }
                if a.createdAt != b.createdAt {
                    return a.createdAt > b.createdAt
                }
                return a.id > b.id
            }
    }

    func supplierName(id: String?) -> String? {
        guard let id else { return nil }
        return store.data.suppliers.first(where: { $0.id == id && $0.isActive })?.name
    }

    func deleteExpense(id: String) throws {
        try store.mutate { data, ctx in
            try data.deleteExpense(id: id, ctx: ctx)
        }
    }

    // MARK: - Tablero de Recetas (K3)

    /// Tablero de costos de recetas recalculado únicamente cuando cambia `store.revision` o el orden.
    var recipeDashboard: CostDashboard {
        if let cached = cachedDashboard,
           cachedRevision == store.revision,
           cachedSort == recipeDashboardSort {
            return cached
        }
        let dashboard = store.data.costDashboard(order: recipeDashboardSort, now: Date())
        cachedDashboard = dashboard
        cachedRevision = store.revision
        cachedSort = recipeDashboardSort
        return dashboard
    }

    func setSortOrder(_ sort: CostDashboardSortOrder) {
        recipeDashboardSort = sort
    }
}
