import Foundation

// MARK: - Modelo de Inicio (Bloque I4)

@Observable final class HomeModel {
    var pendingOrders: [Order] = []
    var inProgressOrders: [Order] = []
    var recipes: [RecipeListItem] = []
    var stalePresentations: [StalePresentation] = []

    var isLoading = false
    var errorMessage: String?

    private var calendar: Calendar { Calendar.current }
    var startOfToday: Date { calendar.startOfDay(for: Date.now) }
    var endOfSevenDays: Date {
        calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday.addingTimeInterval(7 * 86400)
    }

    init(
        pendingOrders: [Order]? = nil,
        inProgressOrders: [Order]? = nil,
        recipes: [RecipeListItem]? = nil,
        stalePresentations: [StalePresentation]? = nil
    ) {
        if let pendingOrders { self.pendingOrders = pendingOrders }
        if let inProgressOrders { self.inProgressOrders = inProgressOrders }
        if let recipes { self.recipes = recipes }
        if let stalePresentations { self.stalePresentations = stalePresentations }
    }

    /// Todos los pedidos activos (pendientes y en proceso), ordenados por fecha de entrega.
    var activeOrders: [Order] {
        var map: [String: Order] = [:]
        for order in pendingOrders + inProgressOrders {
            map[order.id] = order
        }
        return map.values.sorted { $0.deliveryAt < $1.deliveryAt }
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

    /// Recetas con complete falso.
    var incompleteRecipes: [RecipeListItem] {
        recipes.filter { !$0.complete }
    }

    /// Indica si hay elementos para la sección "Por revisar".
    var hasReviewItems: Bool {
        !incompleteRecipes.isEmpty || !stalePresentations.isEmpty
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            async let pendingTask: Page<Order> = NetworkService.shared.request(
                .get,
                "/orders/",
                query: [
                    URLQueryItem(name: "status", value: "pendiente"),
                    URLQueryItem(name: "limit", value: "100")
                ]
            )
            async let inProgressTask: Page<Order> = NetworkService.shared.request(
                .get,
                "/orders/",
                query: [
                    URLQueryItem(name: "status", value: "en_proceso"),
                    URLQueryItem(name: "limit", value: "100")
                ]
            )
            async let recipesTask: Page<RecipeListItem> = NetworkService.shared.request(
                .get,
                "/recipes/",
                query: [
                    URLQueryItem(name: "limit", value: "100")
                ]
            )
            async let staleTask: Page<StalePresentation> = NetworkService.shared.request(
                .get,
                "/presentations/stale",
                query: [
                    URLQueryItem(name: "limit", value: "5")
                ]
            )

            let (pOrders, ipOrders, rList, sList) = try await (pendingTask, inProgressTask, recipesTask, staleTask)
            self.pendingOrders = pOrders.items
            self.inProgressOrders = ipOrders.items
            self.recipes = rList.items
            self.stalePresentations = sList.items
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }
}
