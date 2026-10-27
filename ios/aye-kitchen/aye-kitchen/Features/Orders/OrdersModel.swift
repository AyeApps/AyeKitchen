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
    let orders: [Order]
}

/// Modelo de presentación para la lista de pedidos (MVVM, Regla 5).
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

    private var pendingAndInProgressOrders: [Order] = []
    private var deliveredOrders: [Order] = []
    private var hasLoadedPending = false
    private var hasLoadedDelivered = false

    var isEmpty: Bool {
        sections.isEmpty
    }

    init(mockOrders: [Order]? = nil) {
        if let mockOrders {
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
        state = .loading
        do {
            switch filter {
            case .pendingAndInProgress:
                try await fetchPendingAndInProgress()
            case .delivered:
                try await fetchDelivered()
            }
            rebuildSections()
            state = .loaded
        } catch {
            state = .error(error.localizedDescription)
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
                await load()
            }
        }
    }

    /// Dos peticiones en paralelo para "Por entregar":
    /// GET /orders/?status=pendiente&limit=100 y GET /orders/?status=en_proceso&limit=100
    private func fetchPendingAndInProgress() async throws {
        async let pendingRequest: Page<Order> = NetworkService.shared.request(
            .get,
            "/orders/",
            query: [
                URLQueryItem(name: "status", value: OrderStatus.pending.rawValue),
                URLQueryItem(name: "limit", value: "100")
            ]
        )

        async let inProgressRequest: Page<Order> = NetworkService.shared.request(
            .get,
            "/orders/",
            query: [
                URLQueryItem(name: "status", value: OrderStatus.inProgress.rawValue),
                URLQueryItem(name: "limit", value: "100")
            ]
        )

        let (pendingPage, inProgressPage) = try await (pendingRequest, inProgressRequest)
        self.pendingAndInProgressOrders = pendingPage.items + inProgressPage.items
        self.hasLoadedPending = true
    }

    /// Petición para "Entregados":
    /// GET /orders/?status=entregado&from=<hace 30 días>&limit=100
    private func fetchDelivered() async throws {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date.now) ?? Date.now.addingTimeInterval(-30 * 86400)
        let fromString = ISO8601DateFormatter().string(from: thirtyDaysAgo)

        let page: Page<Order> = try await NetworkService.shared.request(
            .get,
            "/orders/",
            query: [
                URLQueryItem(name: "status", value: OrderStatus.delivered.rawValue),
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
    func updateOrder(_ order: Order) {
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
