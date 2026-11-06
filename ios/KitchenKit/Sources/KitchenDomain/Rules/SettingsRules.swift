import Foundation

/// Modificaciones y validaciones para los ajustes del negocio (bloque K3).
///
/// Reglas:
/// - `name`: recortado, de 1 a 80 caracteres.
/// - `defaultMarginPercent`: de 0 a 1000 %.
/// - `priceStaleDays`: de 1 a 3650 días.
/// - `currency`: 3 letras mayúsculas (ej. "MXN").
/// - Si un valor está fuera de rango o vacío, lanza `DomainError.invalidValue`.
/// - Si lanza, `KitchenData` queda intacto (operación atómica).

public struct SettingsUpdateDraft: Sendable {
    public var name: String?
    public var currency: String?
    public var defaultMarginPercent: Int?
    public var priceStaleDays: Int?
    public var timezone: String?

    public init(
        name: String? = nil,
        currency: String? = nil,
        defaultMarginPercent: Int? = nil,
        priceStaleDays: Int? = nil,
        timezone: String? = nil
    ) {
        self.name = name
        self.currency = currency
        self.defaultMarginPercent = defaultMarginPercent
        self.priceStaleDays = priceStaleDays
        self.timezone = timezone
    }
}

extension KitchenData {
    /// Actualiza los ajustes del negocio con cambios parciales.
    ///
    /// Valida cada campo modificado y lanza `DomainError.invalidValue` con una explicación
    /// en palabras de la cocina si algún dato está fuera de rango o vacío.
    /// Si ocurre un error, los datos no se modifican.
    @discardableResult
    public mutating func updateSettings(
        draft: SettingsUpdateDraft,
        ctx: MutationContext = MutationContext()
    ) throws -> KitchenSettings {
        var clone = self
        var newSettings = clone.settings

        if let name = draft.name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidValue(detail: "El nombre del negocio no puede estar vacío")
            }
            guard trimmed.count <= 80 else {
                throw DomainError.invalidValue(detail: "El nombre del negocio no puede tener más de 80 caracteres")
            }
            newSettings.name = trimmed
        }

        if let margin = draft.defaultMarginPercent {
            guard (0...1000).contains(margin) else {
                throw DomainError.invalidValue(detail: "El margen va de 0 % a 1000 %")
            }
            newSettings.defaultMarginPercent = margin
        }

        if let staleDays = draft.priceStaleDays {
            guard (1...3650).contains(staleDays) else {
                throw DomainError.invalidValue(detail: "Los días para considerar un precio viejo van de 1 a 3650")
            }
            newSettings.priceStaleDays = staleDays
        }

        if let currency = draft.currency {
            let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines)
            let isThreeUppercase = trimmed.count == 3 && trimmed.allSatisfy { $0 >= "A" && $0 <= "Z" }
            guard isThreeUppercase else {
                throw DomainError.invalidValue(detail: "La moneda debe tener 3 letras mayúsculas")
            }
            newSettings.currency = trimmed
        }

        if let tz = draft.timezone {
            let trimmed = tz.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidValue(detail: "La zona horaria no puede estar vacía")
            }
            newSettings.timezone = trimmed
        }

        clone.settings = newSettings
        self = clone
        return newSettings
    }

    /// Sobrecarga conveniente con parámetros nombrados.
    @discardableResult
    public mutating func updateSettings(
        name: String? = nil,
        currency: String? = nil,
        defaultMarginPercent: Int? = nil,
        priceStaleDays: Int? = nil,
        timezone: String? = nil,
        ctx: MutationContext = MutationContext()
    ) throws -> KitchenSettings {
        try updateSettings(
            draft: SettingsUpdateDraft(
                name: name,
                currency: currency,
                defaultMarginPercent: defaultMarginPercent,
                priceStaleDays: priceStaleDays,
                timezone: timezone
            ),
            ctx: ctx
        )
    }
}
