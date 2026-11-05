import Foundation
import SwiftUI
import KitchenDomain
import Observation

enum RecipeItemPickerTab: String, CaseIterable, Identifiable, Sendable {
    case ingredients = "Ingredientes"
    case myRecipes = "Mis recetas"

    var id: String { rawValue }
}

@Observable
final class RecipeItemPickerModel {
    private let store: LocalStore
    var tab: RecipeItemPickerTab = .ingredients
    var searchText: String = ""
    let editingRecipeId: String?

    init(
        editingRecipeId: String? = nil,
        store: LocalStore = .shared
    ) {
        self.editingRecipeId = editingRecipeId
        self.store = store
    }

    var ingredients: [Ingredient] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let active = store.data.ingredients.filter { $0.isActive }
        if trimmed.isEmpty {
            return active.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return active
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var usableSubrecipes: [RecipeUsableSubrecipe] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let list: [RecipeUsableSubrecipe]
        if let editingRecipeId {
            list = (try? store.data.usableSubrecipes(for: editingRecipeId)) ?? []
        } else {
            list = store.data.recipes
                .filter { $0.isActive }
                .map { RecipeUsableSubrecipe(id: $0.id, name: $0.name, yieldUnit: $0.yieldUnit) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if trimmed.isEmpty {
            return list
        }
        return list.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
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
