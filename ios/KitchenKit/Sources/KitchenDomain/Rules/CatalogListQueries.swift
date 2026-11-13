import Foundation

// MARK: - Catálogo con búsqueda, filtros y orden (K7)

/// Cómo se ordena la lista del catálogo.
public enum CatalogSort: String, Sendable, Hashable, CaseIterable {
    /// Por grupo y dentro por nombre (lo de siempre).
    case group
    /// Por nombre del ingrediente, A–Z, sin grupos.
    case name
    /// Precio del paquete de la marca mostrada, de menor a mayor; sin precio al final.
    case priceLowToHigh
    /// Precio del paquete de la marca mostrada, de mayor a menor; sin precio al final.
    case priceHighToLow
    /// Precio más viejo primero (para saber qué actualizar); sin precio al final.
    case oldestPrice
}

/// Filtro por tienda.
public enum CatalogStoreFilter: Sendable, Hashable {
    case all
    /// Solo ingredientes con al menos una marca activa de esa tienda (`Supplier.id`).
    case store(id: String)
    /// Solo ingredientes con al menos una marca activa sin tienda.
    case noStore
}

/// Filtro por precio.
public enum CatalogPriceFilter: Sendable, Hashable {
    case all
    /// Ingredientes sin marcas o cuyas marcas (las que pasan el filtro de tienda) no tienen precio.
    case withoutPrice
    /// La marca mostrada tiene precio viejo (`priceIsStale`).
    case stale
    /// Precio del paquete de la marca mostrada dentro del rango, en centavos, ambos extremos incluidos.
    /// Un extremo nulo = sin límite de ese lado.
    case range(minCents: Int?, maxCents: Int?)
}

public struct CatalogFilter: Sendable, Hashable {
    /// Busca en nombre del ingrediente, grupo, nombre de marca y nombre de tienda.
    public var query: String
    public var store: CatalogStoreFilter
    /// Nombre exacto del grupo; nulo = todos.
    public var group: String?
    public var price: CatalogPriceFilter
    public var sort: CatalogSort

    public init(query: String = "", store: CatalogStoreFilter = .all, group: String? = nil,
                price: CatalogPriceFilter = .all, sort: CatalogSort = .group) {
        self.query = query
        self.store = store
        self.group = group
        self.price = price
        self.sort = sort
    }

    /// Verdadero si hay algún filtro aparte de la búsqueda y el orden.
    public var hasFilters: Bool {
        store != .all || group != nil || price != .all
    }
}

/// Un renglón del catálogo: el ingrediente y la marca que conviene mostrar con él.
public struct CatalogListItem: Sendable, Hashable, Identifiable {
    public var id: String { ingredient.id }
    public var ingredient: CatalogIngredient
    /// La marca que representa al ingrediente con estos filtros (ver K7). Nula si no tiene marcas que apliquen.
    public var shownBrand: CatalogPresentation?
    /// Verdadero cuando la pantalla debe mostrar `shownBrand` en el renglón (hay filtro de tienda o precio,
    /// orden por precio, o la búsqueda encontró la marca o la tienda y no el nombre del ingrediente).
    public var highlightsBrand: Bool

    public init(ingredient: CatalogIngredient, shownBrand: CatalogPresentation? = nil, highlightsBrand: Bool = false) {
        self.ingredient = ingredient
        self.shownBrand = shownBrand
        self.highlightsBrand = highlightsBrand
    }
}

extension KitchenData {
    /// Lista del catálogo con búsqueda, filtros y orden.
    public func catalogList(_ filter: CatalogFilter, now: Date = Date()) -> [CatalogListItem] {
        let base = activeIngredients(now: now)
        let trimmedQuery = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = filter.group?.trimmingCharacters(in: .whitespacesAndNewlines)

        var result: [CatalogListItem] = []
        let index = costingIndex()
        let presentationsByIngredient = Dictionary(grouping: presentations.filter { $0.isActive }, by: \.ingredientId)

        for catIng in base {
            // 5. Filtro por grupo (exacto, sin espacios a los lados)
            if let targetGroup = trimmedGroup, !targetGroup.isEmpty {
                let ingGroup = catIng.group?.trimmingCharacters(in: .whitespacesAndNewlines)
                if ingGroup != targetGroup {
                    continue
                }
            }

            // Marcas activas del ingrediente en el orden de presentations(forIngredient:now:)
            let allPres = catalogPresentations(of: catIng.ingredient,
                                               among: presentationsByIngredient[catIng.id] ?? [],
                                               index: index, now: now)

            // 2. Marcas candidatas según tienda
            var candidates: [CatalogPresentation]
            switch filter.store {
            case .all:
                candidates = allPres
            case .store(let storeId):
                candidates = allPres.filter { $0.supplierId == storeId }
            case .noStore:
                candidates = allPres.filter { $0.supplierId == nil }
            }

            // Si el filtro es de tienda y no hay candidatas, el ingrediente no sale
            if filter.store != .all && candidates.isEmpty {
                continue
            }

            // 3. Búsqueda
            var matchedOnlyByBrandOrStore = false
            if !trimmedQuery.isEmpty {
                let matchesName = catIng.name.localizedStandardContains(trimmedQuery)
                let matchesGroup = catIng.group?.localizedStandardContains(trimmedQuery) == true

                let matchingCandidates = candidates.filter { candidate in
                    candidate.brand.localizedStandardContains(trimmedQuery) ||
                    (candidate.supplierName?.localizedStandardContains(trimmedQuery) == true)
                }
                let matchesBrandOrStore = !matchingCandidates.isEmpty

                if !matchesName && !matchesGroup && !matchesBrandOrStore {
                    continue
                }

                if matchesName || matchesGroup {
                    matchedOnlyByBrandOrStore = false
                } else {
                    matchedOnlyByBrandOrStore = true
                    candidates = matchingCandidates
                }
            }

            // 4. Marca mostrada (shownBrand)
            let shownBrand: CatalogPresentation?
            if candidates.isEmpty {
                shownBrand = nil
            } else if let current = candidates.first(where: { $0.isCurrent }) {
                shownBrand = current
            } else if let withPrice = candidates.first(where: { $0.latestPriceCents != nil }) {
                shownBrand = withPrice
            } else {
                shownBrand = candidates.first
            }

            // 6. Filtro por precio (sobre la marca mostrada)
            switch filter.price {
            case .all:
                break

            case .withoutPrice:
                if let shown = shownBrand, shown.latestPriceCents != nil {
                    continue
                }

            case .stale:
                guard let shown = shownBrand, shown.latestPriceCents != nil, shown.priceIsStale else {
                    continue
                }

            case .range(let minCents, let maxCents):
                guard let shown = shownBrand, let priceCents = shown.latestPriceCents else {
                    continue
                }
                var lower = minCents
                var upper = maxCents
                if let min = lower, let max = upper, min > max {
                    lower = max
                    upper = min
                }
                if let lower = lower, priceCents < lower {
                    continue
                }
                if let upper = upper, priceCents > upper {
                    continue
                }
            }

            // 7. highlightsBrand
            let isPriceSort: Bool = {
                switch filter.sort {
                case .priceLowToHigh, .priceHighToLow, .oldestPrice:
                    return true
                case .group, .name:
                    return false
                }
            }()

            let highlightsBrand = (shownBrand != nil) && (
                filter.store != .all ||
                filter.price != .all ||
                isPriceSort ||
                matchedOnlyByBrandOrStore
            )

            result.append(
                CatalogListItem(
                    ingredient: catIng,
                    shownBrand: shownBrand,
                    highlightsBrand: highlightsBrand
                )
            )
        }

        // 8. Orden
        sortCatalogListItems(&result, by: filter.sort)

        return result
    }

    /// Grupos de los ingredientes activos, sin repetir, ordenados por nombre. Vacíos no cuentan.
    public func catalogGroups() -> [String] {
        var seen = Set<String>()
        for ing in ingredients where ing.isActive {
            guard let group = ing.group else { continue }
            let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                seen.insert(trimmed)
            }
        }
        return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

// MARK: - Helpers privados de orden

private func sortCatalogListItems(
    _ items: inout [CatalogListItem],
    by sort: CatalogSort
) {
    items.sort { a, b in
        switch sort {
        case .group, .name:
            return a.ingredient.name.localizedStandardCompare(b.ingredient.name) == .orderedAscending

        case .priceLowToHigh:
            let priceA = a.shownBrand?.latestPriceCents
            let priceB = b.shownBrand?.latestPriceCents
            switch (priceA, priceB) {
            case let (.some(pA), .some(pB)):
                if pA != pB {
                    return pA < pB
                }
                return a.ingredient.name.localizedStandardCompare(b.ingredient.name) == .orderedAscending
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.ingredient.name.localizedStandardCompare(b.ingredient.name) == .orderedAscending
            }

        case .priceHighToLow:
            let priceA = a.shownBrand?.latestPriceCents
            let priceB = b.shownBrand?.latestPriceCents
            switch (priceA, priceB) {
            case let (.some(pA), .some(pB)):
                if pA != pB {
                    return pA > pB
                }
                return a.ingredient.name.localizedStandardCompare(b.ingredient.name) == .orderedAscending
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.ingredient.name.localizedStandardCompare(b.ingredient.name) == .orderedAscending
            }

        case .oldestPrice:
            let priceA = a.shownBrand?.latestPriceCents
            let priceB = b.shownBrand?.latestPriceCents
            switch (priceA, priceB) {
            case (.some, .some):
                let dateA = a.shownBrand?.latestPriceAt ?? .distantPast
                let dateB = b.shownBrand?.latestPriceAt ?? .distantPast
                if dateA != dateB {
                    return dateA < dateB
                }
                return a.ingredient.name.localizedStandardCompare(b.ingredient.name) == .orderedAscending
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.ingredient.name.localizedStandardCompare(b.ingredient.name) == .orderedAscending
            }
        }
    }
}
