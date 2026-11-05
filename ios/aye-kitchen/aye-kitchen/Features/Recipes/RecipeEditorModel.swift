import Foundation
import SwiftUI
import KitchenDomain
import Observation

/// Modo del editor de receta.
enum RecipeEditorMode: Sendable, Hashable {
    case create
    case edit(recipeId: String)
}

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

// MARK: - Mapeo de errores

func userFacingRecipeError(_ error: Error) -> String {
    if let domainError = error as? DomainError {
        switch domainError {
        case .duplicateName:
            return "Ya tienes una receta con ese nombre."
        case .unitNotConvertible(let detail):
            return detail.isEmpty ? "Esa unidad no se puede convertir." : detail
        case .recipeCycle:
            return "Esa receta ya usa a esta. Una receta no puede llevarse a sí misma."
        case .recipeTooDeep:
            return "Hay demasiadas recetas una dentro de otra (máximo 10)."
        case .invalidReference(let detail):
            return detail.isEmpty ? "Uno de los ingredientes o marcas ya no existe." : detail
        default:
            return domainError.localizedDescription
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
    let mode: RecipeEditorMode
    private let store: LocalStore

    var name: String = ""
    var descriptionText: String = ""
    var yieldQuantity: String = "1"
    var yieldUnit: BaseUnit = .pz
    var servings: Int? = nil
    var items: [RecipeEditorLine] = []
    var extraCosts: [ExtraCost] = []
    var allUnits: [KitchenUnit] = []

    var isSaving: Bool = false
    var errorMessage: String? = nil

    // Snapshots para hasUnsavedChanges
    private var initialName: String = ""
    private var initialDescription: String = ""
    private var initialYieldQuantity: String = "1"
    private var initialYieldUnit: BaseUnit = .pz
    private var initialServings: Int? = nil
    private var initialItems: [RecipeEditorLine] = []
    private var initialExtraCosts: [ExtraCost] = []

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var canSave: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { return false }
        guard let parsed = Quantity.parse(yieldQuantity), !parsed.isEmpty else { return false }
        return !isSaving
    }

    var hasUnsavedChanges: Bool {
        if isEditing {
            if name != initialName { return true }
            if descriptionText != initialDescription { return true }
            if yieldQuantity != initialYieldQuantity { return true }
            if yieldUnit != initialYieldUnit { return true }
            if servings != initialServings { return true }
            if extraCosts != initialExtraCosts { return true }

            if items.count != initialItems.count { return true }
            for (idx, item) in items.enumerated() {
                let initItem = initialItems[idx]
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

    init(mode: RecipeEditorMode = .create, store: LocalStore = .shared) {
        self.mode = mode
        self.store = store
        let units = store.data.availableKitchenUnits()
        self.allUnits = units

        if case .edit(let recipeId) = mode, let recipe = store.data.recipe(id: recipeId) {
            self.name = recipe.name
            self.descriptionText = recipe.description ?? ""
            self.yieldQuantity = recipe.yieldQuantity
            self.yieldUnit = recipe.yieldUnit
            self.servings = recipe.servings
            self.extraCosts = recipe.extraCosts

            var mappedLines: [RecipeEditorLine] = []
            for it in recipe.items {
                let refName: String
                switch it.kind {
                case .ingredient:
                    refName = store.data.ingredients.first(where: { $0.id == it.refId })?.name ?? ""
                case .recipe:
                    refName = store.data.recipes.first(where: { $0.id == it.refId })?.name ?? ""
                }
                let unitName = it.unitId.flatMap { uid in units.first(where: { $0.id == uid })?.name }
                let brandName = it.pinnedPresentationId.flatMap { pid in
                    store.data.presentations.first(where: { $0.id == pid })?.brand
                }

                mappedLines.append(RecipeEditorLine(
                    kind: it.kind,
                    refId: it.refId,
                    refName: refName,
                    quantity: it.quantity,
                    unitId: it.unitId,
                    unitName: unitName,
                    pinnedPresentationId: it.pinnedPresentationId,
                    pinnedBrandName: brandName
                ))
            }
            self.items = mappedLines

            // Guardar snapshot inicial
            self.initialName = recipe.name
            self.initialDescription = recipe.description ?? ""
            self.initialYieldQuantity = recipe.yieldQuantity
            self.initialYieldUnit = recipe.yieldUnit
            self.initialServings = recipe.servings
            self.initialExtraCosts = recipe.extraCosts
            self.initialItems = mappedLines
        }
    }

    func loadTarget(for item: RecipeEditorLine) -> LineTarget? {
        if item.kind == .ingredient {
            if let ing = store.data.ingredients.first(where: { $0.id == item.refId && $0.isActive }) {
                return .ingredient(ing)
            }
        } else {
            if let rec = store.data.recipes.first(where: { $0.id == item.refId && $0.isActive }) {
                return .subrecipe(id: rec.id, name: rec.name, yieldUnit: rec.yieldUnit)
            }
        }
        return nil
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

    func save() throws -> Recipe {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let cleanName = name.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else {
            throw DomainError.invalidValue(detail: "El nombre es obligatorio")
        }
        guard let parsedYield = Quantity.parse(yieldQuantity) else {
            throw DomainError.invalidValue(detail: "El rendimiento debe ser un número mayor a 0")
        }

        let domainItems = items.map {
            RecipeItem(
                kind: $0.kind,
                refId: $0.refId,
                quantity: $0.quantity,
                unitId: $0.unitId,
                pinnedPresentationId: $0.pinnedPresentationId
            )
        }

        switch mode {
        case .create:
            return try store.mutate { data, ctx in
                try data.createRecipe(
                    name: cleanName,
                    description: descriptionText.isEmpty ? nil : descriptionText,
                    items: domainItems,
                    extraCosts: extraCosts,
                    yieldQuantity: parsedYield,
                    yieldUnit: yieldUnit,
                    servings: servings,
                    ctx: ctx
                )
            }
        case .edit(let recipeId):
            return try store.mutate { data, ctx in
                try data.updateRecipe(
                    id: recipeId,
                    name: cleanName,
                    description: descriptionText.isEmpty ? nil : descriptionText,
                    items: domainItems,
                    extraCosts: extraCosts,
                    yieldQuantity: parsedYield,
                    yieldUnit: yieldUnit,
                    servings: servings,
                    ctx: ctx
                )
            }
        }
    }
}
