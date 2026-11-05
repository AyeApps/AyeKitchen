import Foundation
import SwiftUI

/// Estado de carga de la lista de recetas.
enum RecipesLoadingState: Equatable, Sendable {
    case loading
    case loaded
    case error(String)
}

/// Errores específicos de acciones sobre recetas.
enum RecipeActionError: LocalizedError, Sendable {
    case inUse

    var errorDescription: String? {
        switch self {
        case .inUse:
            "No se puede borrar: otra receta la usa como parte de ella."
        }
    }
}

/// Modelo de presentación para la lista de recetas (MVVM, Regla 5 / Bloque I13).
@Observable
final class RecipesModel {
    var items: [RemoteRecipeListItem] = []
    var state: RecipesLoadingState = .loading
    var query: String = ""

    private var currentPage: Int = 1
    private var totalPages: Int = 1
    private(set) var isLoadingMore: Bool = false
    private(set) var isMock: Bool = false
    private var hasLoadedOnce: Bool = false

    private let firstPageQuery = [
        URLQueryItem(name: "page", value: "1"),
        URLQueryItem(name: "limit", value: "50")
    ]

    var isEmpty: Bool {
        items.isEmpty
    }

    var hasMorePages: Bool {
        currentPage < totalPages
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(mockItems: [RemoteRecipeListItem]? = nil) {
        if let mockItems {
            self.items = mockItems
            self.state = .loaded
            self.currentPage = 1
            self.totalPages = 1
            self.isMock = true
            self.hasLoadedOnce = true
        }
    }

    /// Carga la primera página de recetas (o filtra por búsqueda activa).
    func load() async {
        guard !isMock else { return }
        if isSearching {
            await performSearch()
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

    /// Recarga la lista respetando la búsqueda actual o forzando recarga de la sección.
    func refresh() async {
        guard !isMock else { return }
        if isSearching {
            await performSearch()
        } else {
            await forceReload()
        }
    }

    func forceReload() async {
        guard !isMock else { return }
        await ChangeTracker.shared.forceReload(.recipes) {
            await self.reloadSilently()
        }
    }

    func reloadIfStale() async {
        guard !isMock, !isSearching else { return }
        await ChangeTracker.shared.reloadIfStale(.recipes) {
            await self.reloadSilently()
        }
    }

    private func performSearch() async {
        state = .loading
        currentPage = 1
        do {
            let page = try await fetchPage(pageNumber: 1, query: query)
            self.items = page.items
            self.totalPages = page.pages
            self.state = .loaded
        } catch where error.isCancellation {
            if !items.isEmpty {
                self.state = .loaded
            }
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    /// Carga la siguiente página de recetas cuando el usuario llega al final de la lista.
    func loadNextPageIfNeeded(currentItem: RemoteRecipeListItem) async {
        guard let lastItem = items.last, lastItem.id == currentItem.id else { return }
        guard hasMorePages, !isLoadingMore else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1

        do {
            let page = try await fetchPage(pageNumber: nextPage, query: query)
            self.items.append(contentsOf: page.items)
            self.currentPage = nextPage
            self.totalPages = page.pages
        } catch where error.isCancellation {
            // Silencioso al paginar, mantiene los items existentes
        } catch {
            // Silencioso al paginar, mantiene los items existentes
        }
        isLoadingMore = false
    }

    /// Borra una receta:
    /// DELETE /recipes/{id} (204). IN_USE -> "No se puede borrar: otra receta la usa como parte de ella."
    func deleteRecipe(id: String) async throws {
        do {
            try await NetworkService.shared.requestNoContent(.delete, "/recipes/\(id)")
            items.removeAll { $0.id == id }
        } catch {
            if let apiError = error as? APIError, apiError.code == "IN_USE" {
                throw RecipeActionError.inUse
            }
            throw error
        }
    }

    /// Lee la copia guardada en disco de la primera pantalla sin búsqueda.
    private func loadFromCache() async -> Bool {
        guard !isMock else { return true }
        guard let page: Page<RemoteRecipeListItem> = await NetworkService.shared.cached("/recipes/", query: firstPageQuery) else {
            return false
        }
        self.items = page.items
        self.totalPages = page.pages
        self.currentPage = 1
        self.hasLoadedOnce = true
        self.state = .loaded
        return true
    }

    /// Recarga en silencio sin pasar por estado de carga. Guarda la respuesta en disco con requestCaching.
    @discardableResult
    func reloadSilently() async -> Bool {
        guard !isMock else { return true }
        do {
            let page: Page<RemoteRecipeListItem> = try await NetworkService.shared.requestCaching(
                "/recipes/",
                query: firstPageQuery
            )
            self.items = page.items
            self.totalPages = page.pages
            self.currentPage = 1
            self.hasLoadedOnce = true
            self.state = .loaded
            return true
        } catch where error.isCancellation {
            if hasLoadedOnce {
                self.state = .loaded
            }
            return false
        } catch {
            if !hasLoadedOnce {
                self.state = .error(error.localizedDescription)
            }
            return false
        }
    }

    private func fetchPage(pageNumber: Int, query: String) async throws -> Page<RemoteRecipeListItem> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(pageNumber)"),
            URLQueryItem(name: "limit", value: "50")
        ]

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmed))
            return try await NetworkService.shared.request(
                .get,
                "/recipes/",
                query: queryItems
            )
        } else if pageNumber == 1 {
            return try await NetworkService.shared.requestCaching(
                "/recipes/",
                query: queryItems
            )
        } else {
            return try await NetworkService.shared.request(
                .get,
                "/recipes/",
                query: queryItems
            )
        }
    }
}
