import Foundation

/// Todos los datos de un negocio. Es a la vez el archivo local de la app y el respaldo que se sube
/// al servidor (docs/backup-format.md). Las listas incluyen lo borrado (`deletedAt`).
public struct KitchenData: Codable, Sendable, Hashable {
    /// Versión del formato. Sube solo con cambios que una app vieja no sabría leer.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Cuándo se escribió este documento.
    public var exportedAt: Date
    /// El teléfono que lo escribió (`UIDevice.identifierForVendor` o un UUID guardado).
    public var deviceId: String
    public var settings: KitchenSettings
    /// Solo las unidades del negocio; las del sistema están en `SystemUnits`.
    public var units: [KitchenUnit]
    public var ingredients: [Ingredient]
    public var suppliers: [Supplier]
    public var presentations: [Presentation]
    public var priceRecords: [PriceRecord]
    public var recipes: [Recipe]
    public var costVersions: [CostVersion]
    public var customers: [Customer]
    public var orders: [Order]
    public var expenses: [Expense]
    /// Imágenes de referencia (sus datos; los bytes van aparte).
    public var references: [ReferenceImage]

    public init(schemaVersion: Int = KitchenData.currentSchemaVersion, exportedAt: Date = Date(), deviceId: String,
                settings: KitchenSettings = KitchenSettings(), units: [KitchenUnit] = [], ingredients: [Ingredient] = [],
                suppliers: [Supplier] = [], presentations: [Presentation] = [], priceRecords: [PriceRecord] = [],
                recipes: [Recipe] = [], costVersions: [CostVersion] = [], customers: [Customer] = [],
                orders: [Order] = [], expenses: [Expense] = [], references: [ReferenceImage] = []) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.deviceId = deviceId
        self.settings = settings
        self.units = units
        self.ingredients = ingredients
        self.suppliers = suppliers
        self.presentations = presentations
        self.priceRecords = priceRecords
        self.recipes = recipes
        self.costVersions = costVersions
        self.customers = customers
        self.orders = orders
        self.expenses = expenses
        self.references = references
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, deviceId, settings, units, ingredients, suppliers, presentations
        case priceRecords, recipes, costVersions, customers, orders, expenses, references
    }

    /// Tolerante: una lista que falta se lee vacía, para que archivos y respaldos escritos antes de
    /// que existiera un campo nuevo se sigan leyendo (cambios que solo agregan, sin subir la versión).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        settings = try c.decodeIfPresent(KitchenSettings.self, forKey: .settings) ?? KitchenSettings()
        units = try c.decodeIfPresent([KitchenUnit].self, forKey: .units) ?? []
        ingredients = try c.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        suppliers = try c.decodeIfPresent([Supplier].self, forKey: .suppliers) ?? []
        presentations = try c.decodeIfPresent([Presentation].self, forKey: .presentations) ?? []
        priceRecords = try c.decodeIfPresent([PriceRecord].self, forKey: .priceRecords) ?? []
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        costVersions = try c.decodeIfPresent([CostVersion].self, forKey: .costVersions) ?? []
        customers = try c.decodeIfPresent([Customer].self, forKey: .customers) ?? []
        orders = try c.decodeIfPresent([Order].self, forKey: .orders) ?? []
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        references = try c.decodeIfPresent([ReferenceImage].self, forKey: .references) ?? []
    }

    /// Un negocio vacío (primera vez, sin respaldo).
    public static func empty(deviceId: String) -> KitchenData {
        KitchenData(deviceId: deviceId)
    }
}

/// JSON del archivo y del respaldo: llaves en snake_case, fechas ISO 8601 en UTC con milisegundos.
public enum KitchenCoding {
    public static func encode(_ data: KitchenData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(fractional))
        }
        return try encoder.encode(data)
    }

    public static func decode(_ data: Data) throws -> KitchenData {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Fecha inválida: \(text)")
            }
            return date
        }
        let decoded = try decoder.decode(KitchenData.self, from: data)
        guard decoded.schemaVersion <= KitchenData.currentSchemaVersion else {
            throw KitchenCodingError.newerSchema(decoded.schemaVersion)
        }
        return decoded
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    /// Acepta con o sin milisegundos, con "Z" o sin zona (sin zona = UTC), y microsegundos (los corta).
    static func parseDate(_ text: String) -> Date? {
        var value = text
        let hasZone = value.hasSuffix("Z") || value.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil
        if !hasZone { value += "Z" }
        if let dot = value.firstIndex(of: ".") {
            var end = value.index(after: dot)
            while end < value.endIndex, value[end].isNumber { end = value.index(after: end) }
            if value.distance(from: dot, to: end) > 4 {
                value = String(value[..<value.index(dot, offsetBy: 4)]) + String(value[end...])
            }
        }
        return (try? fractional.parse(value)) ?? (try? plain.parse(value))
    }
}

public enum KitchenCodingError: Error, Equatable {
    /// El archivo lo escribió una versión más nueva de la app: hay que actualizar.
    case newerSchema(Int)
}

/// Cantidades: texto decimal ↔ `Decimal`, sin pasar por `Double`.
public enum Qty {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Nulo si no es un número.
    public static func decimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: posix)
    }

    public static func text(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: posix)
    }
}
