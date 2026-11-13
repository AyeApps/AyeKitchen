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
    /// ESQUELETO K7: hoy solo busca por nombre (como `activeIngredients(q:)`); K7 implementa el resto.
    public func catalogList(_ filter: CatalogFilter, now: Date = Date()) -> [CatalogListItem] {
        activeIngredients(q: filter.query, now: now).map { CatalogListItem(ingredient: $0) }
    }

    /// Grupos de los ingredientes activos, sin repetir, ordenados por nombre. Vacíos no cuentan.
    /// ESQUELETO K7: hoy devuelve vacío; K7 lo implementa.
    public func catalogGroups() -> [String] {
        []
    }
}
