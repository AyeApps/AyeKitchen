#if DEBUG
import Foundation
import os

/// Cuenta de prueba SOLO para builds Debug: correo `test` y contraseña `test` entran sin servidor.
///
/// Sirve para probar como cuenta nueva (onboarding, Primeros pasos) sin otra cuenta Apple.
/// Vive solo en el teléfono: no hay tokens, así que toda petición autorizada se comporta como
/// "sin internet" (no sube respaldos y no cierra la sesión). Al cerrar la app hay que volver a
/// entrar con test/test; los datos siguen en su archivo local. Nada de esto existe en Release.
enum DebugAccount {
    static let id = "debug-test-account"

    static let me = Me(
        id: id,
        email: "test",
        name: "Cuenta de prueba",
        avatarUrl: nil,
        workspace: Workspace(
            id: "debug-test-workspace",
            name: "Mi cocina",
            currency: "MXN",
            defaultMarginPercent: 40,
            priceStaleDays: 90
        )
    )

    static func matches(email: String, password: String) -> Bool {
        email.trimmingCharacters(in: .whitespaces).lowercased() == "test" && password == "test"
    }

    private nonisolated static let activeLock = OSAllocatedUnfairLock(initialState: false)

    /// Lo lee `NetworkService` (otro aislamiento), por eso va con candado.
    nonisolated static var isActive: Bool {
        get { activeLock.withLock { $0 } }
        set { activeLock.withLock { $0 = newValue } }
    }
}
#endif
