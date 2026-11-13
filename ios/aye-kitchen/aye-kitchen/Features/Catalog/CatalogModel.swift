import Foundation
import KitchenDomain
import Observation

/// Descripción de cómo se mide según la unidad base del contrato.
extension BaseUnit {
    var buyingUnitDescription: String {
        switch self {
        case .g:
            "Se pesa (g)"
        case .ml:
            "Es líquido (ml)"
        case .pz:
            "Se cuenta (piezas)"
        }
    }
}

extension CatalogIngredient {
    var buyingUnitDescription: String {
        baseUnit.buyingUnitDescription
    }
}

extension Ingredient {
    var buyingUnitDescription: String {
        baseUnit.buyingUnitDescription
    }
}

/// Sección agrupada para la lista de catálogo.
struct CatalogSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [CatalogListItem]
}

/// ViewModel para la lista de ingredientes (`CatalogView`, MVVM, Regla 5 / Bloque I16 / Bloque I33).
@Observable final class CatalogModel {
    let store: LocalStore
    var filter: CatalogFilter = CatalogFilter()

    init(store: LocalStore = .shared) {
        self.store = store
    }

    /// Se recalcula solo cuando cambian el filtro o los datos (`store.revision`): la vista lo lee varias veces
    /// por dibujo y `catalogList` recorre todas las marcas.
    var items: [CatalogListItem] {
        let key = ItemsCacheKey(filter: filter, revision: store.revision)
        if key != cachedKey {
            cachedItems = store.data.catalogList(filter)
            cachedKey = key
        }
        return cachedItems
    }

    private struct ItemsCacheKey: Equatable {
        let filter: CatalogFilter
        let revision: Int
    }

    @ObservationIgnored private var cachedKey: ItemsCacheKey?
    @ObservationIgnored private var cachedItems: [CatalogListItem] = []

    var groups: [String] {
        store.data.catalogGroups()
    }

    var suppliers: [Supplier] {
        store.data.activeSuppliers()
    }

    var hasAnyIngredient: Bool {
        store.data.ingredients.contains(where: { $0.isActive })
    }

    func clearFilters() {
        filter.store = .all
        filter.group = nil
        filter.price = .all
    }

    /// Agrupa por `group` en secciones ordenadas por nombre si `sort == .group`; con cualquier otro orden,
    /// una sola sección sin título con todos los `items` en el orden que vienen.
    var sections: [CatalogSection] {
        let currentItems = items
        guard !currentItems.isEmpty else { return [] }

        if filter.sort == .group {
            var groupsMap: [String: [CatalogListItem]] = [:]
            var others: [CatalogListItem] = []

            for item in currentItems {
                if let groupName = item.ingredient.group?.trimmingCharacters(in: .whitespacesAndNewlines), !groupName.isEmpty {
                    groupsMap[groupName, default: []].append(item)
                } else {
                    others.append(item)
                }
            }

            var result: [CatalogSection] = []
            let sortedGroupNames = groupsMap.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            for groupName in sortedGroupNames {
                if let groupItems = groupsMap[groupName] {
                    result.append(CatalogSection(id: groupName, title: groupName, items: groupItems))
                }
            }

            if !others.isEmpty {
                result.append(CatalogSection(id: "__otros__", title: "Otros", items: others))
            }

            return result
        } else {
            return [CatalogSection(id: "__all__", title: "", items: currentItems)]
        }
    }

    /// Borrado del ingrediente. Lanza error para que la vista decida cómo mostrarlo (p. ej. IN_USE).
    func deleteIngredient(id: String) throws {
        try store.mutate { data, ctx in
            try data.deleteIngredient(id: id, ctx: ctx)
        }
    }
}
