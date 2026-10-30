import Foundation
import SwiftUI

enum RecipeItemPickerTab: String, CaseIterable, Identifiable, Sendable {
    case ingredients = "Ingredientes"
    case myRecipes = "Mis recetas"

    var id: String { rawValue }
}

@Observable
final class RecipeItemPickerModel {
    var tab: RecipeItemPickerTab = .ingredients
    var searchText: String = ""

    var ingredients: [Ingredient] = []
    var usableSubrecipes: [UsableSubrecipe] = []
    var allRecipes: [RecipeListItem] = []

    var isLoading: Bool = false
    var errorMessage: String? = nil

    let editingRecipeId: String?
    private(set) var isMock: Bool = false
    private var searchTask: Task<Void, Never>?

    init(
        editingRecipeId: String? = nil,
        mockIngredients: [Ingredient]? = nil,
        mockSubrecipes: [UsableSubrecipe]? = nil,
        mockAllRecipes: [RecipeListItem]? = nil
    ) {
        self.editingRecipeId = editingRecipeId
        if let mockIngredients {
            self.ingredients = mockIngredients
            self.isMock = true
        }
        if let mockSubrecipes {
            self.usableSubrecipes = mockSubrecipes
            self.isMock = true
        }
        if let mockAllRecipes {
            self.allRecipes = mockAllRecipes
            self.isMock = true
        }
    }

    func loadInitialData() async {
        guard !isMock else { return }
        isLoading = true
        defer { isLoading = false }

        await loadIngredients(query: "")

        if let editingRecipeId {
            do {
                let subrecipes: [UsableSubrecipe] = try await NetworkService.shared.request(
                    .get,
                    "/recipes/\(editingRecipeId)/usable-as-subrecipe"
                )
                self.usableSubrecipes = subrecipes
            } catch {
                self.errorMessage = error.localizedDescription
            }
        } else {
            do {
                let page: Page<RecipeListItem> = try await NetworkService.shared.request(
                    .get,
                    "/recipes/",
                    query: [URLQueryItem(name: "limit", value: "100")]
                )
                self.allRecipes = page.items
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func onSearchTextChanged(_ newText: String) {
        searchText = newText
        guard !isMock else { return }

        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadIngredients(query: newText)
        }
    }

    private func loadIngredients(query: String) async {
        do {
            var queryItems = [URLQueryItem(name: "limit", value: "50")]
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                queryItems.append(URLQueryItem(name: "q", value: trimmed))
            }
            let page: Page<Ingredient> = try await NetworkService.shared.request(
                .get,
                "/ingredients/",
                query: queryItems
            )
            self.ingredients = page.items
        } catch {
            if !Task.isCancelled {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Agrega un ingrediente al principio de la lista sin duplicar por id.
    func prependIngredient(_ ingredient: Ingredient) {
        ingredients.removeAll { $0.id == ingredient.id }
        ingredients.insert(ingredient, at: 0)
    }

    /// Alias para conveniencia.
    func addIngredient(_ ingredient: Ingredient) {
        prependIngredient(ingredient)
    }

    var filteredSubrecipes: [UsableSubrecipe] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return usableSubrecipes }
        return usableSubrecipes.filter { $0.name.lowercased().contains(trimmed) }
    }

    var filteredAllRecipes: [RecipeListItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return allRecipes }
        return allRecipes.filter { $0.recipe.name.lowercased().contains(trimmed) }
    }

    static func ingredientSubtitle(for baseUnit: BaseUnit) -> String {
        switch baseUnit {
        case .g: "Por peso (g)"
        case .ml: "Por volumen (ml)"
        case .pz: "Por pieza"
        }
    }

    static func recipeSubtitle(for yieldUnit: BaseUnit) -> String {
        switch yieldUnit {
        case .g: "Rinde en gramos"
        case .ml: "Rinde en mililitros"
        case .pz: "Rinde en piezas"
        }
    }
}
