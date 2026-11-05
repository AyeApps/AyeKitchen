import Foundation
import KitchenDomain
import Observation

// MARK: - Modelo de Detalle de Marca

@Observable final class BrandDetailModel {
    let presentationId: String
    private let store: LocalStore

    init(presentationId: String, store: LocalStore = .shared) {
        self.presentationId = presentationId
        self.store = store
    }

    var presentation: CatalogPresentation? {
        guard let p = store.data.presentations.first(where: { $0.id == presentationId && $0.isActive }) else {
            return nil
        }
        return try? store.data.presentations(forIngredient: p.ingredientId).first(where: { $0.id == presentationId })
    }

    var prices: [PriceRecord] {
        (try? store.data.priceHistory(presentationId: presentationId)) ?? []
    }
}
