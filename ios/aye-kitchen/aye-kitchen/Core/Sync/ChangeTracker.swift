import Foundation
import Observation

/// `GET /me/changes` (B8): cuándo cambió por última vez lo que muestra cada sección.
/// Nulo = esa sección nunca ha tenido datos.
nonisolated struct DataChanges: Decodable, Sendable, Hashable {
    let home: Date?
    let orders: Date?
    let recipes: Date?
    let catalog: Date?
    let customers: Date?

    func stamp(for section: ChangeTracker.Section) -> Date? {
        switch section {
        case .home: home
        case .orders: orders
        case .recipes: recipes
        case .catalog: catalog
        case .customers: customers
        }
    }
}

/// Decide cuándo una pestaña tiene que volver a pedir sus datos, para no gastar datos de más.
///
/// Uso desde el Model de una pestaña (ver bloque I13):
///
///     // Al aparecer la pantalla, si ya tiene datos (de memoria o de la caché en disco):
///     await ChangeTracker.shared.reloadIfStale(.recipes) { await self.reloadSilently() }
///     // Jalar para refrescar:
///     await ChangeTracker.shared.forceReload(.recipes) { await self.reloadSilently() }
///
/// El closure recarga sin mostrar el indicador de carga y devuelve `true` si la carga salió bien.
/// La sección queda "al día" con la marca de cambios que se pidió ANTES de recargar, así un
/// cambio que ocurra durante la carga se detecta la siguiente vez.
///
/// Recarga si: nunca se cargó, la marca del servidor es distinta a la de la última carga, o la
/// última carga tiene más de `maxAge` (red de seguridad, y para lo que cambia con la fecha,
/// como los precios viejos). Si `/me/changes` falla (sin red), no recarga: se quedan los datos.
@Observable
final class ChangeTracker {
    enum Section: String, CaseIterable, Sendable {
        case home, orders, recipes, catalog, customers
    }

    static let shared = ChangeTracker()

    /// Más viejo que esto, se recarga aunque la marca no haya cambiado.
    var maxAge: TimeInterval = 30 * 60
    /// Varias pestañas que aparecen seguidas comparten una sola consulta a `/me/changes`.
    private let changesReuseWindow: TimeInterval = 5

    private var accountId: String?
    private var lastChanges: DataChanges?
    private var lastChangesAt: Date?
    private var inFlight: Task<DataChanges?, Never>?

    private struct Seen: Codable {
        var stamp: Date?
        var loadedAt: Date
    }

    private var seen: [String: Seen] = [:]

    private var defaultsKey: String? {
        accountId.map { "ChangeTracker.seen.\($0)" }
    }

    /// Cuenta activa: carga lo que ya se había visto en esta cuenta (sobrevive a cerrar la app).
    func useAccount(_ id: String?) {
        accountId = id
        lastChanges = nil
        lastChangesAt = nil
        inFlight = nil
        seen = [:]
        if let key = defaultsKey,
           let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode([String: Seen].self, from: data) {
            seen = stored
        }
    }

    /// Olvida todo (cerrar sesión).
    func reset() {
        if let key = defaultsKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        useAccount(nil)
    }

    /// Recarga la sección solo si cambió algo en el servidor (o es muy vieja).
    func reloadIfStale(_ section: Section, reload: () async -> Bool) async {
        let changes = await currentChanges()
        let previous = seen[section.rawValue]
        let needsReload: Bool = {
            guard let previous else { return true }
            if Date().timeIntervalSince(previous.loadedAt) > maxAge { return true }
            guard let changes else { return false }
            return changes.stamp(for: section) != previous.stamp
        }()
        guard needsReload else { return }
        if await reload() {
            markLoaded(section, stamp: changes?.stamp(for: section))
        }
    }

    /// Recarga siempre (jalar para refrescar, primera carga sin caché).
    func forceReload(_ section: Section, reload: () async -> Bool) async {
        let changes = await currentChanges(forceFetch: true)
        if await reload() {
            markLoaded(section, stamp: changes?.stamp(for: section))
        }
    }

    /// Marca la sección como al día sin pedir `/me/changes` (ej. después de guardar algo desde la
    /// misma pantalla y recargar). La siguiente comparación pedirá la marca nueva.
    func invalidate(_ section: Section) {
        seen[section.rawValue] = nil
        persist()
    }

    // MARK: Internos

    private func markLoaded(_ section: Section, stamp: Date?) {
        seen[section.rawValue] = Seen(stamp: stamp, loadedAt: Date())
        persist()
    }

    private func persist() {
        guard let key = defaultsKey, let data = try? JSONEncoder().encode(seen) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func currentChanges(forceFetch: Bool = false) async -> DataChanges? {
        if !forceFetch, let lastChangesAt, Date().timeIntervalSince(lastChangesAt) < changesReuseWindow {
            return lastChanges
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task<DataChanges?, Never> {
            try? await NetworkService.shared.request(.get, "/me/changes")
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if let result {
            lastChanges = result
            lastChangesAt = Date()
        }
        return result
    }
}
