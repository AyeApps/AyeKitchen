import Foundation
import Observation
import KitchenDomain

// MARK: - Modelo de Inicio (Bloque I19 local-first)

@Observable final class HomeModel {
    let store: LocalStore

    private(set) var incompleteRecipes: [RecipeListItem] = []
    private(set) var stalePresentations: [CatalogStalePresentation] = []
    private var lastRevision: Int = -1

    private var calendar: Calendar { Calendar.current }
    var startOfToday: Date { calendar.startOfDay(for: Date.now) }
    var endOfSevenDays: Date {
        calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday.addingTimeInterval(7 * 86400)
    }

    init(store: LocalStore = .shared) {
        self.store = store
        recalculate(force: true)
    }

    /// Todos los pedidos activos (pendientes y en proceso), ordenados por fecha de entrega.
    var activeOrders: [Order] {
        store.data.orders
            .filter { $0.isActive && ($0.status == .pendiente || $0.status == .enProceso) }
            .sorted { a, b in
                if a.deliveryAt != b.deliveryAt {
                    return a.deliveryAt < b.deliveryAt
                }
                if a.createdAt != b.createdAt {
                    return a.createdAt < b.createdAt
                }
                return a.id < b.id
            }
    }

    /// Pedidos atrasados: pendientes o en proceso con fecha de entrega antes del inicio de hoy.
    var overdueOrders: [Order] {
        activeOrders.filter { $0.deliveryAt < startOfToday }
    }

    /// Pedidos de la semana: desde el inicio de hoy hasta 7 días después.
    var ordersThisWeek: [Order] {
        activeOrders.filter { $0.deliveryAt >= startOfToday && $0.deliveryAt <= endOfSevenDays }
    }

    /// Cantidad de entregas esta semana para el subtítulo del encabezado.
    var deliveriesThisWeekCount: Int {
        ordersThisWeek.count
    }

    /// "Lo que sigue": pedido pendiente o en proceso con la entrega más próxima desde el inicio de hoy.
    var nextOrder: Order? {
        activeOrders.first { $0.deliveryAt >= startOfToday }
    }

    /// Demás pedidos de la semana (excluyendo el que se muestra en la tarjeta "Lo que sigue").
    var remainingWeekOrders: [Order] {
        if let nextId = nextOrder?.id {
            return ordersThisWeek.filter { $0.id != nextId }
        }
        return ordersThisWeek
    }

    /// Indica si hay elementos para la sección "Por revisar".
    var hasReviewItems: Bool {
        !incompleteRecipes.isEmpty || !stalePresentations.isEmpty
    }

    func recalculateIfNeeded() {
        if store.revision != lastRevision {
            recalculate()
        }
    }

    func recalculate(force: Bool = false) {
        guard force || store.revision != lastRevision else { return }
        lastRevision = store.revision
        let allRecipes = store.data.listRecipes()
        incompleteRecipes = allRecipes.filter { !$0.complete }
        stalePresentations = Array(store.data.stalePresentations().prefix(5))
    }
}
