import Foundation
import SwiftUI
import KitchenDomain
import Observation

/// Destino de navegación desde una línea de costo del desglose (Bloque I17 local-first).
enum RecipeDetailDestination: Hashable, Identifiable {
    case presentation(id: String)
    case ingredient(id: String)

    var id: String {
        switch self {
        case .presentation(let id): "presentation_\(id)"
        case .ingredient(let id): "ingredient_\(id)"
        }
    }
}

/// Modelo de presentación para el detalle y desglose de costo de una receta (MVVM, Bloque I17 local-first).
@Observable
final class RecipeDetailModel {
    let recipeId: String
    private let store: LocalStore

    var selectedVersionId: String? = nil
    var actionErrorMessage: String? = nil
    var lineErrorMessage: String? = nil
    var activeDestination: RecipeDetailDestination? = nil

    init(
        recipeId: String,
        initialVersionId: String? = nil,
        store: LocalStore = .shared
    ) {
        self.recipeId = recipeId
        self.selectedVersionId = initialVersionId
        self.store = store
    }

    var recipe: Recipe? {
        store.data.recipe(id: recipeId)
    }

    var cost: RecipeCost? {
        try? store.data.calculateRecipeCost(recipeId: recipeId, versionId: selectedVersionId)
    }

    var comparisons: [CostVersionComparison] {
        (try? store.data.compareVersions(recipeId: recipeId)) ?? []
    }

    var versions: [RecipeCostVersionDetail] {
        (try? store.data.costVersions(for: recipeId)) ?? []
    }

    var effectiveMargin: Int {
        cost?.marginPercent ?? recipe?.marginPercent ?? 30
    }

    /// Algún ingrediente de la receta tiene 2 o más marcas activas (regla de RecipeVersionsTip).
    var hasIngredientWithSeveralBrands: Bool {
        guard let recipe else { return false }
        let ingredientIds = recipe.items.filter { $0.kind == .ingredient }.map(\.refId)
        return ingredientIds.contains { ingId in
            store.data.presentations.filter { $0.ingredientId == ingId && $0.isActive }.count >= 2
        }
    }

    var selectedVersionName: String? {
        guard let selectedVersionId else { return nil }
        return versions.first(where: { $0.id == selectedVersionId })?.name ??
               comparisons.first(where: { $0.versionId == selectedVersionId })?.name
    }

    func selectVersion(_ versionId: String?) {
        guard selectedVersionId != versionId else { return }
        selectedVersionId = versionId
    }

    @discardableResult
    func createVersion(name: String) throws -> CostVersion {
        let created = try store.mutate { data, ctx in
            try data.createCostVersion(recipeId: recipeId, name: name, choices: [], ctx: ctx)
        }
        self.selectedVersionId = created.id
        return created
    }

    func renameVersion(versionId: String, newName: String) throws {
        try store.mutate { data, ctx in
            try data.updateCostVersion(recipeId: recipeId, versionId: versionId, name: newName, ctx: ctx)
        }
    }

    func deleteVersion(versionId: String) throws {
        try store.mutate { data, ctx in
            try data.deleteCostVersion(recipeId: recipeId, versionId: versionId, ctx: ctx)
        }
        if selectedVersionId == versionId {
            selectedVersionId = nil
        }
    }

    func chooseBrand(for ingredientId: String, presentationId: String?) throws {
        if let versionId = selectedVersionId {
            let currentChoices = store.data.costVersions.first(where: { $0.id == versionId && $0.isActive })?.choices ?? []
            var updatedChoices = currentChoices.filter { $0.ingredientId != ingredientId }
            if let presentationId {
                updatedChoices.append(CostVersionChoice(ingredientId: ingredientId, presentationId: presentationId))
            }
            try store.mutate { data, ctx in
                try data.updateCostVersion(recipeId: recipeId, versionId: versionId, choices: updatedChoices, ctx: ctx)
            }
        } else {
            guard let currentRecipe = recipe else { return }
            let updatedItems = currentRecipe.items.map { item -> RecipeItem in
                var copy = item
                if item.kind == .ingredient && item.refId == ingredientId {
                    copy.pinnedPresentationId = presentationId
                }
                return copy
            }
            try store.mutate { data, ctx in
                try data.updateRecipe(id: recipeId, items: updatedItems, ctx: ctx)
            }
        }
    }

    func updateMargin(percent: Int) {
        actionErrorMessage = nil
        do {
            try store.mutate { data, ctx in
                try data.updateRecipe(id: recipeId, marginPercent: percent, ctx: ctx)
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func openIngredientLine(_ line: RecipeCostLine) {
        if let presentationId = line.presentationId, !presentationId.isEmpty {
            self.activeDestination = .presentation(id: presentationId)
        } else {
            self.activeDestination = .ingredient(id: line.refId)
        }
    }
}
