import Foundation

// MARK: - Modelos de consulta del catálogo (K2a)

public struct CatalogUnit: Sendable, Hashable, Identifiable {
    public var id: String { unit.id }
    public var unit: KitchenUnit
    public var isSystem: Bool

    public var name: String { unit.name }
    public var abbreviation: String { unit.abbreviation }
    public var baseUnit: BaseUnit { unit.baseUnit }
    public var factorToBase: String { unit.factorToBase }

    public init(unit: KitchenUnit, isSystem: Bool) {
        self.unit = unit
        self.isSystem = isSystem
    }
}

public struct CatalogIngredientConversion: Sendable, Hashable {
    public var unitId: String
    public var unitName: String
    public var quantityInBase: String

    public init(unitId: String, unitName: String, quantityInBase: String) {
        self.unitId = unitId
        self.unitName = unitName
        self.quantityInBase = quantityInBase
    }
}

public struct CatalogIngredientCurrentBrand: Sendable, Hashable {
    public var presentationId: String
    public var brand: String
    public var supplierName: String?
    public var costPerBaseUnit: String?

    public init(
        presentationId: String,
        brand: String,
        supplierName: String? = nil,
        costPerBaseUnit: String? = nil
    ) {
        self.presentationId = presentationId
        self.brand = brand
        self.supplierName = supplierName
        self.costPerBaseUnit = costPerBaseUnit
    }
}

public struct CatalogIngredient: Sendable, Hashable, Identifiable {
    public var id: String { ingredient.id }
    public var ingredient: Ingredient
    public var conversions: [CatalogIngredientConversion]
    public var brandsCount: Int
    public var currentBrand: CatalogIngredientCurrentBrand?

    public var name: String { ingredient.name }
    public var baseUnit: BaseUnit { ingredient.baseUnit }
    public var group: String? { ingredient.group }
    public var notes: String? { ingredient.notes }
    public var referenceIds: [String] { ingredient.referenceIds ?? [] }
    public var createdAt: Date { ingredient.createdAt }
    public var updatedAt: Date { ingredient.updatedAt }

    public init(
        ingredient: Ingredient,
        conversions: [CatalogIngredientConversion],
        brandsCount: Int,
        currentBrand: CatalogIngredientCurrentBrand? = nil
    ) {
        self.ingredient = ingredient
        self.conversions = conversions
        self.brandsCount = brandsCount
        self.currentBrand = currentBrand
    }
}

public struct CatalogPresentation: Sendable, Hashable, Identifiable {
    public var id: String { presentation.id }
    public var presentation: Presentation
    public var ingredientId: String { presentation.ingredientId }
    public var ingredientName: String
    public var brand: String { presentation.brand }
    public var supplierId: String? { presentation.supplierId }
    public var supplierName: String?
    public var packageQuantity: String { presentation.packageQuantity }
    public var baseUnit: BaseUnit
    public var barcode: String? { presentation.barcode }
    public var latestPriceCents: Int?
    public var latestPriceAt: Date?
    public var costPerBaseUnit: String?
    public var isCurrent: Bool
    public var priceAgeDays: Int?
    public var priceIsStale: Bool
    public var createdAt: Date { presentation.createdAt }
    public var updatedAt: Date { presentation.updatedAt }

    public init(
        presentation: Presentation,
        ingredientName: String,
        supplierName: String? = nil,
        baseUnit: BaseUnit,
        latestPriceCents: Int? = nil,
        latestPriceAt: Date? = nil,
        costPerBaseUnit: String? = nil,
        isCurrent: Bool = false,
        priceAgeDays: Int? = nil,
        priceIsStale: Bool = false
    ) {
        self.presentation = presentation
        self.ingredientName = ingredientName
        self.supplierName = supplierName
        self.baseUnit = baseUnit
        self.latestPriceCents = latestPriceCents
        self.latestPriceAt = latestPriceAt
        self.costPerBaseUnit = costPerBaseUnit
        self.isCurrent = isCurrent
        self.priceAgeDays = priceAgeDays
        self.priceIsStale = priceIsStale
    }
}

public struct CatalogStalePresentation: Sendable, Hashable, Identifiable {
    public var id: String { presentation.id }
    public var presentation: CatalogPresentation
    public var usedInRecipes: Int

    public var ingredientId: String { presentation.ingredientId }
    public var ingredientName: String { presentation.ingredientName }
    public var brand: String { presentation.brand }
    public var supplierId: String? { presentation.supplierId }
    public var supplierName: String? { presentation.supplierName }
    public var packageQuantity: String { presentation.packageQuantity }
    public var baseUnit: BaseUnit { presentation.baseUnit }
    public var barcode: String? { presentation.barcode }
    public var latestPriceCents: Int? { presentation.latestPriceCents }
    public var latestPriceAt: Date? { presentation.latestPriceAt }
    public var costPerBaseUnit: String? { presentation.costPerBaseUnit }
    public var isCurrent: Bool { presentation.isCurrent }
    public var priceAgeDays: Int? { presentation.priceAgeDays }
    public var priceIsStale: Bool { presentation.priceIsStale }

    public init(presentation: CatalogPresentation, usedInRecipes: Int) {
        self.presentation = presentation
        self.usedInRecipes = usedInRecipes
    }
}

public struct CatalogSupplier: Sendable, Hashable, Identifiable {
    public var id: String { supplier.id }
    public var supplier: Supplier
    public var name: String { supplier.name }
    public var notes: String? { supplier.notes }
    public var createdAt: Date { supplier.createdAt }
    public var updatedAt: Date { supplier.updatedAt }

    public init(supplier: Supplier) {
        self.supplier = supplier
    }
}

// MARK: - Consultas del catálogo sobre KitchenData

extension KitchenData {

    // MARK: - 1. Unidades disponibles

    /// Lista de unidades disponibles (sistema + negocio activas), ordenadas por `base_unit` y luego factor.
    public func availableUnits(now: Date = Date()) -> [CatalogUnit] {
        var allUnits = SystemUnits.all.map { CatalogUnit(unit: $0, isSystem: true) }
        for u in units where u.isActive {
            allUnits.append(CatalogUnit(unit: u, isSystem: false))
        }

        allUnits.sort { a, b in
            let baseA = a.baseUnit.rawValue
            let baseB = b.baseUnit.rawValue
            if baseA != baseB {
                return baseA < baseB
            }
            let factorA = Qty.decimal(a.factorToBase) ?? 0
            let factorB = Qty.decimal(b.factorToBase) ?? 0
            if factorA != factorB {
                return factorA < factorB
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        return allUnits
    }

    /// Conveniencia para obtener directamente las `KitchenUnit` activas y del sistema.
    public func availableKitchenUnits(now: Date = Date()) -> [KitchenUnit] {
        availableUnits(now: now).map(\.unit)
    }

    // MARK: - 2. Ingredientes activos

    /// Ingredientes activos con búsqueda opcional por nombre y filtro por grupo, ordenados por nombre,
    /// cada uno con su resumen de marcas (`brands_count` y marca vigente con `cost_per_base_unit`).
    public func activeIngredients(
        q: String? = nil,
        group: String? = nil,
        now: Date = Date()
    ) -> [CatalogIngredient] {
        let index = costingIndex()
        var filtered = ingredients.filter { $0.isActive }

        if let g = group, !g.isEmpty {
            filtered = filtered.filter { $0.group == g }
        }

        if let query = q?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        filtered.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return filtered.map { ing in
            let conversions = ing.conversions.map { c in
                let uName = index.unitsById[c.unitId]?.name ?? ""
                return CatalogIngredientConversion(unitId: c.unitId, unitName: uName, quantityInBase: c.quantityInBase)
            }

            let brandsCount = presentations.filter { $0.isActive && $0.ingredientId == ing.id }.count

            var currentBrand: CatalogIngredientCurrentBrand? = nil
            if let curr = index.currentPresentation(for: ing.id) {
                let suppName = curr.presentation.supplierId.flatMap { index.suppliersById[$0]?.name }
                let pkgQty = Qty.decimal(curr.presentation.packageQuantity) ?? 0
                let costPerBase: String? = pkgQty > 0
                    ? CostingMath.formatSixDecimals(Decimal(curr.priceRecord.priceCents) / pkgQty)
                    : nil
                currentBrand = CatalogIngredientCurrentBrand(
                    presentationId: curr.presentation.id,
                    brand: curr.presentation.brand,
                    supplierName: suppName,
                    costPerBaseUnit: costPerBase
                )
            }

            return CatalogIngredient(
                ingredient: ing,
                conversions: conversions,
                brandsCount: brandsCount,
                currentBrand: currentBrand
            )
        }
    }

    // MARK: - 3. Marcas de un ingrediente

    /// Marcas de un ingrediente en el orden del contrato: las que tienen precio primero (más recientes por
    /// `latest_price_at` y luego `created_at`), seguidas de las que no tienen precio (por `created_at` desc).
    public func presentations(
        forIngredient ingredientId: String,
        now: Date = Date()
    ) throws -> [CatalogPresentation] {
        guard let ingredient = ingredients.first(where: { $0.id == ingredientId && $0.isActive }) else {
            throw DomainError.notFound(detail: "Ingrediente no encontrado")
        }

        let index = costingIndex()
        var presList = presentations.filter { $0.isActive && $0.ingredientId == ingredientId }

        presList.sort { a, b in
            let priceA = index.latestPrice(for: a.id)
            let priceB = index.latestPrice(for: b.id)
            switch (priceA, priceB) {
            case let (.some(prA), .some(prB)):
                if prA.recordedAt != prB.recordedAt {
                    return prA.recordedAt > prB.recordedAt
                }
                return a.createdAt > b.createdAt
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.createdAt > b.createdAt
            }
        }

        let currPresentationId = index.currentPresentation(for: ingredientId)?.presentation.id

        return presList.map { p in
            let lp = index.latestPrice(for: p.id)
            let supplierName = p.supplierId.flatMap { index.suppliersById[$0]?.name }
            let pkgQty = Qty.decimal(p.packageQuantity) ?? 0
            let costPerBase: String?
            if let lp = lp, pkgQty > 0 {
                costPerBase = CostingMath.formatSixDecimals(Decimal(lp.priceCents) / pkgQty)
            } else {
                costPerBase = nil
            }

            let isCurrent = (p.id == currPresentationId)
            let staleness = index.computePriceStaleness(priceAt: lp?.recordedAt, now: now)

            return CatalogPresentation(
                presentation: p,
                ingredientName: ingredient.name,
                supplierName: supplierName,
                baseUnit: ingredient.baseUnit,
                latestPriceCents: lp?.priceCents,
                latestPriceAt: lp?.recordedAt,
                costPerBaseUnit: costPerBase,
                isCurrent: isCurrent,
                priceAgeDays: staleness.ageDays,
                priceIsStale: staleness.isStale
            )
        }
    }

    /// Sobrecarga con etiqueta `ingredientId:`.
    public func presentations(
        ingredientId: String,
        now: Date = Date()
    ) throws -> [CatalogPresentation] {
        try presentations(forIngredient: ingredientId, now: now)
    }

    // MARK: - 4. Historial de precios de una marca

    /// Historial de precios de una marca ordenado por `recorded_at` desc y luego `created_at` desc.
    public func priceHistory(
        presentationId: String,
        now: Date = Date()
    ) throws -> [PriceRecord] {
        guard presentations.contains(where: { $0.id == presentationId && $0.isActive }) else {
            throw DomainError.notFound(detail: "Presentación no encontrada")
        }

        var records = priceRecords.filter { $0.isActive && $0.presentationId == presentationId }
        records.sort { a, b in
            if a.recordedAt != b.recordedAt {
                return a.recordedAt > b.recordedAt
            }
            return a.createdAt > b.createdAt
        }
        return records
    }

    // MARK: - 5. Precios por actualizar (/presentations/stale)

    /// Precios por actualizar: presentaciones activas con precio viejo (`price_is_stale`) que el costeo
    /// de verdad usa (son la vigente de su ingrediente y el ingrediente aparece en una receta activa,
    /// o están fijadas en una receta activa). Orden: `latest_price_at` asc (la más vieja primero).
    public func stalePresentations(now: Date = Date()) -> [CatalogStalePresentation] {
        let index = costingIndex()
        let activePresentations = presentations.filter { $0.isActive }
        if activePresentations.isEmpty {
            return []
        }

        let presMap = Dictionary(uniqueKeysWithValues: activePresentations.map { ($0.id, $0) })

        var currentPresIdByIng: [String: String] = [:]
        for (ingId, curr) in index.currentPresentationByIngredient {
            currentPresIdByIng[ingId] = curr.presentation.id
        }

        let activeRecipes = recipes.filter { $0.isActive }
        var usedRecipes: [String: Set<String>] = Dictionary(uniqueKeysWithValues: activePresentations.map { ($0.id, Set<String>()) })

        for r in activeRecipes {
            for item in r.items where item.kind == .ingredient {
                if let pinnedId = item.pinnedPresentationId, presMap[pinnedId] != nil {
                    usedRecipes[pinnedId, default: []].insert(r.id)
                } else if let currId = currentPresIdByIng[item.refId], usedRecipes[currId] != nil {
                    usedRecipes[currId, default: []].insert(r.id)
                }
            }
        }

        var staleList: [(presentation: Presentation, priceRecord: PriceRecord, usedCount: Int)] = []
        for p in activePresentations {
            guard let pr = index.latestPrice(for: p.id) else { continue }
            let (_, isStale) = index.computePriceStaleness(priceAt: pr.recordedAt, now: now)
            guard isStale else { continue }
            let count = usedRecipes[p.id]?.count ?? 0
            if count > 0 {
                staleList.append((presentation: p, priceRecord: pr, usedCount: count))
            }
        }

        // Orden: latest_price_at asc (la más vieja primero), desempate created_at asc
        staleList.sort { a, b in
            if a.priceRecord.recordedAt != b.priceRecord.recordedAt {
                return a.priceRecord.recordedAt < b.priceRecord.recordedAt
            }
            return a.presentation.createdAt < b.presentation.createdAt
        }

        return staleList.map { item in
            let p = item.presentation
            let pr = item.priceRecord
            let ing = index.ingredientsById[p.ingredientId]
            let suppName = p.supplierId.flatMap { index.suppliersById[$0]?.name }
            let pkgQty = Qty.decimal(p.packageQuantity) ?? 0
            let costPerBase: String? = pkgQty > 0
                ? CostingMath.formatSixDecimals(Decimal(pr.priceCents) / pkgQty)
                : nil
            let isCurrent = (currentPresIdByIng[p.ingredientId] == p.id)
            let staleness = index.computePriceStaleness(priceAt: pr.recordedAt, now: now)

            let catPres = CatalogPresentation(
                presentation: p,
                ingredientName: ing?.name ?? "",
                supplierName: suppName,
                baseUnit: ing?.baseUnit ?? .g,
                latestPriceCents: pr.priceCents,
                latestPriceAt: pr.recordedAt,
                costPerBaseUnit: costPerBase,
                isCurrent: isCurrent,
                priceAgeDays: staleness.ageDays,
                priceIsStale: true
            )
            return CatalogStalePresentation(presentation: catPres, usedInRecipes: item.usedCount)
        }
    }

    // MARK: - 6. Proveedores activos por nombre

    /// Proveedores activos ordenados por nombre.
    public func activeSuppliers(now: Date = Date()) -> [Supplier] {
        suppliers
            .filter { $0.isActive }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Proveedores activos como `CatalogSupplier` ordenados por nombre.
    public func catalogSuppliers(now: Date = Date()) -> [CatalogSupplier] {
        activeSuppliers(now: now).map(CatalogSupplier.init)
    }
}
