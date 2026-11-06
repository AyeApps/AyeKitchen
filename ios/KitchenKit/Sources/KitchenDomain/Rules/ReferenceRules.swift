import Foundation

extension ReferenceImage: SoftDeletable {}

/// Dueño de una imagen de referencia (soporta hasta 5 por dueño).
public enum ReferenceOwner: Hashable, Sendable {
    case ingredient(String)
    case presentation(String)
    case recipe(String)
    case order(String)
    case expense(String)

    public var id: String {
        switch self {
        case .ingredient(let id),
             .presentation(let id),
             .recipe(let id),
             .order(let id),
             .expense(let id):
            return id
        }
    }
}

extension KitchenData {
    // MARK: - Consultas

    /// Referencias activas asignadas a un dueño, en el orden de `referenceIds`.
    /// Si el dueño está borrado o no existe, regresa un arreglo vacío.
    public func references(of owner: ReferenceOwner) -> [ReferenceImage] {
        guard isOwnerActive(owner),
              let ids = ownerReferenceIds(owner),
              !ids.isEmpty else {
            return []
        }
        let activeRefs = Dictionary(uniqueKeysWithValues: references.filter(\.isActive).map { ($0.id, $0) })
        return ids.compactMap { activeRefs[$0] }
    }

    /// Todas las referencias activas en el documento.
    public func activeReferences() -> [ReferenceImage] {
        references.filter(\.isActive)
    }

    /// Ids de referencias borradas (para que la app borre los bytes locales y el respaldo las quite).
    public func deletedReferenceIds() -> [String] {
        references.filter { !$0.isActive }.map(\.id)
    }

    // MARK: - Modificaciones

    /// Agrega una imagen de referencia a un dueño activo.
    /// - El dueño debe existir y estar activo (`notFound` si no).
    /// - Máximo 5 referencias activas por dueño (`invalidValue` con "Puedes guardar hasta 5 fotos").
    /// - `image.id` no puede existir ya (`invalidValue`).
    /// - Agrega la imagen a `references` (con `createdAt`/`updatedAt` de `ctx`) y su id al final de
    ///   `referenceIds` del dueño (creando la lista si era nula); actualiza `updatedAt` del dueño.
    public mutating func addReference(
        _ image: ReferenceImage,
        to owner: ReferenceOwner,
        _ ctx: MutationContext = MutationContext()
    ) throws {
        // 1. Validar que el dueño existe y está activo
        guard isOwnerActive(owner) else {
            throw DomainError.notFound(detail: ownerNotFoundDetail(owner))
        }

        // 2. Máximo 5 referencias activas por dueño
        let currentActive = references(of: owner)
        guard currentActive.count < 5 else {
            throw DomainError.invalidValue(detail: "Puedes guardar hasta 5 fotos")
        }

        // 3. image.id no puede existir ya
        guard !image.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainError.invalidValue(detail: "El id de la referencia no puede estar vacío")
        }
        guard !references.contains(where: { $0.id == image.id }) else {
            throw DomainError.invalidValue(detail: "Ya existe una referencia con ese id")
        }

        // 4. Modificar imagen
        var newImage = image
        newImage.createdAt = ctx.now
        newImage.updatedAt = ctx.now
        newImage.deletedAt = nil

        // 5. Agregar id al dueño y actualizar updatedAt
        var ids = ownerReferenceIds(owner) ?? []
        ids.append(image.id)
        try updateReferenceIds(for: owner, ids: ids, updatedAt: ctx.now)

        references.append(newImage)
    }

    /// Quita una referencia de un dueño y la marca como borrada.
    /// - La quita de `referenceIds` (si queda vacía, `nil`).
    /// - Marca la imagen con `deletedAt` y `updatedAt`.
    /// - Si la referencia no está en ese dueño o el dueño no existe, lanza `notFound`.
    public mutating func removeReference(
        _ referenceId: String,
        from owner: ReferenceOwner,
        _ ctx: MutationContext = MutationContext()
    ) throws {
        guard isOwnerActive(owner) else {
            throw DomainError.notFound(detail: ownerNotFoundDetail(owner))
        }

        guard var ids = ownerReferenceIds(owner),
              let indexInOwner = ids.firstIndex(of: referenceId) else {
            throw DomainError.notFound(detail: "Referencia no encontrada")
        }

        guard let refIndex = references.firstIndex(where: { $0.id == referenceId && $0.isActive }) else {
            throw DomainError.notFound(detail: "Referencia no encontrada")
        }

        ids.remove(at: indexInOwner)
        let newIds: [String]? = ids.isEmpty ? nil : ids
        try updateReferenceIds(for: owner, ids: newIds, updatedAt: ctx.now)

        references[refIndex].deletedAt = ctx.now
        references[refIndex].updatedAt = ctx.now
    }

    /// Reordena una referencia dentro de la lista del dueño.
    public mutating func moveReference(
        _ referenceId: String,
        in owner: ReferenceOwner,
        toIndex: Int,
        _ ctx: MutationContext = MutationContext()
    ) throws {
        guard isOwnerActive(owner) else {
            throw DomainError.notFound(detail: ownerNotFoundDetail(owner))
        }

        guard var ids = ownerReferenceIds(owner),
              let fromIndex = ids.firstIndex(of: referenceId) else {
            throw DomainError.notFound(detail: "Referencia no encontrada")
        }

        guard toIndex >= 0 && toIndex < ids.count else {
            throw DomainError.invalidValue(detail: "Índice fuera de rango")
        }

        if fromIndex != toIndex {
            ids.remove(at: fromIndex)
            ids.insert(referenceId, at: toIndex)
            try updateReferenceIds(for: owner, ids: ids, updatedAt: ctx.now)
        }
    }

    // MARK: - Auxiliares privados

    private func isOwnerActive(_ owner: ReferenceOwner) -> Bool {
        switch owner {
        case .ingredient(let id):
            return ingredients.active(id) != nil
        case .presentation(let id):
            return presentations.active(id) != nil
        case .recipe(let id):
            return recipes.active(id) != nil
        case .order(let id):
            return orders.active(id) != nil
        case .expense(let id):
            return expenses.active(id) != nil
        }
    }

    private func ownerReferenceIds(_ owner: ReferenceOwner) -> [String]? {
        switch owner {
        case .ingredient(let id):
            return ingredients.active(id)?.referenceIds
        case .presentation(let id):
            return presentations.active(id)?.referenceIds
        case .recipe(let id):
            return recipes.active(id)?.referenceIds
        case .order(let id):
            return orders.active(id)?.referenceIds
        case .expense(let id):
            return expenses.active(id)?.referenceIds
        }
    }

    private func ownerNotFoundDetail(_ owner: ReferenceOwner) -> String {
        switch owner {
        case .ingredient:
            return "Ingrediente no encontrado"
        case .presentation:
            return "Presentación no encontrada"
        case .recipe:
            return "Receta no encontrada"
        case .order:
            return "Pedido no encontrado"
        case .expense:
            return "Gasto no encontrado"
        }
    }

    private mutating func updateReferenceIds(
        for owner: ReferenceOwner,
        ids: [String]?,
        updatedAt: Date
    ) throws {
        switch owner {
        case .ingredient(let id):
            guard let idx = ingredients.activeIndex(of: id) else {
                throw DomainError.notFound(detail: "Ingrediente no encontrado")
            }
            ingredients[idx].referenceIds = ids
            ingredients[idx].updatedAt = updatedAt
        case .presentation(let id):
            guard let idx = presentations.activeIndex(of: id) else {
                throw DomainError.notFound(detail: "Presentación no encontrada")
            }
            presentations[idx].referenceIds = ids
            presentations[idx].updatedAt = updatedAt
        case .recipe(let id):
            guard let idx = recipes.activeIndex(of: id) else {
                throw DomainError.notFound(detail: "Receta no encontrada")
            }
            recipes[idx].referenceIds = ids
            recipes[idx].updatedAt = updatedAt
        case .order(let id):
            guard let idx = orders.activeIndex(of: id) else {
                throw DomainError.notFound(detail: "Pedido no encontrado")
            }
            orders[idx].referenceIds = ids
            orders[idx].updatedAt = updatedAt
        case .expense(let id):
            guard let idx = expenses.activeIndex(of: id) else {
                throw DomainError.notFound(detail: "Gasto no encontrado")
            }
            expenses[idx].referenceIds = ids
            expenses[idx].updatedAt = updatedAt
        }
    }
}
