import Foundation

// MARK: - Ganancia y Precios de Venta (Bloque K5)

/// Margen y ganancia en centavos y porcentaje sobre el costo.
public struct Profit: Sendable, Hashable {
    public var priceCents: Int
    public var costCents: Int
    public var profitCents: Int
    /// Ganancia ÷ costo × 100, redondeado a entero sobre el costo. Nulo si el costo es 0.
    public var percent: Int?

    public init(priceCents: Int, costCents: Int, profitCents: Int, percent: Int?) {
        self.priceCents = priceCents
        self.costCents = costCents
        self.profitCents = profitCents
        self.percent = percent
    }

    /// Construye `Profit` calculando `profitCents` y su porcentaje sobre el costo.
    public static func make(priceCents: Int, costCents: Int) -> Profit {
        let profit = priceCents - costCents
        let pct: Int?
        if costCents == 0 {
            pct = nil
        } else {
            let unrounded = (Decimal(profit) / Decimal(costCents)) * Decimal(100)
            pct = CostingMath.roundToCents(unrounded)
        }
        return Profit(
            priceCents: priceCents,
            costCents: costCents,
            profitCents: profit,
            percent: pct
        )
    }
}

/// "Tu precio" de una receta desglosado por tanda y por unidad de rendimiento.
public struct RecipeSalePrice: Sendable, Hashable {
    public var soldBy: OrderSoldBy
    public var batch: Profit
    public var perUnit: Profit

    public init(soldBy: OrderSoldBy, batch: Profit, perUnit: Profit) {
        self.soldBy = soldBy
        self.batch = batch
        self.perUnit = perUnit
    }
}

/// Tandas y sobrante calculados para surtir un pedido o conjunto de pedidos.
public struct BatchNeed: Sendable, Hashable, Identifiable {
    public var id: String { recipeId }
    public var recipeId: String
    public var recipeName: String
    public var yieldQuantity: String
    public var yieldUnit: BaseUnit
    public var neededUnits: String
    public var exactBatches: String
    public var wholeBatches: Int
    public var leftoverUnits: String
    public var leftoverValueCents: Int?

    public init(
        recipeId: String,
        recipeName: String,
        yieldQuantity: String,
        yieldUnit: BaseUnit,
        neededUnits: String,
        exactBatches: String,
        wholeBatches: Int,
        leftoverUnits: String,
        leftoverValueCents: Int?
    ) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.yieldQuantity = yieldQuantity
        self.yieldUnit = yieldUnit
        self.neededUnits = neededUnits
        self.exactBatches = exactBatches
        self.wholeBatches = wholeBatches
        self.leftoverUnits = leftoverUnits
        self.leftoverValueCents = leftoverValueCents
    }
}

// MARK: - Funciones de Precio Propio y Ganancia Sugerida

/// Calcula el desglose de precio propio por tanda y por unidad de rendimiento. Nulo si la receta no tiene precio propio.
public func salePrice(of recipe: Recipe, cost: RecipeCost) -> RecipeSalePrice? {
    guard let priceCents = recipe.salePriceCents else { return nil }
    let soldBy = recipe.salePriceSoldBy ?? .batch
    let yieldQty = Qty.decimal(recipe.yieldQuantity) ?? Decimal(1)
    let effectiveYield = yieldQty > Decimal(0) ? yieldQty : Decimal(1)

    let batchCostCents = cost.batchCostCents
    let perUnitCostCents = CostingMath.roundToCents(Qty.decimal(cost.costPerYieldUnit) ?? Decimal(0))

    let batchPriceCents: Int
    let perUnitPriceCents: Int

    switch soldBy {
    case .batch:
        batchPriceCents = priceCents
        let unroundedPerUnit = Decimal(priceCents) / effectiveYield
        perUnitPriceCents = CostingMath.roundToCents(unroundedPerUnit)
    case .unit:
        perUnitPriceCents = priceCents
        let unroundedBatch = Decimal(priceCents) * effectiveYield
        batchPriceCents = CostingMath.roundToCents(unroundedBatch)
    }

    let batchProfit = Profit.make(priceCents: batchPriceCents, costCents: batchCostCents)
    let perUnitProfit = Profit.make(priceCents: perUnitPriceCents, costCents: perUnitCostCents)

    return RecipeSalePrice(soldBy: soldBy, batch: batchProfit, perUnit: perUnitProfit)
}

/// Ganancia sugerida por tanda contra su costo.
public func suggestedProfit(cost: RecipeCost) -> Profit {
    Profit.make(priceCents: cost.suggestedPriceCents, costCents: cost.batchCostCents)
}

// MARK: - Consultas sobre KitchenData

extension KitchenData {

    /// Desglose de precio propio de la receta. Nulo si no tiene precio propio.
    public func salePrice(of recipe: Recipe, cost: RecipeCost) -> RecipeSalePrice? {
        KitchenDomain.salePrice(of: recipe, cost: cost)
    }

    /// Ganancia sugerida por tanda contra su costo.
    public func suggestedProfit(cost: RecipeCost) -> Profit {
        KitchenDomain.suggestedProfit(cost: cost)
    }

    /// Precio por defecto de una línea: precio propio si la receta tiene, si no el sugerido.
    public func defaultLinePriceCents(recipeId: String, soldBy: OrderSoldBy, cost: RecipeCost) -> Int {
        if let rec = recipes.active(recipeId) ?? recipes.first(where: { $0.id == recipeId }),
           let custom = salePrice(of: rec, cost: cost) {
            switch soldBy {
            case .batch:
                return custom.batch.priceCents
            case .unit:
                return custom.perUnit.priceCents
            }
        }

        switch soldBy {
        case .batch:
            return cost.suggestedPriceCents
        case .unit:
            return cost.suggestedPricePerYieldUnitCents
        }
    }

    /// Tandas necesarias y sobrante para surtir un pedido.
    public func batchNeeds(for order: Order) -> [BatchNeed] {
        batchNeeds(for: [order])
    }

    /// Tandas necesarias y sobrante acumulados para surtir varios pedidos.
    public func batchNeeds(for orders: [Order], now: Date = Date()) -> [BatchNeed] {
        var orderedRecipeIds: [String] = []
        var neededUnitsByRecipe: [String: Decimal] = [:]

        for order in orders {
            for item in order.items {
                guard let recipe = recipes.active(item.recipeId) else {
                    // "si la receta ya no existe, sáltala"
                    continue
                }
                guard let itemQty = Qty.decimal(item.quantity), itemQty > Decimal(0) else {
                    continue
                }
                guard let recipeYield = Qty.decimal(recipe.yieldQuantity), recipeYield > Decimal(0) else {
                    continue
                }

                let units: Decimal
                switch item.soldBy {
                case .batch:
                    units = itemQty * recipeYield
                case .unit:
                    units = itemQty
                }

                if neededUnitsByRecipe[recipe.id] == nil {
                    orderedRecipeIds.append(recipe.id)
                    neededUnitsByRecipe[recipe.id] = units
                } else {
                    neededUnitsByRecipe[recipe.id]! += units
                }
            }
        }

        let index = costingIndex()
        var recipeCostCache: [String: RecipeCost] = [:]
        var result: [BatchNeed] = []

        for recipeId in orderedRecipeIds {
            guard let recipe = recipes.active(recipeId),
                  let neededUnitsDecimal = neededUnitsByRecipe[recipeId],
                  let recipeYield = Qty.decimal(recipe.yieldQuantity),
                  recipeYield > Decimal(0) else {
                continue
            }

            let exactBatchesDecimal = neededUnitsDecimal / recipeYield

            // exactBatches: decimal hasta 2 decimales
            var roundedExact = Decimal()
            var inputExact = exactBatchesDecimal
            NSDecimalRound(&roundedExact, &inputExact, 2, .plain)
            let exactBatchesStr = Qty.text(roundedExact)

            // wholeBatches: redondeo hacia arriba (.up)
            var ceilResult = Decimal()
            var inputCeil = exactBatchesDecimal
            NSDecimalRound(&ceilResult, &inputCeil, 0, .up)
            let wholeBatches = NSDecimalNumber(decimal: ceilResult).intValue

            // leftoverUnits: wholeBatches × rendimiento − necesario
            let leftoverUnitsDecimal = (Decimal(wholeBatches) * recipeYield) - neededUnitsDecimal
            let leftoverUnitsStr = Qty.text(leftoverUnitsDecimal)

            // leftoverValueCents: lo que sobra × precio por unidad
            let leftoverValueCents: Int?
            if leftoverUnitsDecimal > Decimal(0) {
                let costInfo: RecipeCost?
                if let cached = recipeCostCache[recipeId] {
                    costInfo = cached
                } else {
                    costInfo = try? index.calculateRecipeCost(recipe: recipe, version: nil, now: now)
                    if let c = costInfo {
                        recipeCostCache[recipeId] = c
                    }
                }

                if let cost = costInfo {
                    let unitPrice = defaultLinePriceCents(recipeId: recipe.id, soldBy: .unit, cost: cost)
                    let unroundedValue = leftoverUnitsDecimal * Decimal(unitPrice)
                    leftoverValueCents = CostingMath.roundToCents(unroundedValue)
                } else {
                    leftoverValueCents = nil
                }
            } else {
                leftoverValueCents = nil
            }

            result.append(
                BatchNeed(
                    recipeId: recipe.id,
                    recipeName: recipe.name,
                    yieldQuantity: recipe.yieldQuantity,
                    yieldUnit: recipe.yieldUnit,
                    neededUnits: Qty.text(neededUnitsDecimal),
                    exactBatches: exactBatchesStr,
                    wholeBatches: wholeBatches,
                    leftoverUnits: leftoverUnitsStr,
                    leftoverValueCents: leftoverValueCents
                )
            )
        }

        return result
    }
}
