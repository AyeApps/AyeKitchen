import Foundation
import SwiftUI

/// Cuerpo de la petición para cambiar el margen de ganancia de una receta.
nonisolated struct RecipeMarginPatch: Encodable, Sendable {
    let marginPercent: Int
}

/// Payload para actualizar las líneas de una receta en la versión base.
nonisolated struct RecipeItemPayload: Encodable, Sendable {
    let kind: RecipeItemKind
    let refId: String
    let quantity: String
    let unitId: String?
    let pinnedPresentationId: String?

    enum CodingKeys: String, CodingKey {
        case kind, refId, quantity, unitId, pinnedPresentationId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(refId, forKey: .refId)
        try container.encode(quantity, forKey: .quantity)
        if let unitId {
            try container.encode(unitId, forKey: .unitId)
        } else {
            try container.encodeNil(forKey: .unitId)
        }
        if let pinnedPresentationId {
            try container.encode(pinnedPresentationId, forKey: .pinnedPresentationId)
        } else {
            try container.encodeNil(forKey: .pinnedPresentationId)
        }
    }
}

nonisolated struct RecipeItemsPatch: Encodable, Sendable {
    let items: [RecipeItemPayload]
}

/// Elección de marca de ingrediente en una versión de costeo.
nonisolated struct CostVersionChoicePayload: Encodable, Sendable {
    let ingredientId: String
    let presentationId: String
}

nonisolated struct CostVersionCreatePayload: Encodable, Sendable {
    let name: String
    let choices: [CostVersionChoicePayload]
}

nonisolated struct CostVersionRenamePayload: Encodable, Sendable {
    let name: String
}

nonisolated struct CostVersionChoicesPatchPayload: Encodable, Sendable {
    let choices: [CostVersionChoicePayload]
}

/// Estado de carga para el detalle de la receta.
enum RecipeDetailLoadingState: Equatable, Sendable {
    case loading
    case loaded
    case error(String)
}

/// Destino de navegación desde una línea de costo del desglose.
enum RecipeDetailDestination: Hashable, Identifiable {
    case presentation(Presentation)
    case ingredient(Ingredient)

    var id: String {
        switch self {
        case .presentation(let p): "presentation_\(p.id)"
        case .ingredient(let i): "ingredient_\(i.id)"
        }
    }
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

    var selectedVersionId: String? = nil
    var comparisons: [CostVersionComparison] = []
    var versions: [CostVersion] = []
    var isLoadingCost: Bool = false

    var loadingLine: CostLine? = nil
    var lineErrorMessage: String? = nil
    var activeDestination: RecipeDetailDestination? = nil

    var effectiveMargin: Int {
        optimisticMargin ?? cost?.marginPercent ?? recipe?.marginPercent ?? 30
    }

    var selectedVersionName: String? {
        guard let selectedVersionId else { return nil }
        return versions.first(where: { $0.id == selectedVersionId })?.name ??
               comparisons.first(where: { $0.versionId == selectedVersionId })?.name
    }

    init(
        recipeId: String,
        mockRecipe: Recipe? = nil,
        mockCost: RecipeCost? = nil,
        mockComparisons: [CostVersionComparison]? = nil,
        mockVersions: [CostVersion]? = nil,
        initialVersionId: String? = nil
    ) {
        self.recipeId = recipeId
        self.selectedVersionId = initialVersionId
        if let mockRecipe, let mockCost {
            self.recipe = mockRecipe
            self.cost = mockCost
            self.comparisons = mockComparisons ?? []
            self.versions = mockVersions ?? []
            self.state = .loaded
        }
    }

    /// Carga en paralelo GET /recipes/{id}, GET /recipes/{id}/cost,
    /// GET /recipes/{id}/versions/compare y GET /recipes/{id}/versions/.
    /// Si la comparación falla, el detalle se sigue viendo sin el selector.
    func load() async {
        state = .loading
        actionErrorMessage = nil

        do {
            let costQuery: [URLQueryItem] = selectedVersionId.map {
                [URLQueryItem(name: "version_id", value: $0)]
            } ?? []

            async let recipeReq: Recipe = NetworkService.shared.request(.get, "/recipes/\(recipeId)")
            async let costReq: RecipeCost = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/cost",
                query: costQuery
            )
            async let compareReq: [CostVersionComparison] = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/versions/compare"
            )
            async let versionsReq: [CostVersion] = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/versions/"
            )

            let loadedRecipe = try await recipeReq
            let loadedCost = try await costReq
            let loadedComparisons = (try? await compareReq) ?? []
            let loadedVersions = (try? await versionsReq) ?? []

            self.recipe = loadedRecipe
            self.cost = loadedCost
            self.comparisons = loadedComparisons
            self.versions = loadedVersions
            self.state = .loaded
        } catch where error.isCancellation {
            if recipe != nil {
                self.state = .loaded
            }
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    /// Cambia la versión seleccionada y pide el costo correspondiente.
    func selectVersion(_ versionId: String?) async {
        guard selectedVersionId != versionId else { return }
        selectedVersionId = versionId
        isLoadingCost = true
        actionErrorMessage = nil

        do {
            let costQuery: [URLQueryItem] = versionId.map {
                [URLQueryItem(name: "version_id", value: $0)]
            } ?? []
            let loadedCost: RecipeCost = try await NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/cost",
                query: costQuery
            )
            self.cost = loadedCost
        } catch where error.isCancellation {
            isLoadingCost = false
            return
        } catch {
            self.actionErrorMessage = error.localizedDescription
        }
        isLoadingCost = false
    }

    /// Crea una nueva versión con choices vacío: POST /recipes/{id}/versions/.
    /// Al guardar, la versión nueva queda elegida y se recargan costo, versiones y comparación.
    @discardableResult
    func createVersion(name: String) async throws -> CostVersion {
        let payload = CostVersionCreatePayload(name: name, choices: [])
        let created: CostVersion = try await NetworkService.shared.request(
            .post,
            "/recipes/\(recipeId)/versions/",
            body: payload
        )

        self.selectedVersionId = created.id

        // Recargar versiones, comparaciones y el costo de la nueva versión
        async let versionsReq: [CostVersion] = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/versions/"
        )
        async let compareReq: [CostVersionComparison] = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/versions/compare"
        )
        async let costReq: RecipeCost = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/cost",
            query: [URLQueryItem(name: "version_id", value: created.id)]
        )

        let (newVersions, newComparisons, newCost) = try await (versionsReq, compareReq, costReq)
        self.versions = newVersions
        self.comparisons = newComparisons
        self.cost = newCost

        return created
    }

    /// Renombra una versión existente: PATCH /recipes/{id}/versions/{version_id}.
    func renameVersion(versionId: String, newName: String) async throws {
        let payload = CostVersionRenamePayload(name: newName)
        let _: CostVersion = try await NetworkService.shared.request(
            .patch,
            "/recipes/\(recipeId)/versions/\(versionId)",
            body: payload
        )

        let costQuery: [URLQueryItem] = selectedVersionId.map {
            [URLQueryItem(name: "version_id", value: $0)]
        } ?? []

        async let versionsReq: [CostVersion] = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/versions/"
        )
        async let compareReq: [CostVersionComparison] = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/versions/compare"
        )
        async let costReq: RecipeCost = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/cost",
            query: costQuery
        )

        let (newVersions, newComparisons, newCost) = try await (versionsReq, compareReq, costReq)
        self.versions = newVersions
        self.comparisons = newComparisons
        self.cost = newCost
    }

    /// Borra una versión: DELETE /recipes/{id}/versions/{version_id}.
    /// Regresa a la versión base y recarga receta, costo y comparación.
    func deleteVersion(versionId: String) async throws {
        try await NetworkService.shared.requestNoContent(
            .delete,
            "/recipes/\(recipeId)/versions/\(versionId)"
        )

        self.selectedVersionId = nil

        async let versionsReq: [CostVersion] = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/versions/"
        )
        async let compareReq: [CostVersionComparison] = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/versions/compare"
        )
        async let costReq: RecipeCost = NetworkService.shared.request(
            .get,
            "/recipes/\(recipeId)/cost"
        )

        let (newVersions, newComparisons, newCost) = try await (versionsReq, compareReq, costReq)
        self.versions = newVersions
        self.comparisons = newComparisons
        self.cost = newCost
    }

    /// Guarda la elección de marca para un ingrediente.
    /// - Si estamos en una versión: PATCH /recipes/{id}/versions/{version_id} con choices completos.
    /// - Si estamos en la base: PATCH /recipes/{id} con items completos cambiando pinned_presentation_id.
    func chooseBrand(for ingredientId: String, presentationId: String?) async throws {
        if let versionId = selectedVersionId {
            // Versión de costeo
            let currentChoices = versions.first(where: { $0.id == versionId })?.choices ?? []
            var updatedChoices = currentChoices
                .filter { $0.ingredientId != ingredientId }
                .map { CostVersionChoicePayload(ingredientId: $0.ingredientId, presentationId: $0.presentationId) }

            if let presentationId {
                updatedChoices.append(CostVersionChoicePayload(ingredientId: ingredientId, presentationId: presentationId))
            }

            let payload = CostVersionChoicesPatchPayload(choices: updatedChoices)
            let _: CostVersion = try await NetworkService.shared.request(
                .patch,
                "/recipes/\(recipeId)/versions/\(versionId)",
                body: payload
            )

            async let versionsReq: [CostVersion] = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/versions/"
            )
            async let compareReq: [CostVersionComparison] = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/versions/compare"
            )
            async let costReq: RecipeCost = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/cost",
                query: [URLQueryItem(name: "version_id", value: versionId)]
            )

            let (newVersions, newComparisons, newCost) = try await (versionsReq, compareReq, costReq)
            self.versions = newVersions
            self.comparisons = newComparisons
            self.cost = newCost
        } else {
            // Versión base: actualizar items de la receta
            guard let currentRecipe = recipe else { return }
            let updatedItems: [RecipeItemPayload] = currentRecipe.items.map { item in
                let newPinnedId: String? = (item.kind == .ingredient && item.refId == ingredientId)
                    ? presentationId
                    : item.pinnedPresentationId

                return RecipeItemPayload(
                    kind: item.kind,
                    refId: item.refId,
                    quantity: item.quantity,
                    unitId: item.unitId,
                    pinnedPresentationId: newPinnedId
                )
            }

            let payload = RecipeItemsPatch(items: updatedItems)
            let updatedRecipe: Recipe = try await NetworkService.shared.request(
                .patch,
                "/recipes/\(recipeId)",
                body: payload
            )

            async let costReq: RecipeCost = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/cost"
            )
            async let compareReq: [CostVersionComparison] = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/versions/compare"
            )
            async let versionsReq: [CostVersion] = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/versions/"
            )

            let (newCost, newComparisons, newVersions) = try await (costReq, compareReq, versionsReq)
            self.recipe = updatedRecipe
            self.cost = newCost
            self.comparisons = newComparisons
            self.versions = newVersions
        }
    }

    /// Cambia el margen de ganancia:
    /// PATCH /recipes/{id} con solo margin_percent, luego vuelve a pedir el costo.
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

            let costQuery: [URLQueryItem] = selectedVersionId.map {
                [URLQueryItem(name: "version_id", value: $0)]
            } ?? []
            async let costReq: RecipeCost = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/cost",
                query: costQuery
            )
            async let compareReq: [CostVersionComparison] = NetworkService.shared.request(
                .get,
                "/recipes/\(recipeId)/versions/compare"
            )

            let (newCost, newComparisons) = try await (costReq, compareReq)
            self.recipe = updatedRecipe
            self.cost = newCost
            self.comparisons = newComparisons
            self.optimisticMargin = nil
        } catch {
            self.optimisticMargin = nil
            self.actionErrorMessage = error.localizedDescription
        }
        isUpdatingMargin = false
    }

    /// Abre una línea de ingrediente del desglose para ver detalles de la marca o ingrediente.
    func openIngredientLine(_ line: CostLine) async {
        guard loadingLine == nil else { return }
        loadingLine = line
        lineErrorMessage = nil
        defer { loadingLine = nil }

        do {
            if let presentationId = line.presentationId, !presentationId.isEmpty {
                let presentation: Presentation = try await NetworkService.shared.request(
                    .get,
                    "/presentations/\(presentationId)"
                )
                self.activeDestination = .presentation(presentation)
            } else {
                let ingredient: Ingredient = try await NetworkService.shared.request(
                    .get,
                    "/ingredients/\(line.refId)"
                )
                self.activeDestination = .ingredient(ingredient)
            }
        } catch where error.isCancellation {
            return
        } catch {
            self.lineErrorMessage = error.localizedDescription
        }
    }
}
