import Foundation
import SwiftUI

/// Destino de la línea: ingrediente o subreceta.
enum LineTarget: Hashable, Sendable, Identifiable {
    case ingredient(Ingredient)
    case subrecipe(id: String, name: String, yieldUnit: BaseUnit)

    var id: String {
        switch self {
        case .ingredient(let ing): "ing_\(ing.id)"
        case .subrecipe(let id, _, _): "rec_\(id)"
        }
    }

    var name: String {
        switch self {
        case .ingredient(let ing): ing.name
        case .subrecipe(_, let name, _): name
        }
    }

    var baseUnit: BaseUnit {
        switch self {
        case .ingredient(let ing): ing.baseUnit
        case .subrecipe(_, _, let yieldUnit): yieldUnit
        }
    }

    var kind: RecipeItemKind {
        switch self {
        case .ingredient: .ingredient
        case .subrecipe: .recipe
        }
    }

    var refId: String {
        switch self {
        case .ingredient(let ing): ing.id
        case .subrecipe(let id, _, _): id
        }
    }
}

// MARK: - Cuerpos de petición para equivalencias (PATCH /ingredients/{id})

nonisolated struct RecipeLineConversionInput: Encodable, Sendable {
    let unitId: String
    let quantityInBase: String
}

nonisolated struct IngredientConversionsPatchRequest: Encodable, Sendable {
    let conversions: [RecipeLineConversionInput]
}

// MARK: - Helpers de texto y unidades

func unitDisplayLabel(for unit: MeasureUnit) -> String {
    if unit.abbreviation == "tz" {
        return "taza"
    }
    return unit.abbreviation
}

func unitDisplayPlural(for unit: MeasureUnit, qty: String) -> String {
    let isSingle = (Quantity.parse(qty) == "1")
    let lower = unit.abbreviation.lowercased()
    if lower == "tz" {
        return isSingle ? "taza" : "tazas"
    } else if lower == "cda" {
        return isSingle ? "cda" : "cdas"
    } else if lower == "cdta" {
        return isSingle ? "cdta" : "cdtas"
    } else if lower == "pz" {
        return isSingle ? "pz" : "pzs"
    } else if lower == "doc" {
        return isSingle ? "docena" : "docenas"
    }
    return unit.abbreviation
}

func equivalenceQuestionText(ingredientName: String, baseUnit: BaseUnit, unitName: String) -> String {
    let lowerName = ingredientName.lowercased()
    let basePlural: String = switch baseUnit {
    case .g: "gramos"
    case .ml: "mililitros"
    case .pz: "piezas"
    }
    let questionVerb: String = switch baseUnit {
    case .g: "¿Cuánto pesa"
    case .ml: "¿Cuánto mide"
    case .pz: "¿Cuántas piezas son"
    }

    let article: String
    if lowerName.hasPrefix("el ") || lowerName.hasPrefix("la ") || lowerName.hasPrefix("los ") || lowerName.hasPrefix("las ") {
        article = ""
    } else {
        article = "La "
    }
    return "\(article)\(lowerName) la compras por \(basePlural). \(questionVerb) 1 \(unitName) de \(lowerName)? Solo te lo preguntamos una vez."
}

// MARK: - ViewModel de Hoja de Línea

@Observable
final class RecipeLineModel {
    var target: LineTarget
    var allUnits: [MeasureUnit]
    var existingLine: RecipeEditorLine?

    var quantityText: String = "1"
    var selectedUnitId: String = ""
    var pinnedPresentationId: String? = nil
    var presentations: [Presentation] = []
    var isLoadingPresentations: Bool = false

    var equivalenceQuantity: String = ""
    var isSavingEquivalence: Bool = false
    var errorMessage: String? = nil

    private(set) var isMock: Bool = false

    init(
        target: LineTarget,
        existingLine: RecipeEditorLine? = nil,
        allUnits: [MeasureUnit],
        mockPresentations: [Presentation]? = nil
    ) {
        self.target = target
        self.existingLine = existingLine
        self.allUnits = allUnits

        if let existingLine {
            self.quantityText = existingLine.quantity
            self.pinnedPresentationId = existingLine.pinnedPresentationId
            if let unitId = existingLine.unitId {
                self.selectedUnitId = unitId
            }
        }

        if let mockPresentations {
            self.presentations = mockPresentations
            self.isMock = true
        }

        // Si selectedUnitId sigue vacío, asignar la por defecto
        if selectedUnitId.isEmpty {
            self.selectedUnitId = defaultUnitId(for: target, allUnits: allUnits)
        }
    }

    private func defaultUnitId(for target: LineTarget, allUnits: [MeasureUnit]) -> String {
        let base = target.baseUnit
        let targetAbbr: String = switch base {
        case .g: "g"
        case .ml: "ml"
        case .pz: "pz"
        }
        if let match = allUnits.first(where: { $0.abbreviation == targetAbbr }) {
            return match.id
        }
        // Fallback al primer match con la misma base
        if let matchBase = allUnits.first(where: { $0.baseUnit == base }) {
            return matchBase.id
        }
        return allUnits.first?.id ?? ""
    }

    // MARK: - Unidades disponibles y filtros

    var availableUnits: [MeasureUnit] {
        switch target {
        case .ingredient:
            return allUnits
        case .subrecipe(_, _, let yieldUnit):
            return allUnits.filter { $0.baseUnit == yieldUnit }
        }
    }

    var primaryUnits: [MeasureUnit] {
        let abbreviations: [String] = switch target.baseUnit {
        case .g: ["g", "kg", "tz", "cda", "cdta"]
        case .ml: ["ml", "l", "tz", "cda", "cdta"]
        case .pz: ["pz", "doc"]
        }

        switch target {
        case .ingredient:
            return abbreviations.compactMap { abbr in
                allUnits.first(where: { $0.abbreviation == abbr })
            }
        case .subrecipe(_, _, let yieldUnit):
            return abbreviations.compactMap { abbr in
                allUnits.first(where: { $0.abbreviation == abbr && $0.baseUnit == yieldUnit })
            }
        }
    }

    var moreUnits: [MeasureUnit] {
        let primaryIds = Set(primaryUnits.map(\.id))
        return availableUnits.filter { !primaryIds.contains($0.id) }
    }

    var selectedUnit: MeasureUnit? {
        allUnits.first(where: { $0.id == selectedUnitId })
    }

    var isUnitInMore: Bool {
        guard let selected = selectedUnit else { return false }
        return moreUnits.contains(where: { $0.id == selected.id })
    }

    // MARK: - Equivalencia

    var isUnitConvertible: Bool {
        guard case .ingredient(let ing) = target else {
            return true
        }
        guard let selectedUnit else {
            return true
        }
        if selectedUnit.baseUnit == ing.baseUnit {
            return true
        }
        if ing.conversions.contains(where: { $0.unitId == selectedUnitId }) {
            return true
        }
        return false
    }

    var canSave: Bool {
        guard Quantity.parse(quantityText) != nil else { return false }
        if !isUnitConvertible {
            guard Quantity.parse(equivalenceQuantity) != nil else { return false }
        }
        return !isSavingEquivalence
    }

    // MARK: - Pasos de cantidad

    func incrementQuantity() {
        let current = Decimal(string: Quantity.parse(quantityText) ?? "1") ?? 1
        let next: Decimal
        if current < 1 {
            next = current + Decimal(string: "0.25")!
        } else {
            next = current + 1
        }
        quantityText = "\(next)"
    }

    func decrementQuantity() {
        let current = Decimal(string: Quantity.parse(quantityText) ?? "1") ?? 1
        let next: Decimal
        if current <= 1 {
            next = max(Decimal(string: "0.25")!, current - Decimal(string: "0.25")!)
        } else {
            next = max(Decimal(string: "0.25")!, current - 1)
        }
        quantityText = "\(next)"
    }

    // MARK: - Presentaciones / Marcas

    func loadPresentations() async {
        guard case .ingredient(let ing) = target, !isMock else { return }
        isLoadingPresentations = true
        defer { isLoadingPresentations = false }

        do {
            let page: Page<Presentation> = try await NetworkService.shared.request(
                .get,
                "/presentations/",
                query: [
                    URLQueryItem(name: "ingredient_id", value: ing.id),
                    URLQueryItem(name: "limit", value: "100")
                ]
            )
            self.presentations = page.items
        } catch {
            // Se muestra estado de error o aviso sin marcas
        }
    }

    var currentOrPinnedPresentation: Presentation? {
        if let pinnedId = pinnedPresentationId,
           let match = presentations.first(where: { $0.id == pinnedId }) {
            return match
        }
        return presentations.first(where: { $0.isCurrent }) ??
               presentations.first(where: { $0.latestPriceCents != nil }) ??
               presentations.first
    }

    func presentationTitle(_ p: Presentation) -> String {
        if let sup = p.supplierName, !sup.isEmpty {
            return "\(p.brand) · \(sup)"
        }
        return p.brand
    }

    func presentationSubtitle(_ p: Presentation) -> String {
        if let cents = p.latestPriceCents {
            let priceFormatted = Money.format(cents: cents)
            let qtyFormatted = Quantity.format(p.packageQuantity)
            let unitStr = p.baseUnit.rawValue
            let label = (p.id == pinnedPresentationId) ? "marca fijada" : "el precio más reciente"
            return "\(priceFormatted) por \(qtyFormatted) \(unitStr) · \(label)"
        }
        return "Sin precio registrado"
    }

    // MARK: - Resumen de equivalencia y costo estimado

    var quantityInBase: Decimal? {
        guard let parsed = Quantity.parse(quantityText),
              let qtyDecimal = Decimal(string: parsed),
              qtyDecimal > 0,
              let unit = selectedUnit else {
            return nil
        }

        switch target {
        case .ingredient(let ing):
            if unit.baseUnit == ing.baseUnit {
                let factor = Decimal(string: unit.factorToBase) ?? 1
                return qtyDecimal * factor
            } else if let conv = ing.conversions.first(where: { $0.unitId == selectedUnitId }),
                      let convDec = Decimal(string: conv.quantityInBase) {
                return qtyDecimal * convDec
            } else if let eqParsed = Quantity.parse(equivalenceQuantity),
                      let eqDec = Decimal(string: eqParsed) {
                return qtyDecimal * eqDec
            } else {
                return nil
            }
        case .subrecipe(_, _, let yieldUnit):
            if unit.baseUnit == yieldUnit {
                let factor = Decimal(string: unit.factorToBase) ?? 1
                return qtyDecimal * factor
            } else {
                return nil
            }
        }
    }

    var conversionSummaryText: String {
        let formattedQty = Quantity.format(quantityText)
        guard let unit = selectedUnit else { return formattedQty }
        let unitLabel = unitDisplayPlural(for: unit, qty: quantityText)

        if let inBase = quantityInBase {
            let baseUnitStr = target.baseUnit.rawValue
            let formattedBase = Quantity.format("\(inBase)")
            if unit.abbreviation == baseUnitStr {
                return "\(formattedQty) \(baseUnitStr)"
            } else {
                return "\(formattedQty) \(unitLabel) = \(formattedBase) \(baseUnitStr)"
            }
        }
        return "\(formattedQty) \(unitLabel)"
    }

    var estimatedCostText: String? {
        guard let inBase = quantityInBase,
              let pres = currentOrPinnedPresentation,
              let priceCents = pres.latestPriceCents,
              let pkgQty = Decimal(string: pres.packageQuantity),
              pkgQty > 0 else {
            return nil
        }

        let totalCents = inBase * Decimal(priceCents) / pkgQty
        var rounded = Decimal()
        var copy = totalCents
        NSDecimalRound(&rounded, &copy, 0, .plain)
        let cents = (rounded as NSDecimalNumber).intValue
        return Money.format(cents: cents)
    }

    // MARK: - Guardar la línea

    func saveLine() async throws -> RecipeEditorLine {
        guard let parsedQty = Quantity.parse(quantityText) else {
            throw APIError.server(status: 400, code: nil, message: "Cantidad no válida")
        }
        guard let selectedUnit else {
            throw APIError.server(status: 400, code: nil, message: "Unidad no válida")
        }

        // Si falta equivalencia, guardarla en el ingrediente primero
        if case .ingredient(let ing) = target, !isUnitConvertible {
            guard let eqQty = Quantity.parse(equivalenceQuantity) else {
                throw APIError.server(status: 400, code: nil, message: "Falta responder la pregunta de equivalencia")
            }
            isSavingEquivalence = true
            defer { isSavingEquivalence = false }

            let existingInputs = ing.conversions.map {
                RecipeLineConversionInput(unitId: $0.unitId, quantityInBase: $0.quantityInBase)
            }
            let newConv = RecipeLineConversionInput(unitId: selectedUnitId, quantityInBase: eqQty)
            let patchBody = IngredientConversionsPatchRequest(conversions: existingInputs + [newConv])

            let updated: Ingredient = try await NetworkService.shared.request(
                .patch,
                "/ingredients/\(ing.id)",
                body: patchBody
            )
            target = .ingredient(updated)
        }

        let brandName: String? = if let pinnedId = pinnedPresentationId {
            presentations.first(where: { $0.id == pinnedId })?.brand
        } else {
            nil
        }

        return RecipeEditorLine(
            id: existingLine?.id ?? UUID(),
            kind: target.kind,
            refId: target.refId,
            refName: target.name,
            quantity: parsedQty,
            unitId: selectedUnit.id,
            unitName: selectedUnit.name,
            pinnedPresentationId: pinnedPresentationId,
            pinnedBrandName: brandName
        )
    }
}
