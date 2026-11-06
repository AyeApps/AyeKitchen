import Foundation

// Entidades de AyeKitchen tal como viven en el teléfono y en el respaldo (docs/backup-format.md).
// Mismos campos que los modelos del backend (backend/app/models), en camelCase; el JSON va en
// snake_case (KitchenCoding). Cantidades como texto decimal ("1000", "0.5") igual que la API;
// usa `Qty.decimal(_:)` para calcular. Dinero en centavos enteros. Fechas en UTC.
// Nada se borra de verdad: `deletedAt` marca el borrado y se conserva para el historial.

public enum BaseUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case g, ml, pz
}

/// Unidad propia del negocio. Las del sistema no se guardan: viven en `SystemUnits`.
public struct KitchenUnit: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var abbreviation: String
    public var baseUnit: BaseUnit
    /// 1 <unidad> = factorToBase <baseUnit>.
    public var factorToBase: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, name: String, abbreviation: String, baseUnit: BaseUnit, factorToBase: String,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.baseUnit = baseUnit
        self.factorToBase = factorToBase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// "1 taza de harina = 125 g". Gana sobre la tabla general.
public struct IngredientConversion: Codable, Sendable, Hashable {
    public var unitId: String
    public var quantityInBase: String

    public init(unitId: String, quantityInBase: String) {
        self.unitId = unitId
        self.quantityInBase = quantityInBase
    }
}

/// El ingrediente general: "Harina de trigo". Sus marcas son `Presentation`.
public struct Ingredient: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var baseUnit: BaseUnit
    public var group: String?
    public var notes: String?
    public var conversions: [IngredientConversion]
    /// Imágenes de referencia opcionales (ids de `KitchenData.references`), hasta 5. Nulo = ninguna.
    public var referenceIds: [String]?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, name: String, baseUnit: BaseUnit, group: String? = nil, notes: String? = nil,
                conversions: [IngredientConversion] = [], referenceIds: [String]? = nil,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.baseUnit = baseUnit
        self.group = group
        self.notes = notes
        self.conversions = conversions
        self.referenceIds = referenceIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Supplier: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, name: String, notes: String? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Una marca de un ingrediente: "Selecta, Walmart, bolsa de 1000 g". El precio vive en `PriceRecord`.
public struct Presentation: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var ingredientId: String
    public var brand: String
    public var supplierId: String?
    /// En la base_unit del ingrediente.
    public var packageQuantity: String
    public var barcode: String?
    /// Imágenes de referencia opcionales (ids de `KitchenData.references`), hasta 5. Nulo = ninguna.
    public var referenceIds: [String]?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, ingredientId: String, brand: String, supplierId: String? = nil, packageQuantity: String,
                barcode: String? = nil, referenceIds: [String]? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.ingredientId = ingredientId
        self.brand = brand
        self.supplierId = supplierId
        self.packageQuantity = packageQuantity
        self.barcode = barcode
        self.referenceIds = referenceIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Historial de precios. El precio de una marca es su registro más reciente (`recordedAt`, luego `createdAt`).
public struct PriceRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var presentationId: String
    public var priceCents: Int
    public var recordedAt: Date
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, presentationId: String, priceCents: Int, recordedAt: Date, note: String? = nil,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.presentationId = presentationId
        self.priceCents = priceCents
        self.recordedAt = recordedAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public enum RecipeItemKind: String, Codable, Sendable, Hashable {
    case ingredient
    case recipe
}

public struct RecipeItem: Codable, Sendable, Hashable {
    public var kind: RecipeItemKind
    /// Ingredient.id o Recipe.id según `kind`.
    public var refId: String
    /// Tal como la escribió la usuaria.
    public var quantity: String
    /// Nulo = la base_unit del ingrediente o la yield_unit de la subreceta.
    public var unitId: String?
    /// Solo en ingredientes. Nulo = la marca vigente.
    public var pinnedPresentationId: String?

    public init(kind: RecipeItemKind, refId: String, quantity: String, unitId: String? = nil, pinnedPresentationId: String? = nil) {
        self.kind = kind
        self.refId = refId
        self.quantity = quantity
        self.unitId = unitId
        self.pinnedPresentationId = pinnedPresentationId
    }
}

/// Costos fijos por tanda: caja, gas, mano de obra.
public struct ExtraCost: Codable, Sendable, Hashable {
    public var name: String
    public var costCents: Int

    public init(name: String, costCents: Int) {
        self.name = name
        self.costCents = costCents
    }
}

public struct Recipe: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    public var items: [RecipeItem]
    public var extraCosts: [ExtraCost]
    public var yieldQuantity: String
    public var yieldUnit: BaseUnit
    public var servings: Int?
    /// Nulo = el margen del negocio (`KitchenSettings.defaultMarginPercent`).
    public var marginPercent: Int?
    /// Imágenes de referencia opcionales (ids de `KitchenData.references`), hasta 5. Nulo = ninguna.
    public var referenceIds: [String]?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, name: String, description: String? = nil, items: [RecipeItem] = [], extraCosts: [ExtraCost] = [],
                yieldQuantity: String, yieldUnit: BaseUnit, servings: Int? = nil, marginPercent: Int? = nil,
                referenceIds: [String]? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.items = items
        self.extraCosts = extraCosts
        self.yieldQuantity = yieldQuantity
        self.yieldUnit = yieldUnit
        self.servings = servings
        self.marginPercent = marginPercent
        self.referenceIds = referenceIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct CostVersionChoice: Codable, Sendable, Hashable {
    public var ingredientId: String
    public var presentationId: String

    public init(ingredientId: String, presentationId: String) {
        self.ingredientId = ingredientId
        self.presentationId = presentationId
    }
}

/// "Con Selecta": qué marca usar por ingrediente. Todo lo demás sale de la receta.
public struct CostVersion: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var recipeId: String
    public var name: String
    public var choices: [CostVersionChoice]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, recipeId: String, name: String, choices: [CostVersionChoice] = [],
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.recipeId = recipeId
        self.name = name
        self.choices = choices
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Customer: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var phone: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, name: String, phone: String? = nil, notes: String? = nil,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public enum OrderStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case pendiente
    case enProceso = "en_proceso"
    case entregado
    case cancelado
}

public enum OrderSoldBy: String, Codable, Sendable, Hashable {
    /// Tandas completas de la receta.
    case batch
    /// La unidad que rinde la receta (pz, g, ml).
    case unit
}

public struct OrderItem: Codable, Sendable, Hashable {
    public var recipeId: String
    /// Copia del nombre al crear la línea: el pedido se sigue leyendo aunque la receta cambie o se borre.
    public var recipeName: String
    public var soldBy: OrderSoldBy
    /// Copia de la yield_unit cuando `soldBy == .unit`; nulo en tandas.
    public var unitLabel: BaseUnit?
    public var quantity: String
    public var unitPriceCents: Int
    /// Costo por tanda o por unidad al crear la línea; no cambia con los precios.
    public var unitCostCentsSnapshot: Int

    public init(recipeId: String, recipeName: String, soldBy: OrderSoldBy = .batch, unitLabel: BaseUnit? = nil,
                quantity: String, unitPriceCents: Int, unitCostCentsSnapshot: Int) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.soldBy = soldBy
        self.unitLabel = unitLabel
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.unitCostCentsSnapshot = unitCostCentsSnapshot
    }
}

public struct Payment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var amountCents: Int
    public var paidAt: Date
    public var method: String?

    public init(id: String, amountCents: Int, paidAt: Date, method: String? = nil) {
        self.id = id
        self.amountCents = amountCents
        self.paidAt = paidAt
        self.method = method
    }
}

public struct Order: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var customerId: String?
    /// Copia que se muestra; si hay `customerId`, se actualiza al renombrar al cliente.
    public var customerName: String
    public var customerPhone: String?
    public var deliveryAt: Date
    public var items: [OrderItem]
    public var payments: [Payment]
    public var status: OrderStatus
    public var notes: String?
    /// Imágenes de referencia opcionales (lo que pidió el cliente), hasta 5.
    public var referenceIds: [String]?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, customerId: String? = nil, customerName: String, customerPhone: String? = nil,
                deliveryAt: Date, items: [OrderItem] = [], payments: [Payment] = [], status: OrderStatus = .pendiente,
                notes: String? = nil, referenceIds: [String]? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.customerId = customerId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.deliveryAt = deliveryAt
        self.items = items
        self.payments = payments
        self.status = status
        self.notes = notes
        self.referenceIds = referenceIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Expense: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var description: String
    public var amountCents: Int
    public var spentAt: Date
    public var category: String?
    public var supplierId: String?
    /// Imágenes de referencia opcionales (el ticket), hasta 5.
    public var referenceIds: [String]?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, description: String, amountCents: Int, spentAt: Date, category: String? = nil,
                supplierId: String? = nil, referenceIds: [String]? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.description = description
        self.amountCents = amountCents
        self.spentAt = spentAt
        self.category = category
        self.supplierId = supplierId
        self.referenceIds = referenceIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Imagen de referencia (foto del empaque, del pastel terminado, de la receta escrita, del ticket).
/// Los bytes viven aparte (en el teléfono y en `/backup/references`); aquí solo sus datos.
public struct ReferenceImage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// "image/jpeg" o "image/heic".
    public var contentType: String
    public var sizeBytes: Int
    public var width: Int
    public var height: Int
    /// Huella SHA-256 en hex de los bytes, para saber si ya está respaldada.
    public var sha256: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: String, contentType: String, sizeBytes: Int, width: Int, height: Int, sha256: String,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.width = width
        self.height = height
        self.sha256 = sha256
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Ajustes del negocio (el "workspace" del backend).
public struct KitchenSettings: Codable, Sendable, Hashable {
    public var name: String
    public var currency: String
    /// Zona para los límites de día y mes ("America/Mexico_City").
    public var timezone: String
    public var defaultMarginPercent: Int
    /// Un precio con más días que esto es "precio viejo".
    public var priceStaleDays: Int

    public init(name: String = "Mi cocina", currency: String = "MXN", timezone: String = "America/Mexico_City",
                defaultMarginPercent: Int = 40, priceStaleDays: Int = 90) {
        self.name = name
        self.currency = currency
        self.timezone = timezone
        self.defaultMarginPercent = defaultMarginPercent
        self.priceStaleDays = priceStaleDays
    }
}
