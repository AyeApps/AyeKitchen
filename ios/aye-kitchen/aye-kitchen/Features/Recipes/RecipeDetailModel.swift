import Foundation
import SwiftUI

/// Cuerpo de la petición para cambiar el margen de ganancia de una receta.
nonisolated struct RecipeMarginPatch: Encodable, Sendable {
    let marginPercent: Int
}

/// Estado de carga para el detalle de la receta.
enum RecipeDetailLoadingState: Equatable, Sendable {
    case loading
    case loaded
    case error(String)
}

/// Modelo de presentación para el detalle y desglose de costo de una receta (MVVM, Regla 5).
@Observable
final class RecipeDetailModel {
    let recipeId: String

    var recipe: Recipe?
    var cost: RecipeCost?
    var state: RecipeDetailLoadingState = .loading
    var optimisticMargin: Int?
    var isUpdatingMargin: Bool = false
    var actionErrorMessage: String?

    var effectiveMargin: Int {
        optimisticMargin ?? cost?.marginPercent ?? recipe?.marginPercent ?? 30
    }

    init(recipeId: String, mockRecipe: Recipe? = nil, mockCost: RecipeCost? = nil) {
        self.recipeId = recipeId
        if let mockRecipe, let mockCost {
            self.recipe = mockRecipe
            self.cost = mockCost
            self.state = .loaded
        }
    }

    /// Carga en paralelo GET /recipes/{id} y GET /recipes/{id}/cost.
    /// Si cualquiera falla, pasa a estado .error.
    func load() async {
        state = .loading
        actionErrorMessage = nil

        do {
            async let recipeReq: Recipe = NetworkService.shared.request(.get, "/recipes/\(recipeId)")
            async let costReq: RecipeCost = NetworkService.shared.request(.get, "/recipes/\(recipeId)/cost")

            let (loadedRecipe, loadedCost) = try await (recipeReq, costReq)
            self.recipe = loadedRecipe
            self.cost = loadedCost
            self.state = .loaded
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    /// Cambia el margen de ganancia:
    /// PATCH /recipes/{id} con solo margin_percent, luego vuelve a pedir el costo.
    /// Mientras guarda, el control se queda con lo elegido; si falla, regresa al anterior y muestra el error.
    func updateMargin(percent: Int) async {
        guard !isUpdatingMargin else { return }
        isUpdatingMargin = true
        actionErrorMessage = nil
        optimisticMargin = percent

        do {
            let body = RecipeMarginPatch(marginPercent: percent)
            let updatedRecipe: Recipe = try await NetworkService.shared.request(
                .patch,
                "/recipes/\(recipeId)",
                body: body
            )
            let updatedCost: RecipeCost = try await NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/cost"
            )

            self.recipe = updatedRecipe
            self.cost = updatedCost
            self.optimisticMargin = nil
        } catch {
            self.optimisticMargin = nil
            self.actionErrorMessage = error.localizedDescription
        }
        isUpdatingMargin = false
    }
}
