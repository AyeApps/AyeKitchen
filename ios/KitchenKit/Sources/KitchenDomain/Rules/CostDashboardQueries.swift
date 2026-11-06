import Foundation

// MARK: - Modelos del Tablero de Costos de Recetas (K3)

/// Criterios de ordenamiento para el tablero de costos de recetas.
public enum CostDashboardSortOrder: String, Codable, Sendable, Hashable, CaseIterable {
    /// Alfabéticamente por nombre de la receta.
    case name
    /// Por costo de tanda descendente (mayor primero).
    case batchCost
    /// Por ganancia sugerida por tanda descendente (mayor primero).
    case suggestedProfit
    /// Primero las incompletas, luego las de precios viejos, luego por nombre.
    case needsReview

    public static let byName: CostDashboardSortOrder = .name
    public static let highestCost: CostDashboardSortOrder = .batchCost
    public static let highestProfit: CostDashboardSortOrder = .suggestedProfit
    public static let toReview: CostDashboardSortOrder = .needsReview
}

public typealias CostDashboardOrder = CostDashboardSortOrder
public typealias CostDashboardSort = CostDashboardSortOrder

/// Totales generales del tablero de costos.
public struct CostDashboardTotals: Codable, Sendable, Hashable {
    /// Número total de recetas activas.
    public var totalRecipes: Int
    /// Número de recetas con costeo incompleto (falta precio o error de cálculo).
    public var incompleteRecipes: Int
    /// Número de recetas con precios viejos.
    public var stalePriceRecipes: Int

    public var total: Int { totalRecipes }
    public var incomplete: Int { incompleteRecipes }
    public var stalePrices: Int { stalePriceRecipes }

    public init(totalRecipes: Int, incompleteRecipes: Int, stalePriceRecipes: Int) {
        self.totalRecipes = totalRecipes
        self.incompleteRecipes = incompleteRecipes
        self.stalePriceRecipes = stalePriceRecipes
    }
}

/// Fila individual del tablero de costos con los cálculos de una receta activa.
public struct CostDashboardItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var yieldQuantity: String
    public var yieldUnit: BaseUnit
    public var servings: Int?
    public var batchCostCents: Int?
    public var costPerYieldUnitCents: Int?
    public var costPerServingCents: Int?
    public var effectiveMarginPercent: Int
    public var suggestedPriceCents: Int?
    public var suggestedPricePerYieldUnitCents: Int?
    public var suggestedProfitCents: Int?
    public var complete: Bool
    public var hasStalePrices: Bool

    // Aliases convenientes
    public var marginPercent: Int { effectiveMarginPercent }
    public var suggestedBatchPriceCents: Int? { suggestedPriceCents }
    public var suggestedUnitPriceCents: Int? { suggestedPricePerYieldUnitCents }
    public var suggestedBatchProfitCents: Int? { suggestedProfitCents }
    public var profitCents: Int? { suggestedProfitCents }
    public var isComplete: Bool { complete }

    public init(
        id: String,
        name: String,
        yieldQuantity: String,
        yieldUnit: BaseUnit,
        servings: Int? = nil,
        batchCostCents: Int? = nil,
        costPerYieldUnitCents: Int? = nil,
        costPerServingCents: Int? = nil,
        effectiveMarginPercent: Int,
        suggestedPriceCents: Int? = nil,
        suggestedPricePerYieldUnitCents: Int? = nil,
        suggestedProfitCents: Int? = nil,
        complete: Bool,
        hasStalePrices: Bool = false
    ) {
        self.id = id
        self.name = name
        self.yieldQuantity = yieldQuantity
        self.yieldUnit = yieldUnit
        self.servings = servings
        self.batchCostCents = batchCostCents
        self.costPerYieldUnitCents = costPerYieldUnitCents
        self.costPerServingCents = costPerServingCents
        self.effectiveMarginPercent = effectiveMarginPercent
        self.suggestedPriceCents = suggestedPriceCents
        self.suggestedPricePerYieldUnitCents = suggestedPricePerYieldUnitCents
        self.suggestedProfitCents = suggestedProfitCents
        self.complete = complete
        self.hasStalePrices = hasStalePrices
    }
}

/// Resultado completo del tablero de costos de recetas, incluyendo totales e ítems ordenados.
public struct CostDashboard: Codable, Sendable, Hashable {
    public var totals: CostDashboardTotals
    public var items: [CostDashboardItem]

    public var totalRecipes: Int { totals.totalRecipes }
    public var incompleteRecipes: Int { totals.incompleteRecipes }
    public var stalePriceRecipes: Int { totals.stalePriceRecipes }

    public init(totals: CostDashboardTotals, items: [CostDashboardItem]) {
        self.totals = totals
        self.items = items
    }
}

extension CostDashboard: RandomAccessCollection {
    public typealias Element = CostDashboardItem
    public typealias Index = [CostDashboardItem].Index

    public var startIndex: Index { items.startIndex }
    public var endIndex: Index { items.endIndex }
    public subscript(position: Index) -> CostDashboardItem { items[position] }
}

// MARK: - Consultas sobre KitchenData

extension KitchenData {

    /// Genera el tablero de costos para todas las recetas activas con totales y orden configurable.
    public func costDashboard(
        order: CostDashboardSortOrder = .name,
        now: Date = Date()
    ) -> CostDashboard {
        let index = costingIndex()
        var costCache: [String: (batchCost: Decimal, isComplete: Bool, hasStalePrices: Bool)] = [:]

        let activeRecipes = recipes.filter { $0.isActive }

        var dashboardItems: [CostDashboardItem] = []
        dashboardItems.reserveCapacity(activeRecipes.count)

        for rec in activeRecipes {
            let effectiveMargin = rec.marginPercent ?? settings.defaultMarginPercent

            let item: CostDashboardItem
            do {
                let cost = try index.calculateRecipeCost(recipe: rec, version: nil, now: now, cache: &costCache)

                let costPerYieldUnitCents: Int?
                if let yieldDecimal = Qty.decimal(rec.yieldQuantity), yieldDecimal > 0,
                   let costPerYield = Decimal(string: cost.costPerYieldUnit) {
                    costPerYieldUnitCents = CostingMath.roundToCents(costPerYield)
                } else {
                    costPerYieldUnitCents = nil
                }

                let profitCents = cost.suggestedPriceCents - cost.batchCostCents

                item = CostDashboardItem(
                    id: rec.id,
                    name: rec.name,
                    yieldQuantity: rec.yieldQuantity,
                    yieldUnit: rec.yieldUnit,
                    servings: rec.servings,
                    batchCostCents: cost.batchCostCents,
                    costPerYieldUnitCents: costPerYieldUnitCents,
                    costPerServingCents: cost.costPerServingCents,
                    effectiveMarginPercent: cost.marginPercent,
                    suggestedPriceCents: cost.suggestedPriceCents,
                    suggestedPricePerYieldUnitCents: cost.suggestedPricePerYieldUnitCents,
                    suggestedProfitCents: profitCents,
                    complete: cost.complete,
                    hasStalePrices: cost.hasStalePrices
                )
            } catch {
                item = CostDashboardItem(
                    id: rec.id,
                    name: rec.name,
                    yieldQuantity: rec.yieldQuantity,
                    yieldUnit: rec.yieldUnit,
                    servings: rec.servings,
                    batchCostCents: nil,
                    costPerYieldUnitCents: nil,
                    costPerServingCents: nil,
                    effectiveMarginPercent: effectiveMargin,
                    suggestedPriceCents: nil,
                    suggestedPricePerYieldUnitCents: nil,
                    suggestedProfitCents: nil,
                    complete: false,
                    hasStalePrices: false
                )
            }
            dashboardItems.append(item)
        }

        let totals = CostDashboardTotals(
            totalRecipes: dashboardItems.count,
            incompleteRecipes: dashboardItems.filter { !$0.complete }.count,
            stalePriceRecipes: dashboardItems.filter { $0.hasStalePrices }.count
        )

        switch order {
        case .name:
            dashboardItems.sort { a, b in
                let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return a.id < b.id
            }
        case .batchCost:
            dashboardItems.sort { a, b in
                let costA = a.batchCostCents ?? -1
                let costB = b.batchCostCents ?? -1
                if costA != costB {
                    return costA > costB
                }
                let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return a.id < b.id
            }
        case .suggestedProfit:
            dashboardItems.sort { a, b in
                let profitA = a.suggestedProfitCents ?? Int.min
                let profitB = b.suggestedProfitCents ?? Int.min
                if profitA != profitB {
                    return profitA > profitB
                }
                let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return a.id < b.id
            }
        case .needsReview:
            dashboardItems.sort { a, b in
                func priority(_ item: CostDashboardItem) -> Int {
                    if !item.complete { return 0 }
                    if item.hasStalePrices { return 1 }
                    return 2
                }
                let prioA = priority(a)
                let prioB = priority(b)
                if prioA != prioB {
                    return prioA < prioB
                }
                let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return a.id < b.id
            }
        }

        return CostDashboard(totals: totals, items: dashboardItems)
    }

    /// Sobrecarga con etiqueta `sort`.
    public func costDashboard(
        sort: CostDashboardSortOrder,
        now: Date = Date()
    ) -> CostDashboard {
        costDashboard(order: sort, now: now)
    }

    // MARK: - Categorías de Gasto

    /// Categorías distintas de los gastos activos (sin vacías), ordenadas por cuántas
    /// veces se usaron (frecuencia descendente) y luego alfabéticamente por nombre.
    public func expenseCategories() -> [String] {
        var counts: [String: Int] = [:]
        for exp in expenses where exp.isActive {
            guard let raw = exp.category else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }

        return counts.keys.sorted { a, b in
            let countA = counts[a] ?? 0
            let countB = counts[b] ?? 0
            if countA != countB {
                return countA > countB
            }
            let cmp = a.localizedCaseInsensitiveCompare(b)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return a < b
        }
    }

    /// Alias para claridad y compatibilidad.
    public func activeExpenseCategories() -> [String] {
        expenseCategories()
    }
}
