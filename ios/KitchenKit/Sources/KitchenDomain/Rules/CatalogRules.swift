import Foundation

// MARK: - Reglas de escritura del catálogo (K2a)

extension KitchenData {

    // MARK: - Unidades

    /// Crea una unidad propia del negocio.
    @discardableResult
    public mutating func createUnit(
        name: String,
        abbreviation: String,
        baseUnit: BaseUnit,
        factorToBase: String,
        ctx: MutationContext = MutationContext()
    ) throws -> KitchenUnit {
        var copy = self
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbr = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw DomainError.invalidValue(detail: "El nombre de la unidad no puede estar vacío")
        }
        guard trimmedName.count <= 50 else {
            throw DomainError.invalidValue(detail: "El nombre de la unidad no puede tener más de 50 caracteres")
        }
        guard !trimmedAbbr.isEmpty else {
            throw DomainError.invalidValue(detail: "La abreviatura no puede estar vacía")
        }
        guard trimmedAbbr.count <= 12 else {
            throw DomainError.invalidValue(detail: "La abreviatura no puede tener más de 12 caracteres")
        }
        guard let factor = Qty.decimal(factorToBase), factor > 0 else {
            throw DomainError.invalidValue(detail: "El factor a la unidad base debe ser mayor a cero")
        }

        let nameClean = trimmedName.normalizedName
        let abbrClean = trimmedAbbr.normalizedName

        // Unidades activas del sistema y del negocio
        let activeUnits = SystemUnits.all + copy.units.filter { $0.isActive }
        for u in activeUnits {
            if u.name.normalizedName == nameClean || u.abbreviation.normalizedName == abbrClean {
                throw DomainError.duplicateName(detail: "Ya existe una unidad con ese nombre o abreviatura")
            }
        }

        let unit = KitchenUnit(
            id: ctx.newId(),
            name: trimmedName,
            abbreviation: trimmedAbbr,
            baseUnit: baseUnit,
            factorToBase: Qty.text(factor),
            createdAt: ctx.now,
            updatedAt: ctx.now
        )
        copy.units.append(unit)
        self = copy
        return unit
    }

    /// Edita una unidad propia del negocio. Las unidades del sistema son de solo lectura.
    @discardableResult
    public mutating func updateUnit(
        id: String,
        name: String? = nil,
        abbreviation: String? = nil,
        baseUnit: BaseUnit? = nil,
        factorToBase: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> KitchenUnit {
        var copy = self

        if SystemUnits.isSystem(id) || SystemUnits.byId[id] != nil {
            throw DomainError.systemUnitReadonly(detail: "No se pueden editar unidades del sistema")
        }

        guard let idx = copy.units.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Unidad no encontrada")
        }
        var unit = copy.units[idx]

        let newNameTrimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newName = newNameTrimmed {
            guard !newName.isEmpty else {
                throw DomainError.invalidValue(detail: "El nombre de la unidad no puede estar vacío")
            }
            guard newName.count <= 50 else {
                throw DomainError.invalidValue(detail: "El nombre de la unidad no puede tener más de 50 caracteres")
            }
        }

        let newAbbrTrimmed = abbreviation?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newAbbr = newAbbrTrimmed {
            guard !newAbbr.isEmpty else {
                throw DomainError.invalidValue(detail: "La abreviatura no puede estar vacía")
            }
            guard newAbbr.count <= 12 else {
                throw DomainError.invalidValue(detail: "La abreviatura no puede tener más de 12 caracteres")
            }
        }

        if newNameTrimmed != nil || newAbbrTrimmed != nil {
            let targetName = (newNameTrimmed ?? unit.name).normalizedName
            let targetAbbr = (newAbbrTrimmed ?? unit.abbreviation).normalizedName
            let activeUnits = SystemUnits.all + copy.units.filter { $0.isActive }
            for u in activeUnits where u.id != unit.id {
                if u.name.normalizedName == targetName || u.abbreviation.normalizedName == targetAbbr {
                    throw DomainError.duplicateName(detail: "Ya existe una unidad con ese nombre o abreviatura")
                }
            }
        }

        if let factorToBase {
            guard let factor = Qty.decimal(factorToBase), factor > 0 else {
                throw DomainError.invalidValue(detail: "El factor a la unidad base debe ser mayor a cero")
            }
            unit.factorToBase = Qty.text(factor)
        }

        if let newBase = baseUnit, newBase != unit.baseUnit {
            try copy.checkUnitNotInUse(unitId: unit.id)
            unit.baseUnit = newBase
        }

        if let newName = newNameTrimmed {
            unit.name = newName
        }
        if let newAbbr = newAbbrTrimmed {
            unit.abbreviation = newAbbr
        }

        unit.updatedAt = ctx.now
        copy.units[idx] = unit
        self = copy
        return unit
    }

    /// Elimina una unidad propia marcando `deletedAt`. Las del sistema son de solo lectura.
    public mutating func deleteUnit(
        id: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var copy = self

        if SystemUnits.isSystem(id) || SystemUnits.byId[id] != nil {
            throw DomainError.systemUnitReadonly(detail: "No se pueden eliminar unidades del sistema")
        }

        guard let idx = copy.units.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Unidad no encontrada")
        }

        try copy.checkUnitNotInUse(unitId: id)

        copy.units[idx].deletedAt = ctx.now
        copy.units[idx].updatedAt = ctx.now
        self = copy
    }

    private func checkUnitNotInUse(unitId: String) throws {
        let inIngredient = ingredients.contains { ing in
            ing.isActive && ing.conversions.contains { $0.unitId == unitId }
        }
        if inIngredient {
            throw DomainError.inUse(detail: "La unidad está en uso en ingredientes")
        }

        let inRecipe = recipes.contains { rec in
            rec.isActive && rec.items.contains { $0.unitId == unitId }
        }
        if inRecipe {
            throw DomainError.inUse(detail: "La unidad está en uso en recetas")
        }
    }

    // MARK: - Ingredientes

    /// Crea un ingrediente general con sus equivalencias opcionales.
    @discardableResult
    public mutating func createIngredient(
        name: String,
        baseUnit: BaseUnit,
        group: String? = nil,
        notes: String? = nil,
        conversions: [IngredientConversion] = [],
        ctx: MutationContext = MutationContext()
    ) throws -> Ingredient {
        var copy = self
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw DomainError.invalidValue(detail: "El nombre del ingrediente no puede estar vacío")
        }
        guard trimmedName.count <= 100 else {
            throw DomainError.invalidValue(detail: "El nombre del ingrediente no puede tener más de 100 caracteres")
        }

        let trimmedGroup = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let g = trimmedGroup, g.count > 50 {
            throw DomainError.invalidValue(detail: "El grupo no puede tener más de 50 caracteres")
        }

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = trimmedNotes, n.count > 500 {
            throw DomainError.invalidValue(detail: "Las notas no pueden tener más de 500 caracteres")
        }

        let cleanName = trimmedName.normalizedName
        if copy.ingredients.contains(where: { $0.isActive && $0.name.normalizedName == cleanName }) {
            throw DomainError.duplicateName(detail: "Ya existe un ingrediente con ese nombre")
        }

        try copy.validateConversions(conversions)

        let ingredient = Ingredient(
            id: ctx.newId(),
            name: trimmedName,
            baseUnit: baseUnit,
            group: (trimmedGroup?.isEmpty == true) ? nil : trimmedGroup,
            notes: (trimmedNotes?.isEmpty == true) ? nil : trimmedNotes,
            conversions: conversions,
            referenceIds: nil,
            createdAt: ctx.now,
            updatedAt: ctx.now
        )
        copy.ingredients.append(ingredient)
        self = copy
        return ingredient
    }

    /// Edita un ingrediente. Pasar `.some(nil)` en `group` o `notes` limpia el campo.
    @discardableResult
    public mutating func updateIngredient(
        id: String,
        name: String? = nil,
        baseUnit: BaseUnit? = nil,
        group: String?? = nil,
        notes: String?? = nil,
        conversions: [IngredientConversion]? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Ingredient {
        var copy = self

        guard let idx = copy.ingredients.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Ingrediente no encontrado")
        }
        var ingredient = copy.ingredients[idx]

        if let newName = name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !newName.isEmpty else {
                throw DomainError.invalidValue(detail: "El nombre del ingrediente no puede estar vacío")
            }
            guard newName.count <= 100 else {
                throw DomainError.invalidValue(detail: "El nombre del ingrediente no puede tener más de 100 caracteres")
            }
            let clean = newName.normalizedName
            if copy.ingredients.contains(where: { $0.isActive && $0.id != id && $0.name.normalizedName == clean }) {
                throw DomainError.duplicateName(detail: "Ya existe un ingrediente con ese nombre")
            }
            ingredient.name = newName
        }

        if let newBase = baseUnit, newBase != ingredient.baseUnit {
            let hasPresentation = copy.presentations.contains { $0.isActive && $0.ingredientId == id }
            if hasPresentation {
                throw DomainError.inUse(detail: "No se puede cambiar la unidad base de un ingrediente con presentaciones activas")
            }
            let inRecipe = copy.recipes.contains { rec in
                rec.isActive && rec.items.contains { $0.kind == .ingredient && $0.refId == id }
            }
            if inRecipe {
                throw DomainError.inUse(detail: "El ingrediente está en uso en recetas activas")
            }
            ingredient.baseUnit = newBase
        }

        if let newConversions = conversions {
            let currentUnitIds = Set(ingredient.conversions.map(\.unitId))
            let newUnitIds = Set(newConversions.map(\.unitId))
            let removedUnitIds = currentUnitIds.subtracting(newUnitIds)
            if !removedUnitIds.isEmpty {
                let inRecipe = copy.recipes.contains { rec in
                    rec.isActive && rec.items.contains { item in
                        item.kind == .ingredient && item.refId == id && item.unitId.map { removedUnitIds.contains($0) } ?? false
                    }
                }
                if inRecipe {
                    throw DomainError.inUse(detail: "La conversión está en uso en recetas activas")
                }
            }
            try copy.validateConversions(newConversions)
            ingredient.conversions = newConversions
        }

        if let group {
            if let g = group?.trimmingCharacters(in: .whitespacesAndNewlines) {
                guard g.count <= 50 else {
                    throw DomainError.invalidValue(detail: "El grupo no puede tener más de 50 caracteres")
                }
                ingredient.group = g.isEmpty ? nil : g
            } else {
                ingredient.group = nil
            }
        }

        if let notes {
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines) {
                guard n.count <= 50 else {
                    throw DomainError.invalidValue(detail: "Las notas no pueden tener más de 500 caracteres")
                }
                ingredient.notes = n.isEmpty ? nil : n
            } else {
                ingredient.notes = nil
            }
        }

        ingredient.updatedAt = ctx.now
        copy.ingredients[idx] = ingredient
        self = copy
        return ingredient
    }

    /// Borra un ingrediente marcando `deletedAt`. Borra en cascada sus marcas (presentaciones) activas.
    public mutating func deleteIngredient(
        id: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var copy = self

        guard let idx = copy.ingredients.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Ingrediente no encontrado")
        }

        let inRecipe = copy.recipes.contains { rec in
            rec.isActive && rec.items.contains { $0.kind == .ingredient && $0.refId == id }
        }
        if inRecipe {
            throw DomainError.inUse(detail: "El ingrediente está en uso en recetas activas")
        }

        copy.ingredients[idx].deletedAt = ctx.now
        copy.ingredients[idx].updatedAt = ctx.now

        // Borrar sus presentaciones activas
        for i in 0..<copy.presentations.count {
            if copy.presentations[i].ingredientId == id && copy.presentations[i].isActive {
                copy.presentations[i].deletedAt = ctx.now
                copy.presentations[i].updatedAt = ctx.now
            }
        }

        self = copy
    }

    private func validateConversions(_ conversions: [IngredientConversion]) throws {
        var seenUnits = Set<String>()
        for c in conversions {
            if seenUnits.contains(c.unitId) {
                throw DomainError.invalidReference(detail: "Unidad duplicada en conversiones: \(c.unitId)")
            }
            seenUnits.insert(c.unitId)

            guard let qty = Qty.decimal(c.quantityInBase), qty > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }

            let unitExists = SystemUnits.byId[c.unitId] != nil || units.contains(where: { $0.id == c.unitId && $0.isActive })
            guard unitExists else {
                throw DomainError.invalidReference(detail: "Unidad no encontrada: \(c.unitId)")
            }
        }
    }

    // MARK: - Proveedores

    /// Crea un proveedor.
    @discardableResult
    public mutating func createSupplier(
        name: String,
        notes: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Supplier {
        var copy = self
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw DomainError.invalidValue(detail: "El nombre del proveedor no puede estar vacío")
        }
        guard trimmedName.count <= 100 else {
            throw DomainError.invalidValue(detail: "El nombre del proveedor no puede tener más de 100 caracteres")
        }

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = trimmedNotes, n.count > 500 {
            throw DomainError.invalidValue(detail: "Las notas no pueden tener más de 500 caracteres")
        }

        let clean = trimmedName.normalizedName
        if copy.suppliers.contains(where: { $0.isActive && $0.name.normalizedName == clean }) {
            throw DomainError.duplicateName(detail: "Ya existe un proveedor con ese nombre")
        }

        let supplier = Supplier(
            id: ctx.newId(),
            name: trimmedName,
            notes: (trimmedNotes?.isEmpty == true) ? nil : trimmedNotes,
            createdAt: ctx.now,
            updatedAt: ctx.now
        )
        copy.suppliers.append(supplier)
        self = copy
        return supplier
    }

    /// Edita un proveedor. Pasar `.some(nil)` en `notes` limpia las notas.
    @discardableResult
    public mutating func updateSupplier(
        id: String,
        name: String? = nil,
        notes: String?? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Supplier {
        var copy = self

        guard let idx = copy.suppliers.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Proveedor no encontrado")
        }
        var supplier = copy.suppliers[idx]

        if let newName = name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !newName.isEmpty else {
                throw DomainError.invalidValue(detail: "El nombre del proveedor no puede estar vacío")
            }
            guard newName.count <= 100 else {
                throw DomainError.invalidValue(detail: "El nombre del proveedor no puede tener más de 100 caracteres")
            }
            let clean = newName.normalizedName
            if copy.suppliers.contains(where: { $0.isActive && $0.id != id && $0.name.normalizedName == clean }) {
                throw DomainError.duplicateName(detail: "Ya existe un proveedor con ese nombre")
            }
            supplier.name = newName
        }

        if let notes {
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines) {
                guard n.count <= 500 else {
                    throw DomainError.invalidValue(detail: "Las notas no pueden tener más de 500 caracteres")
                }
                supplier.notes = n.isEmpty ? nil : n
            } else {
                supplier.notes = nil
            }
        }

        supplier.updatedAt = ctx.now
        copy.suppliers[idx] = supplier
        self = copy
        return supplier
    }

    /// Borra un proveedor. Deja `supplierId` nulo en sus marcas activas.
    public mutating func deleteSupplier(
        id: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var copy = self

        guard let idx = copy.suppliers.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Proveedor no encontrado")
        }

        copy.suppliers[idx].deletedAt = ctx.now
        copy.suppliers[idx].updatedAt = ctx.now

        // En presentaciones activas con este proveedor, poner supplierId a nil
        for i in 0..<copy.presentations.count {
            if copy.presentations[i].isActive && copy.presentations[i].supplierId == id {
                copy.presentations[i].supplierId = nil
                copy.presentations[i].updatedAt = ctx.now
            }
        }

        self = copy
    }

    // MARK: - Marcas (Presentaciones) y Precios

    /// Crea una marca de un ingrediente. Si se provee `packageUnitId`, convierte la cantidad a la unidad base.
    /// Si se provee `priceCents`, crea el primer registro de precio.
    @discardableResult
    public mutating func createPresentation(
        ingredientId: String,
        brand: String,
        supplierId: String? = nil,
        packageQuantity: String,
        packageUnitId: String? = nil,
        packCount: Int? = nil,
        packItemQuantity: String? = nil,
        packItemUnitId: String? = nil,
        barcode: String? = nil,
        priceCents: Int? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Presentation {
        var copy = self

        guard let ingredient = copy.ingredients.first(where: { $0.id == ingredientId && $0.isActive }) else {
            throw DomainError.invalidReference(detail: "Ingrediente no encontrado")
        }

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBrand.isEmpty else {
            throw DomainError.invalidValue(detail: "La marca no puede estar vacía")
        }
        guard trimmedBrand.count <= 100 else {
            throw DomainError.invalidValue(detail: "La marca no puede tener más de 100 caracteres")
        }

        if let sid = supplierId, !sid.isEmpty {
            guard copy.suppliers.contains(where: { $0.id == sid && $0.isActive }) else {
                throw DomainError.invalidReference(detail: "Proveedor no encontrado")
            }
        }

        let finalPackCount: Int?
        let finalPackItemQuantity: String?
        let finalPackageQuantity: String

        if let packCount {
            guard packCount >= 1 && packCount <= 10_000 else {
                throw DomainError.invalidValue(detail: "Las piezas del paquete deben ser entre 1 y 10,000")
            }
            guard let packItemQtyStr = packItemQuantity,
                  let itemQty = Qty.decimal(packItemQtyStr),
                  itemQty > 0 else {
                throw DomainError.invalidValue(detail: "Indica cuánto trae cada pieza")
            }
            let convertedItemQty: Decimal
            if let pUnitId = packItemUnitId, !pUnitId.isEmpty {
                convertedItemQty = try copy.costingIndex().convertToBase(
                    quantity: itemQty,
                    unitId: pUnitId,
                    ingredient: ingredient
                )
            } else {
                convertedItemQty = itemQty
            }
            guard convertedItemQty > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }
            finalPackCount = packCount
            finalPackItemQuantity = Qty.text(convertedItemQty)
            finalPackageQuantity = Qty.text(Decimal(packCount) * convertedItemQty)
        } else {
            guard let rawQty = Qty.decimal(packageQuantity), rawQty > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }

            let convertedQty: Decimal
            if let pUnitId = packageUnitId, !pUnitId.isEmpty {
                convertedQty = try copy.costingIndex().convertToBase(
                    quantity: rawQty,
                    unitId: pUnitId,
                    ingredient: ingredient
                )
            } else {
                convertedQty = rawQty
            }

            guard convertedQty > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }

            finalPackCount = nil
            finalPackItemQuantity = nil
            finalPackageQuantity = Qty.text(convertedQty)
        }

        let trimmedBarcode = barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let b = trimmedBarcode, b.count > 100 {
            throw DomainError.invalidValue(detail: "El código de barras no puede tener más de 100 caracteres")
        }

        if let price = priceCents {
            guard price >= 0 else {
                throw DomainError.invalidValue(detail: "El precio no puede ser negativo")
            }
        }

        let presId = ctx.newId()
        let presentation = Presentation(
            id: presId,
            ingredientId: ingredient.id,
            brand: trimmedBrand,
            supplierId: (supplierId?.isEmpty == true) ? nil : supplierId,
            packageQuantity: finalPackageQuantity,
            packCount: finalPackCount,
            packItemQuantity: finalPackItemQuantity,
            barcode: (trimmedBarcode?.isEmpty == true) ? nil : trimmedBarcode,
            referenceIds: nil,
            createdAt: ctx.now,
            updatedAt: ctx.now
        )
        copy.presentations.append(presentation)

        if let price = priceCents {
            let pr = PriceRecord(
                id: ctx.newId(),
                presentationId: presId,
                priceCents: price,
                recordedAt: ctx.now,
                note: nil,
                createdAt: ctx.now,
                updatedAt: ctx.now
            )
            copy.priceRecords.append(pr)
        }

        self = copy
        return presentation
    }

    /// Edita una marca. Pasar `.some(nil)` en `supplierId` o `barcode` limpia el campo.
    @discardableResult
    public mutating func updatePresentation(
        id: String,
        brand: String? = nil,
        supplierId: String?? = nil,
        packageQuantity: String? = nil,
        packageUnitId: String? = nil,
        packCount: Int?? = nil,
        packItemQuantity: String? = nil,
        packItemUnitId: String? = nil,
        barcode: String?? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> Presentation {
        var copy = self

        guard let idx = copy.presentations.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Presentación no encontrada")
        }
        var presentation = copy.presentations[idx]

        if let newBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !newBrand.isEmpty else {
                throw DomainError.invalidValue(detail: "La marca no puede estar vacía")
            }
            guard newBrand.count <= 100 else {
                throw DomainError.invalidValue(detail: "La marca no puede tener más de 100 caracteres")
            }
            presentation.brand = newBrand
        }

        if let supplierId {
            if let sid = supplierId, !sid.isEmpty {
                guard copy.suppliers.contains(where: { $0.id == sid && $0.isActive }) else {
                    throw DomainError.invalidReference(detail: "Proveedor no encontrado")
                }
                presentation.supplierId = sid
            } else {
                presentation.supplierId = nil
            }
        }

        func applyPackageQuantity(_ newQtyStr: String) throws {
            guard let rawQty = Qty.decimal(newQtyStr), rawQty > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }
            let convertedQty: Decimal
            if let pUnitId = packageUnitId, !pUnitId.isEmpty {
                guard let ingredient = copy.ingredients.first(where: { $0.id == presentation.ingredientId && $0.isActive }) else {
                    throw DomainError.notFound(detail: "Ingrediente no encontrado")
                }
                convertedQty = try copy.costingIndex().convertToBase(
                    quantity: rawQty,
                    unitId: pUnitId,
                    ingredient: ingredient
                )
            } else {
                convertedQty = rawQty
            }
            guard convertedQty > 0 else {
                throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
            }
            presentation.packageQuantity = Qty.text(convertedQty)
        }

        if let packCountOpt = packCount {
            if let n = packCountOpt {
                guard n >= 1 && n <= 10_000 else {
                    throw DomainError.invalidValue(detail: "Las piezas del paquete deben ser entre 1 y 10,000")
                }
                guard let packItemQtyStr = packItemQuantity,
                      let itemQty = Qty.decimal(packItemQtyStr),
                      itemQty > 0 else {
                    throw DomainError.invalidValue(detail: "Indica cuánto trae cada pieza")
                }
                guard let ingredient = copy.ingredients.first(where: { $0.id == presentation.ingredientId && $0.isActive }) else {
                    throw DomainError.notFound(detail: "Ingrediente no encontrado")
                }
                let convertedItemQty: Decimal
                if let pUnitId = packItemUnitId, !pUnitId.isEmpty {
                    convertedItemQty = try copy.costingIndex().convertToBase(
                        quantity: itemQty,
                        unitId: pUnitId,
                        ingredient: ingredient
                    )
                } else {
                    convertedItemQty = itemQty
                }
                guard convertedItemQty > 0 else {
                    throw DomainError.invalidReference(detail: "La cantidad debe ser mayor que cero")
                }
                presentation.packCount = n
                presentation.packItemQuantity = Qty.text(convertedItemQty)
                presentation.packageQuantity = Qty.text(Decimal(n) * convertedItemQty)
            } else {
                presentation.packCount = nil
                presentation.packItemQuantity = nil
                if let newQtyStr = packageQuantity {
                    try applyPackageQuantity(newQtyStr)
                }
            }
        } else {
            if let newQtyStr = packageQuantity {
                try applyPackageQuantity(newQtyStr)
                presentation.packCount = nil
                presentation.packItemQuantity = nil
            }
        }

        if let barcode {
            if let b = barcode?.trimmingCharacters(in: .whitespacesAndNewlines) {
                guard b.count <= 100 else {
                    throw DomainError.invalidValue(detail: "El código de barras no puede tener más de 100 caracteres")
                }
                presentation.barcode = b.isEmpty ? nil : b
            } else {
                presentation.barcode = nil
            }
        }

        presentation.updatedAt = ctx.now
        copy.presentations[idx] = presentation
        self = copy
        return presentation
    }

    /// Borra una marca fijada. Si está fijada en una receta activa lanza `IN_USE`.
    /// La quita de las elecciones de las versiones de costeo activas.
    public mutating func deletePresentation(
        id: String,
        ctx: MutationContext = MutationContext()
    ) throws {
        var copy = self

        guard let idx = copy.presentations.firstIndex(where: { $0.id == id && $0.isActive }) else {
            throw DomainError.notFound(detail: "Presentación no encontrada")
        }

        let inRecipe = copy.recipes.contains { rec in
            rec.isActive && rec.items.contains { $0.pinnedPresentationId == id }
        }
        if inRecipe {
            throw DomainError.inUse(detail: "La presentación está en uso en recetas activas")
        }

        copy.presentations[idx].deletedAt = ctx.now
        copy.presentations[idx].updatedAt = ctx.now

        // Quitar de las elecciones de las versiones de costeo activas
        for i in 0..<copy.costVersions.count {
            if copy.costVersions[i].isActive && copy.costVersions[i].choices.contains(where: { $0.presentationId == id }) {
                copy.costVersions[i].choices.removeAll { $0.presentationId == id }
                copy.costVersions[i].updatedAt = ctx.now
            }
        }

        self = copy
    }

    /// Agrega un registro al historial de precios de una marca.
    @discardableResult
    public mutating func addPrice(
        presentationId: String,
        priceCents: Int,
        recordedAt: Date? = nil,
        note: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> PriceRecord {
        var copy = self

        guard copy.presentations.contains(where: { $0.id == presentationId && $0.isActive }) else {
            throw DomainError.notFound(detail: "Presentación no encontrada")
        }

        guard priceCents >= 0 else {
            throw DomainError.invalidValue(detail: "El precio no puede ser negativo")
        }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = trimmedNote, n.count > 200 {
            throw DomainError.invalidValue(detail: "La nota no puede tener más de 200 caracteres")
        }

        let price = PriceRecord(
            id: ctx.newId(),
            presentationId: presentationId,
            priceCents: priceCents,
            recordedAt: recordedAt ?? ctx.now,
            note: (trimmedNote?.isEmpty == true) ? nil : trimmedNote,
            createdAt: ctx.now,
            updatedAt: ctx.now
        )
        copy.priceRecords.append(price)
        self = copy
        return price
    }
}
