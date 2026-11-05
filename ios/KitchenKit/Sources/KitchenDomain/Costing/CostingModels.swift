import Foundation

public enum BrandSource: String, Codable, Sendable, Hashable {
    case version
    case recipe
    case current
}

public struct CurrentPresentation: Sendable, Hashable {
    public var presentation: Presentation
    public var priceRecord: PriceRecord

    public init(presentation: Presentation, priceRecord: PriceRecord) {
        self.presentation = presentation
        self.priceRecord = priceRecord
    }
}

public struct RecipeCostLine: Codable, Sendable, Hashable {
    public var kind: RecipeItemKind
    public var refId: String
    public var refName: String
    public var quantity: String
    public var unitName: String?
    public var quantityInBase: String
    public var baseUnit: BaseUnit
    public var presentationId: String?
    public var presentationLabel: String?
    public var pinned: Bool
    public var brandSource: BrandSource?
    public var costCents: Int
    public var missingPrice: Bool
    public var priceIsStale: Bool

    public init(
        kind: RecipeItemKind,
        refId: String,
        refName: String,
        quantity: String,
        unitName: String? = nil,
        quantityInBase: String,
        baseUnit: BaseUnit,
        presentationId: String? = nil,
        presentationLabel: String? = nil,
        pinned: Bool = false,
        brandSource: BrandSource? = nil,
        costCents: Int,
        missingPrice: Bool,
        priceIsStale: Bool = false
    ) {
        self.kind = kind
        self.refId = refId
        self.refName = refName
        self.quantity = quantity
        self.unitName = unitName
        self.quantityInBase = quantityInBase
        self.baseUnit = baseUnit
        self.presentationId = presentationId
        self.presentationLabel = presentationLabel
        self.pinned = pinned
        self.brandSource = brandSource
        self.costCents = costCents
        self.missingPrice = missingPrice
        self.priceIsStale = priceIsStale
    }

    private enum CodingKeys: CodingKey {
        case kind
        case refId
        case refName
        case quantity
        case unitName
        case quantityInBase
        case baseUnit
        case presentationId
        case presentationLabel
        case pinned
        case brandSource
        case costCents
        case missingPrice
        case priceIsStale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decode(RecipeItemKind.self, forKey: .kind)
        self.refId = try c.decode(String.self, forKey: .refId)
        self.refName = try c.decode(String.self, forKey: .refName)
        self.quantity = try c.decode(String.self, forKey: .quantity)
        self.unitName = try c.decodeIfPresent(String.self, forKey: .unitName)
        self.quantityInBase = try c.decode(String.self, forKey: .quantityInBase)
        self.baseUnit = try c.decode(BaseUnit.self, forKey: .baseUnit)
        self.presentationId = try c.decodeIfPresent(String.self, forKey: .presentationId)
        self.presentationLabel = try c.decodeIfPresent(String.self, forKey: .presentationLabel)
        self.pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.brandSource = try c.decodeIfPresent(BrandSource.self, forKey: .brandSource)
        self.costCents = try c.decode(Int.self, forKey: .costCents)
        self.missingPrice = try c.decode(Bool.self, forKey: .missingPrice)
        self.priceIsStale = try c.decodeIfPresent(Bool.self, forKey: .priceIsStale) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(refId, forKey: .refId)
        try c.encode(refName, forKey: .refName)
        try c.encode(quantity, forKey: .quantity)
        try c.encodeIfPresent(unitName, forKey: .unitName)
        try c.encode(quantityInBase, forKey: .quantityInBase)
        try c.encode(baseUnit, forKey: .baseUnit)
        try c.encodeIfPresent(presentationId, forKey: .presentationId)
        try c.encodeIfPresent(presentationLabel, forKey: .presentationLabel)
        try c.encode(pinned, forKey: .pinned)
        try c.encodeIfPresent(brandSource, forKey: .brandSource)
        try c.encode(costCents, forKey: .costCents)
        try c.encode(missingPrice, forKey: .missingPrice)
        try c.encode(priceIsStale, forKey: .priceIsStale)
    }
}

public struct RecipeCost: Codable, Sendable, Hashable {
    public var recipeId: String
    public var lines: [RecipeCostLine]
    public var ingredientsCostCents: Int
    public var extrasCostCents: Int
    public var batchCostCents: Int
    public var costPerYieldUnit: String
    public var costPerServingCents: Int?
    public var marginPercent: Int
    public var suggestedPriceCents: Int
    public var suggestedPricePerYieldUnitCents: Int
    public var complete: Bool
    public var hasStalePrices: Bool
    public var versionId: String?
    public var versionName: String?

    public init(
        recipeId: String,
        lines: [RecipeCostLine] = [],
        ingredientsCostCents: Int,
        extrasCostCents: Int,
        batchCostCents: Int,
        costPerYieldUnit: String,
        costPerServingCents: Int? = nil,
        marginPercent: Int,
        suggestedPriceCents: Int,
        suggestedPricePerYieldUnitCents: Int,
        complete: Bool,
        hasStalePrices: Bool = false,
        versionId: String? = nil,
        versionName: String? = nil
    ) {
        self.recipeId = recipeId
        self.lines = lines
        self.ingredientsCostCents = ingredientsCostCents
        self.extrasCostCents = extrasCostCents
        self.batchCostCents = batchCostCents
        self.costPerYieldUnit = costPerYieldUnit
        self.costPerServingCents = costPerServingCents
        self.marginPercent = marginPercent
        self.suggestedPriceCents = suggestedPriceCents
        self.suggestedPricePerYieldUnitCents = suggestedPricePerYieldUnitCents
        self.complete = complete
        self.hasStalePrices = hasStalePrices
        self.versionId = versionId
        self.versionName = versionName
    }

    private enum CodingKeys: CodingKey {
        case recipeId
        case lines
        case ingredientsCostCents
        case extrasCostCents
        case batchCostCents
        case costPerYieldUnit
        case costPerServingCents
        case marginPercent
        case suggestedPriceCents
        case suggestedPricePerYieldUnitCents
        case complete
        case hasStalePrices
        case versionId
        case versionName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.recipeId = try c.decode(String.self, forKey: .recipeId)
        self.lines = try c.decodeIfPresent([RecipeCostLine].self, forKey: .lines) ?? []
        self.ingredientsCostCents = try c.decode(Int.self, forKey: .ingredientsCostCents)
        self.extrasCostCents = try c.decode(Int.self, forKey: .extrasCostCents)
        self.batchCostCents = try c.decode(Int.self, forKey: .batchCostCents)
        self.costPerYieldUnit = try c.decode(String.self, forKey: .costPerYieldUnit)
        self.costPerServingCents = try c.decodeIfPresent(Int.self, forKey: .costPerServingCents)
        self.marginPercent = try c.decode(Int.self, forKey: .marginPercent)
        self.suggestedPriceCents = try c.decode(Int.self, forKey: .suggestedPriceCents)
        self.suggestedPricePerYieldUnitCents = try c.decode(Int.self, forKey: .suggestedPricePerYieldUnitCents)
        self.complete = try c.decode(Bool.self, forKey: .complete)
        self.hasStalePrices = try c.decodeIfPresent(Bool.self, forKey: .hasStalePrices) ?? false
        self.versionId = try c.decodeIfPresent(String.self, forKey: .versionId)
        self.versionName = try c.decodeIfPresent(String.self, forKey: .versionName)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recipeId, forKey: .recipeId)
        try c.encode(lines, forKey: .lines)
        try c.encode(ingredientsCostCents, forKey: .ingredientsCostCents)
        try c.encode(extrasCostCents, forKey: .extrasCostCents)
        try c.encode(batchCostCents, forKey: .batchCostCents)
        try c.encode(costPerYieldUnit, forKey: .costPerYieldUnit)
        try c.encodeIfPresent(costPerServingCents, forKey: .costPerServingCents)
        try c.encode(marginPercent, forKey: .marginPercent)
        try c.encode(suggestedPriceCents, forKey: .suggestedPriceCents)
        try c.encode(suggestedPricePerYieldUnitCents, forKey: .suggestedPricePerYieldUnitCents)
        try c.encode(complete, forKey: .complete)
        try c.encode(hasStalePrices, forKey: .hasStalePrices)
        try c.encodeIfPresent(versionId, forKey: .versionId)
        try c.encodeIfPresent(versionName, forKey: .versionName)
    }
}

public struct CostVersionComparison: Codable, Sendable, Hashable, Identifiable {
    public var versionId: String?
    public var name: String
    public var batchCostCents: Int
    public var costPerServingCents: Int?
    public var suggestedPriceCents: Int
    public var complete: Bool
    public var hasStalePrices: Bool

    public var id: String { versionId ?? "base" }

    public init(
        versionId: String? = nil,
        name: String,
        batchCostCents: Int,
        costPerServingCents: Int? = nil,
        suggestedPriceCents: Int,
        complete: Bool,
        hasStalePrices: Bool = false
    ) {
        self.versionId = versionId
        self.name = name
        self.batchCostCents = batchCostCents
        self.costPerServingCents = costPerServingCents
        self.suggestedPriceCents = suggestedPriceCents
        self.complete = complete
        self.hasStalePrices = hasStalePrices
    }

    private enum CodingKeys: CodingKey {
        case versionId
        case name
        case batchCostCents
        case costPerServingCents
        case suggestedPriceCents
        case complete
        case hasStalePrices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.versionId = try c.decodeIfPresent(String.self, forKey: .versionId)
        self.name = try c.decode(String.self, forKey: .name)
        self.batchCostCents = try c.decode(Int.self, forKey: .batchCostCents)
        self.costPerServingCents = try c.decodeIfPresent(Int.self, forKey: .costPerServingCents)
        self.suggestedPriceCents = try c.decode(Int.self, forKey: .suggestedPriceCents)
        self.complete = try c.decode(Bool.self, forKey: .complete)
        self.hasStalePrices = try c.decodeIfPresent(Bool.self, forKey: .hasStalePrices) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(versionId, forKey: .versionId)
        try c.encode(name, forKey: .name)
        try c.encode(batchCostCents, forKey: .batchCostCents)
        try c.encodeIfPresent(costPerServingCents, forKey: .costPerServingCents)
        try c.encode(suggestedPriceCents, forKey: .suggestedPriceCents)
        try c.encode(complete, forKey: .complete)
        try c.encode(hasStalePrices, forKey: .hasStalePrices)
    }
}
