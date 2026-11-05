import Foundation
import SwiftUI

/// Modelo de presentación para el selector de recetas en pedidos (MVVM, Regla 5).
@Observable
final class RecipePickerModel {
    var query: String = ""
    var recipes: [RemoteRecipeListItem] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var selectingId: String?

    init(recipes: [RemoteRecipeListItem] = []) {
        self.recipes = recipes
    }

    /// Busca recetas en el catálogo: GET /recipes/?q=...&limit=50
    func searchRecipes() async {
        isLoading = true
        errorMessage = nil

        var queryItems = [URLQueryItem(name: "limit", value: "50")]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmed))
        }

        do {
            let page: Page<RemoteRecipeListItem> = try await NetworkService.shared.request(
                .get,
                "/recipes/",
                query: queryItems
            )
            self.recipes = page.items
        } catch where error.isCancellation {
            // Cancelado: no mostrar error ni cambiar datos existentes
        } catch {
            self.errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
