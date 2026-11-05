import Foundation
import SwiftUI
import KitchenDomain
import Observation

/// Modelo de presentación para la selección de marca de un ingrediente (MVVM, Bloque I17 local-first).
@Observable
final class BrandChoiceModel {
    let ingredientId: String
    private let store: LocalStore

    init(ingredientId: String, store: LocalStore = .shared) {
        self.ingredientId = ingredientId
        self.store = store
    }

    var presentations: [CatalogPresentation] {
        (try? store.data.presentations(ingredientId: ingredientId)) ?? []
    }
}
