import Foundation
import Observation

/// Descripción de cómo se compra según la unidad base del contrato.
extension Ingredient {
    var buyingUnitDescription: String {
        switch baseUnit {
        case .g:
            "Por peso (g)"
        case .ml:
            "Por volumen (ml)"
        case .pz:
            "Por pieza"
        }
    }
}

/// Sección agrupada para la lista de catálogo.
struct CatalogSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [Ingredient]
}

/// Estado de carga para la pantalla de catálogo.
enum CatalogLoadingState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

/// ViewModel para la lista de ingredientes (`CatalogView`).
@Observable final class CatalogModel {
    var ingredients: [Ingredient] = []
    var state: CatalogLoadingState = .idle
    var currentPage: Int = 1
    var hasMore: Bool = false
    var isLoadingNextPage: Bool = false
    var currentSearchQuery: String? = nil
    private(set) var isMock: Bool = false

    init(mockIngredients: [Ingredient]? = nil) {
        if let mockIngredients {
            self.ingredients = mockIngredients
            self.state = .loaded
            self.isMock = true
        }
    }

    /// Agrupa por `group` en secciones ordenadas por nombre; los que no tienen grupo van al final en "Otros".
    var sections: [CatalogSection] {
        var groups: [String: [Ingredient]] = [:]
        var others: [Ingredient] = []

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

    /// Carga inicial de la primera página (limit=50).
    func loadInitial() async {
        guard !isMock else { return }
        if ingredients.isEmpty {
            state = .loading
        }
        await fetchPage(pageNumber: 1, query: currentSearchQuery, resetList: true)
    }

    /// Recarga desde la página 1 (pull-to-refresh).
    func refresh() async {
        guard !isMock else { return }
        await fetchPage(pageNumber: 1, query: currentSearchQuery, resetList: true)
    }

    /// Carga la siguiente página si hay más items.
    func loadNextPage() async {
        guard !isMock, hasMore, !isLoadingNextPage, state == .loaded else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        let nextPage = currentPage + 1
        await fetchPage(pageNumber: nextPage, query: currentSearchQuery, resetList: false)
    }

    /// Búsqueda con filtro en servidor.
    func search(query: String) async {
        guard !isMock else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let newQuery = trimmed.isEmpty ? nil : trimmed
        currentSearchQuery = newQuery
        state = .loading
        await fetchPage(pageNumber: 1, query: newQuery, resetList: true)
    }

    /// Borrado del ingrediente. Lanza error para que la vista decida cómo mostrarlo (p. ej. IN_USE).
    func deleteIngredient(_ ingredient: Ingredient) async throws {
        if isMock {
            removeIngredient(id: ingredient.id)
            return
        }
        try await NetworkService.shared.requestNoContent(.delete, "/ingredients/\(ingredient.id)")
        removeIngredient(id: ingredient.id)
    }

    /// Agrega un ingrediente recién creado a la lista local.
    func addIngredient(_ ingredient: Ingredient) {
        if let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
            ingredients[index] = ingredient
        } else {
            ingredients.append(ingredient)
        }
    }

    /// Actualiza un ingrediente existente en la lista local.
    func updateIngredient(_ ingredient: Ingredient) {
        if let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
            ingredients[index] = ingredient
        }
    }

    /// Elimina un ingrediente de la lista local por su id.
    func removeIngredient(id: String) {
        ingredients.removeAll { $0.id == id }
    }

    // MARK: - Privado

    private func fetchPage(pageNumber: Int, query: String?, resetList: Bool) async {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(pageNumber)"),
            URLQueryItem(name: "limit", value: "50")
        ]
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        do {
            let page: Page<Ingredient> = try await NetworkService.shared.request(
                .get,
                "/ingredients/",
                query: queryItems
            )
            currentPage = page.page
            hasMore = page.hasMore
            if resetList {
                ingredients = page.items
            } else {
                ingredients.append(contentsOf: page.items)
            }
            state = .loaded
        } catch let apiError as APIError {
            state = .error(apiError.localizedDescription)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
