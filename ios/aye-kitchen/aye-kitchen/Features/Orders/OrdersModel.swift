import Foundation
import SwiftUI
import KitchenDomain
import Observation

/// Filtro del selector segmentado de pedidos (Bloque I18 local-first).
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

/// Sección de pedidos agrupados por día de entrega o atrasados (Bloque I18 local-first).
struct OrderSection: Identifiable, Sendable {
    let id: String
    let title: String
    let orders: [Order]
}

/// Modelo de presentación para la lista de pedidos (MVVM, Regla 5 / Bloque I18 local-first).
@Observable
final class OrdersModel {
    var store: LocalStore
    var filter: OrdersFilter = .pendingAndInProgress

    init(store: LocalStore = .shared) {
        self.store = store
    }

    var isEmpty: Bool {
        sections.isEmpty
    }

    /// Construye las secciones desde KitchenData en LocalStore:
    /// - "Por entregar": Atrasados primero (deliveryAt < now), luego secciones por día ordenadas cronológicamente.
    /// - "Entregados": Últimos 30 días, ordenados del más reciente al más viejo, agrupados por día de entrega.
    var sections: [OrderSection] {
        let calendar = Calendar.current
        let now = Date.now
        var result: [OrderSection] = []

        switch filter {
        case .pendingAndInProgress:
            let allPending = store.data.orders.filter {
                $0.isActive && ($0.status == .pendiente || $0.status == .enProceso)
            }
            let sorted = allPending.sorted { $0.deliveryAt < $1.deliveryAt }

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
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
            let allDelivered = store.data.orders.filter {
                $0.isActive && $0.status == .entregado && $0.deliveryAt >= thirtyDaysAgo
            }
            let sorted = allDelivered.sorted { $0.deliveryAt > $1.deliveryAt }
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

        return result
    }
}
