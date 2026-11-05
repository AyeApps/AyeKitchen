import Foundation
import SwiftUI
import KitchenDomain
import Observation

/// Modelo de presentación para la lista de recetas (MVVM, Bloque I17 local-first).
@Observable
final class RecipesModel {
    private let store: LocalStore
    var query: String = ""
    private(set) var items: [RecipeListItem] = []
    private var lastRevision: Int = -1
    private var lastQuery: String = ""

    init(store: LocalStore = .shared) {
        self.store = store
        recalculate(force: true)
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func recalculateIfNeeded() {
        if store.revision != lastRevision || query != lastQuery {
            recalculate()
        }
    }

    func recalculate(force: Bool = false) {
        let clean = query.trimmingCharacters(in: .whitespaces)
        lastRevision = store.revision
        lastQuery = query
        items = store.data.listRecipes(query: clean.isEmpty ? nil : clean)
    }

    func deleteRecipe(id: String) throws {
        try store.mutate { data, ctx in
            try data.deleteRecipe(id: id, ctx: ctx)
        }
        recalculate(force: true)
    }
}
