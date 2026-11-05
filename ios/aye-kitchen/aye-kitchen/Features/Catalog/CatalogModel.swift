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
    let items: [CatalogIngredient]
}

/// ViewModel para la lista de ingredientes (`CatalogView`, MVVM, Regla 5 / Bloque I16).
@Observable final class CatalogModel {
    private let store: LocalStore
    var searchText: String = ""

    init(store: LocalStore = .shared) {
        self.store = store
    }

    var ingredients: [CatalogIngredient] {
        store.data.activeIngredients(q: searchText)
    }

    /// Agrupa por `group` en secciones ordenadas por nombre; los que no tienen grupo van al final en "Otros".
    var sections: [CatalogSection] {
        var groups: [String: [CatalogIngredient]] = [:]
        var others: [CatalogIngredient] = []

        for item in ingredients {
            if let groupName = item.group?.trimmingCharacters(in: .whitespacesAndNewlines), !groupName.isEmpty {
                groups[groupName, default: []].append(item)
            } else {
                others.append(item)
            }
        }

        var result: [CatalogSection] = []
        let sortedGroupNames = groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for groupName in sortedGroupNames {
            let sortedItems = (groups[groupName] ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            result.append(CatalogSection(id: groupName, title: groupName, items: sortedItems))
        }

        if !others.isEmpty {
            let sortedOthers = others.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            result.append(CatalogSection(id: "__otros__", title: "Otros", items: sortedOthers))
        }

        return result
    }

    /// Borrado del ingrediente. Lanza error para que la vista decida cómo mostrarlo (p. ej. IN_USE).
    func deleteIngredient(id: String) throws {
        try store.mutate { data, ctx in
            try data.deleteIngredient(id: id, ctx: ctx)
        }
    }
}
