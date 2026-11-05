import Foundation

/// Lo que toda escritura necesita y que las pruebas deben poder fijar: la hora y cómo crear ids.
///
/// Convención de las reglas (bloques K2a, K2b, K2c): cada operación es un método `mutating` de
/// `KitchenData` en `Rules/<Área>Rules.swift`, que recibe un `MutationContext`, valida como el
/// servicio equivalente del backend (`backend/app/services/<área>_service.py`), lanza `DomainError`
/// con el mismo código y el mismo texto, y si todo está bien modifica los arreglos:
/// - crear: `id = ctx.newId()`, `createdAt = updatedAt = ctx.now`;
/// - editar: `updatedAt = ctx.now`;
/// - borrar: `deletedAt = updatedAt = ctx.now` (nunca se quita del arreglo).
/// Si lanza, `KitchenData` queda exactamente como estaba (validar todo antes de escribir).
/// Las consultas ignoran lo que tiene `deletedAt`, salvo que el método diga lo contrario.
public struct MutationContext: Sendable {
    public var now: Date
    public var newId: @Sendable () -> String

    public init(now: Date = Date(), newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.now = now
        self.newId = newId
    }
}

extension String {
    /// Para comparar nombres sin distinguir mayúsculas ni espacios de los lados (DUPLICATE_NAME).
    var normalizedName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
