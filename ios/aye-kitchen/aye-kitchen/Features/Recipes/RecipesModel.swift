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

/// Modelo de presentación para la lista de recetas (MVVM, Regla 5).
@Observable
final class RecipesModel {
    var items: [RecipeListItem] = []
    var state: RecipesLoadingState = .loading
    var query: String = ""

    private var currentPage: Int = 1
    private var totalPages: Int = 1
    private(set) var isLoadingMore: Bool = false

    var isEmpty: Bool {
        items.isEmpty
    }

    var hasMorePages: Bool {
        currentPage < totalPages
    }

    init(mockItems: [RecipeListItem]? = nil) {
        if let mockItems {
            self.items = mockItems
            self.state = .loaded
            self.currentPage = 1
            self.totalPages = 1
        }
    }

    /// Carga la primera página de recetas (o filtra por búsqueda).
    func load() async {
        state = .loading
        currentPage = 1

        do {
            let page = try await fetchPage(pageNumber: 1, query: query)
            self.items = page.items
            self.totalPages = page.pages
            self.state = .loaded
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    /// Recarga la lista respetando la búsqueda actual.
    func refresh() async {
        currentPage = 1
        do {
            let page = try await fetchPage(pageNumber: 1, query: query)
            self.items = page.items
            self.totalPages = page.pages
            self.state = .loaded
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    /// Carga la siguiente página de recetas cuando el usuario llega al final de la lista.
    func loadNextPageIfNeeded(currentItem: RecipeListItem) async {
        guard let lastItem = items.last, lastItem.id == currentItem.id else { return }
        guard hasMorePages, !isLoadingMore else { return }

        isLoadingMore = true
        let nextPage = currentPage + 1

        do {
            let page = try await fetchPage(pageNumber: nextPage, query: query)
            self.items.append(contentsOf: page.items)
            self.currentPage = nextPage
            self.totalPages = page.pages
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

    private func fetchPage(pageNumber: Int, query: String) async throws -> Page<RecipeListItem> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(pageNumber)"),
            URLQueryItem(name: "limit", value: "50")
        ]

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmed))
        }

        return try await NetworkService.shared.request(
            .get,
            "/recipes/",
            query: queryItems
        )
    }
}
