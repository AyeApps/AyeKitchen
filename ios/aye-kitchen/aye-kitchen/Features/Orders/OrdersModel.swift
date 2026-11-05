import Foundation
import SwiftUI

/// Filtro del selector segmentado de pedidos.
enum OrdersFilter: String, CaseIterable, Identifiable, Sendable {
    case pendingAndInProgress = "por_entregar"
    case delivered = "entregados"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pendingAndInProgress: "Por entregar"
        case .delivered: "Entregados"
        }
    }
}

/// Estado de carga de la lista de pedidos.
enum OrdersLoadingState: Equatable, Sendable {
    case loading
    case loaded
    case error(String)
}

/// Sección de pedidos agrupados por día de entrega o atrasados.
struct OrderSection: Identifiable, Sendable {
    let id: String
    let title: String
    let orders: [RemoteOrder]
}

/// Modelo de presentación para la lista de pedidos (MVVM, Regla 5 / Bloque I13).
@Observable
final class OrdersModel {
    var filter: OrdersFilter = .pendingAndInProgress {
        didSet {
            if filter != oldValue {
                rebuildSections()
                Task { await loadCurrentFilterIfNeeded() }
            }
        }
    }

    var state: OrdersLoadingState = .loading
    private(set) var sections: [OrderSection] = []

    private var pendingAndInProgressOrders: [RemoteOrder] = []
    private var deliveredOrders: [RemoteOrder] = []
    private var hasLoadedPending = false
    private var hasLoadedDelivered = false
    private(set) var isMock: Bool = false

    private let pendingQuery = [
        URLQueryItem(name: "status", value: RemoteOrderStatus.pending.rawValue),
        URLQueryItem(name: "limit", value: "100")
    ]
    private let inProgressQuery = [
        URLQueryItem(name: "status", value: RemoteOrderStatus.inProgress.rawValue),
        URLQueryItem(name: "limit", value: "100")
    ]

    var isEmpty: Bool {
        sections.isEmpty
    }

    init(mockOrders: [RemoteOrder]? = nil) {
        if let mockOrders {
            self.isMock = true
            self.state = .loaded
            self.pendingAndInProgressOrders = mockOrders.filter { $0.status == .pending || $0.status == .inProgress }
            self.deliveredOrders = mockOrders.filter { $0.status == .delivered }
            self.hasLoadedPending = true
            self.hasLoadedDelivered = true
            rebuildSections()
        }
    }

    /// Carga los pedidos del filtro actual y actualiza las secciones.
    func load() async {
        guard !isMock else { return }
        if hasLoadedPending {
            await reloadIfStale()
        } else {
            if await loadFromCache() {
                await reloadIfStale()
            } else {
                state = .loading
                await forceReload()
            }
        }
    }

    func refresh() async {
        await forceReload()
    }

    func forceReload() async {
        guard !isMock else { return }
        await ChangeTracker.shared.forceReload(.orders) {
            await self.reloadSilently()
        }
    }

    func reloadIfStale() async {
        guard !isMock else { return }
        await ChangeTracker.shared.reloadIfStale(.orders) {
            await self.reloadSilently()
        }
    }

    private func loadCurrentFilterIfNeeded() async {
        switch filter {
        case .pendingAndInProgress:
            if !hasLoadedPending {
                await load()
            }
        case .delivered:
            if !hasLoadedDelivered {
                state = .loading
                do {
                    try await fetchDelivered()
                    rebuildSections()
                    state = .loaded
                } catch where error.isCancellation {
                    if hasLoadedPending {
                        state = .loaded
                    }
                } catch {
                    if !hasLoadedDelivered {
                        state = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Lee la copia guardada en disco de la primera pantalla ("Por entregar").
    private func loadFromCache() async -> Bool {
        guard !isMock else { return true }
        async let cachedPending: Page<RemoteOrder>? = NetworkService.shared.cached("/orders/", query: pendingQuery)
        async let cachedInProgress: Page<RemoteOrder>? = NetworkService.shared.cached("/orders/", query: inProgressQuery)

        let (pendingPage, inProgressPage) = await (cachedPending, cachedInProgress)
        guard let pendingPage, let inProgressPage else {
            return false
        }

        self.pendingAndInProgressOrders = pendingPage.items + inProgressPage.items
        self.hasLoadedPending = true
        rebuildSections()
        self.state = .loaded
        return true
    }

    /// Recarga en silencio sin pasar por estado de carga. Guarda las respuestas en disco con requestCaching.
    @discardableResult
    func reloadSilently() async -> Bool {
        guard !isMock else { return true }
        do {
            async let pendingRequest: Page<RemoteOrder> = NetworkService.shared.requestCaching(
                "/orders/",
                query: pendingQuery
            )

            async let inProgressRequest: Page<RemoteOrder> = NetworkService.shared.requestCaching(
                "/orders/",
                query: inProgressQuery
            )

            let (pendingPage, inProgressPage) = try await (pendingRequest, inProgressRequest)
            self.pendingAndInProgressOrders = pendingPage.items + inProgressPage.items
            self.hasLoadedPending = true

            if filter == .delivered {
                try await fetchDelivered()
            }

            rebuildSections()
            self.state = .loaded
            return true
        } catch where error.isCancellation {
            let hasData = filter == .delivered ? hasLoadedDelivered : hasLoadedPending
            if hasData {
                self.state = .loaded
            }
            return false
        } catch {
            let hasData = filter == .delivered ? hasLoadedDelivered : hasLoadedPending
            if !hasData {
                self.state = .error(error.localizedDescription)
            }
            return false
        }
    }

    /// Petición para "Entregados" (filtro secundario, sigue con request estándar):
    /// GET /orders/?status=entregado&from=<hace 30 días>&limit=100
    private func fetchDelivered() async throws {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date.now) ?? Date.now.addingTimeInterval(-30 * 86400)
        let fromString = ISO8601DateFormatter().string(from: thirtyDaysAgo)

        let page: Page<RemoteOrder> = try await NetworkService.shared.request(
            .get,
            "/orders/",
            query: [
                URLQueryItem(name: "status", value: RemoteOrderStatus.delivered.rawValue),
                URLQueryItem(name: "from", value: fromString),
                URLQueryItem(name: "limit", value: "100")
            ]
        )
        self.deliveredOrders = page.items
        self.hasLoadedDelivered = true
    }

    /// Construye las secciones con la lógica requerida:
    /// - "Por entregar": Atrasados primero (delivery_at < now), luego secciones por día ordenadas cronológicamente.
    /// - "Entregados": Ordenados del más reciente al más viejo, agrupados por día de entrega.
    func rebuildSections() {
        let calendar = Calendar.current
        var result: [OrderSection] = []

        switch filter {
        case .pendingAndInProgress:
            let sorted = pendingAndInProgressOrders.sorted { $0.deliveryAt < $1.deliveryAt }
            let now = Date.now

            // Atrasados: ya pasaron su fecha
            let overdue = sorted.filter { $0.deliveryAt < now }
            if !overdue.isEmpty {
                result.append(OrderSection(id: "atrasados", title: "Atrasados", orders: overdue))
            }

            // Próximos: por día de entrega
            let upcoming = sorted.filter { $0.deliveryAt >= now }
            let grouped = Dictionary(grouping: upcoming) { order in
                calendar.startOfDay(for: order.deliveryAt)
            }
            let sortedDays = grouped.keys.sorted()
            for day in sortedDays {
                let dayOrders = grouped[day]!.sorted { $0.deliveryAt < $1.deliveryAt }
                let title = OrderDateFormatter.dayHeader(for: day)
                result.append(OrderSection(id: "\(day.timeIntervalSince1970)", title: title, orders: dayOrders))
            }

        case .delivered:
            let sorted = deliveredOrders.sorted { $0.deliveryAt > $1.deliveryAt }
            let grouped = Dictionary(grouping: sorted) { order in
                calendar.startOfDay(for: order.deliveryAt)
            }
            let sortedDays = grouped.keys.sorted(by: >)
            for day in sortedDays {
                let dayOrders = grouped[day]!.sorted { $0.deliveryAt > $1.deliveryAt }
                let title = OrderDateFormatter.dayHeader(for: day)
                result.append(OrderSection(id: "\(day.timeIntervalSince1970)", title: title, orders: dayOrders))
            }
        }

        self.sections = result
    }

    /// Actualiza o inserta un pedido guardado localmente para respuesta instantánea.
    func updateOrder(_ order: RemoteOrder) {
        pendingAndInProgressOrders.removeAll { $0.id == order.id }
        deliveredOrders.removeAll { $0.id == order.id }

        switch order.status {
        case .pending, .inProgress:
            pendingAndInProgressOrders.append(order)
        case .delivered:
            deliveredOrders.append(order)
        case .cancelled:
            break
        }

        rebuildSections()
    }

    /// Remueve un pedido borrado localmente.
    func removeOrder(id: String) {
        pendingAndInProgressOrders.removeAll { $0.id == id }
        deliveredOrders.removeAll { $0.id == id }
        rebuildSections()
    }
}
