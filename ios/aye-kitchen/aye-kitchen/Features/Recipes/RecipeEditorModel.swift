import Foundation
import SwiftUI

/// Línea de ingrediente o subreceta dentro del editor de receta.
struct RecipeEditorLine: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: RecipeItemKind
    var refId: String
    var refName: String
    var quantity: String
    var unitId: String?
    var unitName: String?
    var pinnedPresentationId: String?
    var pinnedBrandName: String?

    init(
        id: UUID = UUID(),
        kind: RecipeItemKind,
        refId: String,
        refName: String,
        quantity: String,
        unitId: String? = nil,
        unitName: String? = nil,
        pinnedPresentationId: String? = nil,
        pinnedBrandName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.refId = refId
        self.refName = refName
        self.quantity = quantity
        self.unitId = unitId
        self.unitName = unitName
        self.pinnedPresentationId = pinnedPresentationId
        self.pinnedBrandName = pinnedBrandName
    }
}

// MARK: - Cuerpos de petición (docs/api-contract.md)

nonisolated struct RecipeItemInput: Encodable, Sendable {
    let kind: RecipeItemKind
    let refId: String
    let quantity: String
    let unitId: String?
    let pinnedPresentationId: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case refId
        case quantity
        case unitId
        case pinnedPresentationId
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

nonisolated struct ExtraCostInput: Encodable, Sendable {
    let name: String
    let costCents: Int
}

nonisolated struct RecipeCreateRequest: Encodable, Sendable {
    let name: String
    let description: String?
    let items: [RecipeItemInput]
    let extraCosts: [ExtraCostInput]
    let yieldQuantity: String
    let yieldUnit: BaseUnit
    let servings: Int?

    enum CodingKeys: String, CodingKey {
        case name, description, items, extraCosts, yieldQuantity, yieldUnit, servings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            try container.encode(description, forKey: .description)
        } else {
            try container.encodeNil(forKey: .description)
        }
        try container.encode(items, forKey: .items)
        try container.encode(extraCosts, forKey: .extraCosts)
        try container.encode(yieldQuantity, forKey: .yieldQuantity)
        try container.encode(yieldUnit, forKey: .yieldUnit)
        if let servings {
            try container.encode(servings, forKey: .servings)
        } else {
            try container.encodeNil(forKey: .servings)
        }
    }
}

nonisolated struct RecipePatchRequest: Encodable, Sendable {
    let name: String
    let description: String?
    let items: [RecipeItemInput]
    let extraCosts: [ExtraCostInput]
    let yieldQuantity: String
    let yieldUnit: BaseUnit
    let servings: Int?

    enum CodingKeys: String, CodingKey {
        case name, description, items, extraCosts, yieldQuantity, yieldUnit, servings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            try container.encode(description, forKey: .description)
        } else {
            try container.encodeNil(forKey: .description)
        }
        try container.encode(items, forKey: .items)
        try container.encode(extraCosts, forKey: .extraCosts)
        try container.encode(yieldQuantity, forKey: .yieldQuantity)
        try container.encode(yieldUnit, forKey: .yieldUnit)
        if let servings {
            try container.encode(servings, forKey: .servings)
        } else {
            try container.encodeNil(forKey: .servings)
        }
    }
}

// MARK: - Mapeo de errores

func userFacingRecipeError(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError.code {
        case "DUPLICATE_NAME":
            return "Ya tienes una receta con ese nombre."
        case "UNIT_NOT_CONVERTIBLE":
            return apiError.errorDescription ?? "Esa unidad no se puede convertir."
        case "RECIPE_CYCLE":
            return "Esa receta ya usa a esta. Una receta no puede llevarse a sí misma."
        case "RECIPE_TOO_DEEP":
            return "Hay demasiadas recetas una dentro de otra (máximo 10)."
        case "INVALID_REFERENCE":
            return "Uno de los ingredientes o marcas ya no existe."
        default:
            return apiError.errorDescription ?? error.localizedDescription
        }
    }
    return error.localizedDescription
}

// MARK: - Formateo de cantidad y unidad

func formatQuantityAndUnit(quantity: String, unitName: String?) -> String {
    let formattedQty = Quantity.format(quantity)
    guard let unitName = unitName, !unitName.isEmpty else {
        return formattedQty
    }
    let isSingle = (Quantity.parse(quantity) == "1")
    let lower = unitName.lowercased()
    let displayUnit: String
    if lower == "taza" || lower == "tz" {
        displayUnit = isSingle ? "taza" : "tazas"
    } else if lower == "cucharada" || lower == "cda" {
        displayUnit = isSingle ? "cucharada" : "cucharadas"
    } else if lower == "cucharadita" || lower == "cdta" {
        displayUnit = isSingle ? "cucharadita" : "cucharaditas"
    } else if lower == "pieza" || lower == "pz" {
        displayUnit = isSingle ? "pieza" : "piezas"
    } else if lower == "docena" || lower == "doc" {
        displayUnit = isSingle ? "docena" : "docenas"
    } else {
        displayUnit = unitName
    }
    return "\(formattedQty) \(displayUnit)"
}

// MARK: - ViewModel del Editor de Recetas

@Observable
final class RecipeEditorModel {
    let recipe: Recipe?

    var name: String = ""
    var descriptionText: String = ""
    var yieldQuantity: String = "1"
    var yieldUnit: BaseUnit = .pz
    var servings: Int? = nil
    var items: [RecipeEditorLine] = []
    var extraCosts: [ExtraCost] = []
    var allUnits: [MeasureUnit] = []

    var isSaving: Bool = false
    var errorMessage: String? = nil

    var isEditing: Bool { recipe != nil }

    var canSave: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { return false }
        guard let parsed = Quantity.parse(yieldQuantity), !parsed.isEmpty else { return false }
        return !isSaving
    }

    var hasUnsavedChanges: Bool {
        if let initial = recipe {
            if name != initial.name { return true }
            if descriptionText != (initial.description ?? "") { return true }
            if yieldQuantity != initial.yieldQuantity { return true }
            if yieldUnit != initial.yieldUnit { return true }
            if servings != initial.servings { return true }
            if extraCosts != initial.extraCosts { return true }

            if items.count != initial.items.count { return true }
            for (idx, item) in items.enumerated() {
                let initItem = initial.items[idx]
                if item.kind != initItem.kind ||
                    item.refId != initItem.refId ||
                    item.quantity != initItem.quantity ||
                    item.unitId != initItem.unitId ||
                    item.pinnedPresentationId != initItem.pinnedPresentationId {
                    return true
                }
            }
            return false
        } else {
            if !name.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            if !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            if yieldQuantity != "1" { return true }
            if yieldUnit != .pz { return true }
            if servings != nil { return true }
            if !items.isEmpty { return true }
            if !extraCosts.isEmpty { return true }
            return false
        }
    }

    init(recipe: Recipe? = nil, mockUnits: [MeasureUnit]? = nil) {
        self.recipe = recipe
        if let mockUnits {
            self.allUnits = mockUnits
        }
        if let recipe {
            self.name = recipe.name
            self.descriptionText = recipe.description ?? ""
            self.yieldQuantity = recipe.yieldQuantity
            self.yieldUnit = recipe.yieldUnit
            self.servings = recipe.servings
            self.items = recipe.items.map {
                RecipeEditorLine(
                    kind: $0.kind,
                    refId: $0.refId,
                    refName: $0.refName,
                    quantity: $0.quantity,
                    unitId: $0.unitId,
                    unitName: $0.unitName,
                    pinnedPresentationId: $0.pinnedPresentationId
                )
            }
            self.extraCosts = recipe.extraCosts
        }
    }

    func loadInitialData() async {
        do {
            if allUnits.isEmpty {
                let units: [MeasureUnit] = try await NetworkService.shared.request(.get, "/units/")
                self.allUnits = units
            }

            // Si hay líneas con pinnedPresentationId pero sin pinnedBrandName, resolver el nombre de la marca
            for idx in items.indices {
                if let pinnedId = items[idx].pinnedPresentationId,
                   items[idx].pinnedBrandName == nil,
                   items[idx].kind == .ingredient {
                    let ingId = items[idx].refId
                    if let presentations: Page<Presentation> = try? await NetworkService.shared.request(
                        .get,
                        "/presentations/",
                        query: [
                            URLQueryItem(name: "ingredient_id", value: ingId),
                            URLQueryItem(name: "limit", value: "100")
                        ]
                    ) {
                        if let pres = presentations.items.first(where: { $0.id == pinnedId }) {
                            items[idx].pinnedBrandName = pres.brand
                        }
                    }
                }
            }
        } catch {
            // Error silencioso al cargar unidades; se reflejará si intentan guardar
        }
    }

    func addLine(_ line: RecipeEditorLine) {
        items.append(line)
    }

    func updateLine(_ line: RecipeEditorLine) {
        if let index = items.firstIndex(where: { $0.id == line.id }) {
            items[index] = line
        }
    }

    func removeLine(_ line: RecipeEditorLine) {
        items.removeAll(where: { $0.id == line.id })
    }

    func addExtraCost(_ cost: ExtraCost) {
        extraCosts.append(cost)
    }

    func removeExtraCost(_ cost: ExtraCost) {
        extraCosts.removeAll(where: { $0.name == cost.name && $0.costCents == cost.costCents })
    }

    func save() async throws -> Recipe {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        guard let cleanName = name.trimmingCharacters(in: .whitespaces).nilIfEmpty else {
            throw APIError.server(status: 400, code: nil, message: "El nombre es obligatorio")
        }
        guard let parsedYield = Quantity.parse(yieldQuantity) else {
            throw APIError.server(status: 400, code: nil, message: "El rendimiento debe ser un número mayor a 0")
        }

        let itemInputs = items.map {
            RecipeItemInput(
                kind: $0.kind,
                refId: $0.refId,
                quantity: $0.quantity,
                unitId: $0.unitId,
                pinnedPresentationId: $0.pinnedPresentationId
            )
        }

        let extraCostInputs = extraCosts.map {
            ExtraCostInput(name: $0.name, costCents: $0.costCents)
        }

        if let recipe {
            let body = RecipePatchRequest(
                name: cleanName,
                description: descriptionText,
                items: itemInputs,
                extraCosts: extraCostInputs,
                yieldQuantity: parsedYield,
                yieldUnit: yieldUnit,
                servings: servings
            )
            let updated: Recipe = try await NetworkService.shared.request(
                .patch,
                "/recipes/\(recipe.id)",
                body: body
            )
            return updated
        } else {
            let body = RecipeCreateRequest(
                name: cleanName,
                description: descriptionText,
                items: itemInputs,
                extraCosts: extraCostInputs,
                yieldQuantity: parsedYield,
                yieldUnit: yieldUnit,
                servings: servings
            )
            let created: Recipe = try await NetworkService.shared.request(
                .post,
                "/recipes/",
                body: body
            )
            return created
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
