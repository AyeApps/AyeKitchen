import Foundation

/// Unidades del sistema: fijas, iguales para todos, no se guardan en el archivo ni en el respaldo.
/// Sus ids son estables (`sys.<abreviatura>`) y son los que usan recetas y equivalencias.
/// Al migrar desde el backend, cada unidad del sistema del servidor se traduce a su id `sys.*` por
/// su abreviatura (docs/backup-format.md, "Migración").
public enum SystemUnits {
    public static let all: [KitchenUnit] = [
        make("g", "gramo", .g, "1"),
        make("kg", "kilogramo", .g, "1000"),
        make("lb", "libra", .g, "453.592"),
        make("oz", "onza", .g, "28.3495"),
        make("ml", "mililitro", .ml, "1"),
        make("l", "litro", .ml, "1000"),
        make("tz", "taza", .ml, "240"),
        make("cda", "cucharada", .ml, "15"),
        make("cdta", "cucharadita", .ml, "5"),
        make("fl oz", "onza líquida", .ml, "29.5735"),
        make("pz", "pieza", .pz, "1"),
        make("doc", "docena", .pz, "12"),
    ]

    public static let byId: [String: KitchenUnit] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// `sys.kg`, `sys.fl_oz`…
    public static func id(forAbbreviation abbreviation: String) -> String {
        "sys." + abbreviation.replacingOccurrences(of: " ", with: "_")
    }

    public static func isSystem(_ unitId: String) -> Bool {
        unitId.hasPrefix("sys.")
    }

    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func make(_ abbreviation: String, _ name: String, _ base: BaseUnit, _ factor: String) -> KitchenUnit {
        KitchenUnit(
            id: id(forAbbreviation: abbreviation), name: name, abbreviation: abbreviation,
            baseUnit: base, factorToBase: factor, createdAt: epoch, updatedAt: epoch
        )
    }
}
