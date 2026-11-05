import Foundation
import SwiftUI

/// Estado de carga para las marcas de un ingrediente.
enum BrandChoiceLoadingState: Equatable, Sendable {
    case loading
    case loaded
    case error(String)
}

/// Modelo de presentación para la selección de marca de un ingrediente (MVVM, Regla 5).
@Observable
final class BrandChoiceModel {
    let ingredientId: String

    var presentations: [Presentation] = []
    var state: BrandChoiceLoadingState = .loading

    init(ingredientId: String, mockPresentations: [Presentation]? = nil) {
        self.ingredientId = ingredientId
        if let mockPresentations {
            self.presentations = mockPresentations
            self.state = .loaded
        }
    }

    /// Carga las marcas del ingrediente:
    /// GET /presentations/?ingredient_id={ingredientId}&limit=100
    func load() async {
        state = .loading

        do {
            let page: Page<Presentation> = try await NetworkService.shared.request(
                .get,
                "/presentations/",
                query: [
                    URLQueryItem(name: "ingredient_id", value: ingredientId),
                    URLQueryItem(name: "limit", value: "100")
                ]
            )
            self.presentations = page.items
            self.state = .loaded
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }
}
