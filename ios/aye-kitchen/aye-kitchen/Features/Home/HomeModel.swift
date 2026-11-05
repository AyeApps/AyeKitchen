import Foundation

// MARK: - Modelo de Inicio (Bloque I4 / I13)

@Observable final class HomeModel {
    var pendingOrders: [RemoteOrder] = []
    var inProgressOrders: [RemoteOrder] = []
    var recipes: [RemoteRecipeListItem] = []
    var stalePresentations: [StalePresentation] = []

    var isLoading = false
    var errorMessage: String?
    private(set) var isMock: Bool = false
    private var hasLoadedOnce: Bool = false

    private var calendar: Calendar { Calendar.current }
    var startOfToday: Date { calendar.startOfDay(for: Date.now) }
    var endOfSevenDays: Date {
        calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday.addingTimeInterval(7 * 86400)
    }

    private let pendingQuery = [
        URLQueryItem(name: "status", value: "pendiente"),
        URLQueryItem(name: "limit", value: "100")
    ]
    private let inProgressQuery = [
        URLQueryItem(name: "status", value: "en_proceso"),
        URLQueryItem(name: "limit", value: "100")
    ]
    private let recipesQuery = [
        URLQueryItem(name: "limit", value: "100")
    ]
    private let staleQuery = [
        URLQueryItem(name: "limit", value: "5")
    ]

    init(
        pendingOrders: [RemoteOrder]? = nil,
        inProgressOrders: [RemoteOrder]? = nil,
        recipes: [RemoteRecipeListItem]? = nil,
        stalePresentations: [StalePresentation]? = nil
    ) {
        if pendingOrders != nil || inProgressOrders != nil || recipes != nil || stalePresentations != nil {
            self.isMock = true
            self.hasLoadedOnce = true
        }
        if let pendingOrders { self.pendingOrders = pendingOrders }
        if let inProgressOrders { self.inProgressOrders = inProgressOrders }
        if let recipes { self.recipes = recipes }
        if let stalePresentations { self.stalePresentations = stalePresentations }
    }

    /// Todos los pedidos activos (pendientes y en proceso), ordenados por fecha de entrega.
    var activeOrders: [RemoteOrder] {
        var map: [String: RemoteOrder] = [:]
        for order in pendingOrders + inProgressOrders {
            map[order.id] = order
        }
        return map.values.sorted { $0.deliveryAt < $1.deliveryAt }
    }

    /// Pedidos atrasados: pendientes o en proceso con fecha de entrega antes del inicio de hoy.
    var overdueOrders: [RemoteOrder] {
        activeOrders.filter { $0.deliveryAt < startOfToday }
    }

    /// Pedidos de la semana: desde el inicio de hoy hasta 7 días después.
    var ordersThisWeek: [RemoteOrder] {
        activeOrders.filter { $0.deliveryAt >= startOfToday && $0.deliveryAt <= endOfSevenDays }
    }

    /// Cantidad de entregas esta semana para el subtítulo del encabezado.
    var deliveriesThisWeekCount: Int {
        ordersThisWeek.count
    }

    /// "Lo que sigue": pedido pendiente o en proceso con la entrega más próxima desde el inicio de hoy.
    var nextOrder: RemoteOrder? {
        activeOrders.first { $0.deliveryAt >= startOfToday }
    }

    /// Demás pedidos de la semana (excluyendo el que se muestra en la tarjeta "Lo que sigue").
    var remainingWeekOrders: [RemoteOrder] {
        if let nextId = nextOrder?.id {
            return ordersThisWeek.filter { $0.id != nextId }
        }
        return ordersThisWeek
    }

    /// Recetas con complete falso.
    var incompleteRecipes: [RemoteRecipeListItem] {
        recipes.filter { !$0.complete }
    }

    /// Indica si hay elementos para la sección "Por revisar".
    var hasReviewItems: Bool {
        !incompleteRecipes.isEmpty || !stalePresentations.isEmpty
    }

    /// Carga inicial: caché instantánea si existe, o spinner con forceReload.
    func load() async {
        guard !isMock else { return }
        if hasLoadedOnce {
            await reloadIfStale()
        } else {
            if await loadFromCache() {
                await reloadIfStale()
            } else {
                isLoading = true
                errorMessage = nil
                await forceReload()
            }
        }
    }

    /// Jalar para refrescar o recarga forzada tras guardar.
    func refresh() async {
        await forceReload()
    }

    func forceReload() async {
        guard !isMock else { return }
        await ChangeTracker.shared.forceReload(.home) {
            await self.reloadSilently()
        }
    }

    func reloadIfStale() async {
        guard !isMock else { return }
        await ChangeTracker.shared.reloadIfStale(.home) {
            await self.reloadSilently()
        }
    }

    /// Lee la copia guardada en disco de las 4 peticiones de Inicio.
    private func loadFromCache() async -> Bool {
        guard !isMock else { return true }
        async let cachedPending: Page<RemoteOrder>? = NetworkService.shared.cached("/orders/", query: pendingQuery)
        async let cachedInProgress: Page<RemoteOrder>? = NetworkService.shared.cached("/orders/", query: inProgressQuery)
        async let cachedRecipes: Page<RemoteRecipeListItem>? = NetworkService.shared.cached("/recipes/", query: recipesQuery)
        async let cachedStale: Page<StalePresentation>? = NetworkService.shared.cached("/presentations/stale", query: staleQuery)

        let (pOrders, ipOrders, rList, sList) = await (cachedPending, cachedInProgress, cachedRecipes, cachedStale)
        guard let pOrders, let ipOrders, let rList, let sList else {
            return false
        }

        self.pendingOrders = pOrders.items
        self.inProgressOrders = ipOrders.items
        self.recipes = rList.items
        self.stalePresentations = sList.items
        self.hasLoadedOnce = true
        self.isLoading = false
        self.errorMessage = nil
        return true
    }

    /// Recarga en silencio sin pasar por estado de carga. Guarda las respuestas en caché.
    @discardableResult
    func reloadSilently() async -> Bool {
        guard !isMock else { return true }
        do {
            async let pendingTask: Page<RemoteOrder> = NetworkService.shared.requestCaching(
                "/orders/",
                query: pendingQuery
            )
            async let inProgressTask: Page<RemoteOrder> = NetworkService.shared.requestCaching(
                "/orders/",
                query: inProgressQuery
            )
            async let recipesTask: Page<RemoteRecipeListItem> = NetworkService.shared.requestCaching(
                "/recipes/",
                query: recipesQuery
            )
            async let staleTask: Page<StalePresentation> = NetworkService.shared.requestCaching(
                "/presentations/stale",
                query: staleQuery
            )

            let (pOrders, ipOrders, rList, sList) = try await (pendingTask, inProgressTask, recipesTask, staleTask)
            self.pendingOrders = pOrders.items
            self.inProgressOrders = ipOrders.items
            self.recipes = rList.items
            self.stalePresentations = sList.items
            self.hasLoadedOnce = true
            self.errorMessage = nil
            self.isLoading = false
            return true
        } catch where error.isCancellation {
            self.isLoading = false
            return false
        } catch {
            self.isLoading = false
            if !hasLoadedOnce {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }
}
