import Foundation
import Observation

/// Descripción de cómo se mide según la unidad base del contrato.
extension RemoteIngredient {
    var buyingUnitDescription: String {
        switch baseUnit {
        case .g:
            "Se pesa (g)"
        case .ml:
            "Es líquido (ml)"
        case .pz:
            "Se cuenta (piezas)"
        }
    }
}

/// Sección agrupada para la lista de catálogo.
struct CatalogSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [RemoteIngredient]
}

/// Estado de carga para la pantalla de catálogo.
enum CatalogLoadingState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

/// ViewModel para la lista de ingredientes (`CatalogView`, MVVM, Regla 5 / Bloque I13).
@Observable final class CatalogModel {
    var ingredients: [RemoteIngredient] = []
    var state: CatalogLoadingState = .idle
    var currentPage: Int = 1
    var hasMore: Bool = false
    var isLoadingNextPage: Bool = false
    var currentSearchQuery: String? = nil
    private(set) var isMock: Bool = false
    private var hasLoadedOnce: Bool = false

    private let firstPageQuery = [
        URLQueryItem(name: "page", value: "1"),
        URLQueryItem(name: "limit", value: "50")
    ]

    var isSearching: Bool {
        guard let query = currentSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !query.isEmpty
    }

    init(mockIngredients: [RemoteIngredient]? = nil) {
        if let mockIngredients {
            self.ingredients = mockIngredients
            self.state = .loaded
            self.isMock = true
            self.hasLoadedOnce = true
        }
    }

    /// Agrupa por `group` en secciones ordenadas por nombre; los que no tienen grupo van al final en "Otros".
    var sections: [CatalogSection] {
        var groups: [String: [RemoteIngredient]] = [:]
        var others: [RemoteIngredient] = []

        for item in ingredients {
            if let groupName = item.group?.trimmingCharacters(in: .whitespacesAndNewlines), !groupName.isEmpty {
                groups[groupName, default: []].append(item)
            } else {
                others.append(item)
            }
        }

        var result: [CatalogSection] = []
        let sortedGroupNames = groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for groupName in sortedGroupNames {
            let sortedItems = (groups[groupName] ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            result.append(CatalogSection(id: groupName, title: groupName, items: sortedItems))
        }

        if !others.isEmpty {
            let sortedOthers = others.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            result.append(CatalogSection(id: "__otros__", title: "Otros", items: sortedOthers))
        }

        return result
    }

    /// Carga inicial: caché instantánea si existe, o spinner con forceReload.
    func loadInitial() async {
        guard !isMock else { return }
        if isSearching {
            state = .loading
            await fetchPage(pageNumber: 1, query: currentSearchQuery, resetList: true)
            return
        }

        if hasLoadedOnce {
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

    /// Recarga desde la página 1 (pull-to-refresh).
    func refresh() async {
        guard !isMock else { return }
        if isSearching {
            await fetchPage(pageNumber: 1, query: currentSearchQuery, resetList: true)
        } else {
            await forceReload()
        }
    }

    func forceReload() async {
        guard !isMock else { return }
        await ChangeTracker.shared.forceReload(.catalog) {
            await self.reloadSilently()
        }
    }

    func reloadIfStale() async {
        guard !isMock, !isSearching else { return }
        await ChangeTracker.shared.reloadIfStale(.catalog) {
            await self.reloadSilently()
        }
    }

    /// Carga la siguiente página si hay más items (paginación, sigue con request).
    func loadNextPage() async {
        guard !isMock, hasMore, !isLoadingNextPage, state == .loaded else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        let nextPage = currentPage + 1
        await fetchPage(pageNumber: nextPage, query: currentSearchQuery, resetList: false)
    }

    /// Búsqueda con filtro en servidor. Al vaciarse, vuelve a la primera pantalla (desde caché).
    func search(query: String) async {
        guard !isMock else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            currentSearchQuery = nil
            await loadInitial()
        } else {
            currentSearchQuery = trimmed
            state = .loading
            await fetchPage(pageNumber: 1, query: trimmed, resetList: true)
        }
    }

    /// Borrado del ingrediente. Lanza error para que la vista decida cómo mostrarlo (p. ej. IN_USE).
    func deleteIngredient(_ ingredient: RemoteIngredient) async throws {
        if isMock {
            removeIngredient(id: ingredient.id)
            return
        }
        try await NetworkService.shared.requestNoContent(.delete, "/ingredients/\(ingredient.id)")
        removeIngredient(id: ingredient.id)
    }

    /// Agrega un ingrediente recién creado a la lista local.
    func addIngredient(_ ingredient: RemoteIngredient) {
        if let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
            ingredients[index] = ingredient
        } else {
            ingredients.append(ingredient)
        }
    }

    /// Actualiza un ingrediente existente en la lista local.
    func updateIngredient(_ ingredient: RemoteIngredient) {
        if let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
            ingredients[index] = ingredient
        }
    }

    /// Elimina un ingrediente de la lista local por su id.
    func removeIngredient(id: String) {
        ingredients.removeAll { $0.id == id }
    }

    // MARK: - Privado

    /// Lee la copia guardada en disco de la primera pantalla sin búsqueda.
    private func loadFromCache() async -> Bool {
        guard !isMock else { return true }
        guard let page: Page<RemoteIngredient> = await NetworkService.shared.cached("/ingredients/", query: firstPageQuery) else {
            return false
        }
        self.ingredients = page.items
        self.currentPage = page.page
        self.hasMore = page.hasMore
        self.hasLoadedOnce = true
        self.state = .loaded
        return true
    }

    /// Recarga en silencio sin pasar por estado de carga. Guarda la respuesta en disco con requestCaching.
    @discardableResult
    func reloadSilently() async -> Bool {
        guard !isMock else { return true }
        do {
            let page: Page<RemoteIngredient> = try await NetworkService.shared.requestCaching(
                "/ingredients/",
                query: firstPageQuery
            )
            self.ingredients = page.items
            self.currentPage = page.page
            self.hasMore = page.hasMore
            self.hasLoadedOnce = true
            self.state = .loaded
            return true
        } catch where error.isCancellation {
            if !hasLoadedOnce {
                self.state = .idle
            }
            return false
        } catch {
            if !hasLoadedOnce {
                self.state = .error(error.localizedDescription)
            }
            return false
        }
    }

    private func fetchPage(pageNumber: Int, query: String?, resetList: Bool) async {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(pageNumber)"),
            URLQueryItem(name: "limit", value: "50")
        ]
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = trimmed != nil && !trimmed!.isEmpty
        if hasQuery {
            queryItems.append(URLQueryItem(name: "q", value: trimmed!))
        }

        do {
            let page: Page<RemoteIngredient>
            if !hasQuery && pageNumber == 1 {
                page = try await NetworkService.shared.requestCaching(
                    "/ingredients/",
                    query: queryItems
                )
            } else {
                page = try await NetworkService.shared.request(
                    .get,
                    "/ingredients/",
                    query: queryItems
                )
            }
            currentPage = page.page
            hasMore = page.hasMore
            if resetList {
                ingredients = page.items
            } else {
                ingredients.append(contentsOf: page.items)
            }
            hasLoadedOnce = true
            state = .loaded
        } catch where error.isCancellation {
            if !hasLoadedOnce {
                state = .idle
            } else if state == .loading {
                state = .loaded
            }
        } catch let apiError as APIError {
            if !hasLoadedOnce {
                state = .error(apiError.localizedDescription)
            }
        } catch {
            if !hasLoadedOnce {
                state = .error(error.localizedDescription)
            }
        }
    }
}
