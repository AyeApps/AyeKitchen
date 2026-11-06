import Foundation
import KitchenDomain
import Observation

/// Prepara los datos locales al entrar con una cuenta.
///
/// 1. Si el teléfono ya tiene el archivo de esta cuenta, lo abre y listo (sin red).
/// 2. Si no: baja el último respaldo; si no hay, trae lo que hoy tiene el servidor en sus
///    colecciones (la migración a la app local, una sola vez) y lo sube como primer respaldo.
/// 3. Sin red y sin archivo: `failed` con un mensaje para reintentar.
///
/// `RootView` muestra `MainTabView` solo cuando `state == .ready`.
@Observable
final class LocalBootstrap {
    static let shared = LocalBootstrap()

    enum State: Equatable {
        case idle
        /// Bajando los datos por primera vez.
        case downloading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle

    private init() {}

    func prepare(accountId: String) async {
        let store = LocalStore.shared
        BackupService.shared.useAccount(accountId)
        ReferenceStore.shared.open(accountId: accountId)
        store.onChange = { BackupScheduler.shared.noteChange() }
        store.open(accountId: accountId)

        switch store.state {
        case .ready:
            state = .ready
        case .unreadable(let message):
            state = .failed(message)
        case .needsData, .idle:
            #if DEBUG
            if accountId == DebugAccount.id {
                store.replaceAll(with: KitchenData.empty(deviceId: LocalStore.deviceId), backedUp: true)
                state = .ready
                return
            }
            #endif
            state = .downloading
            do {
                if try await BackupService.shared.restoreLatest() {
                    state = .ready
                } else {
                    let current = try await BackupService.shared.exportCurrentServerData()
                    store.replaceAll(with: current, backedUp: false)
                    state = .ready
                    try? await BackupService.shared.backupNow()
                }
            } catch {
                state = .failed("La primera vez necesitamos internet para traer tus datos. \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        state = .idle
        ReferenceStore.shared.close()
    }
}

/// Respaldo automático: sube 2 minutos después del último cambio, y al irse la app a segundo
/// plano si hay cambios sin respaldar. Los errores se guardan en `BackupService.lastError`
/// (la pantalla de respaldo los muestra); un conflicto nunca se resuelve solo.
@Observable
final class BackupScheduler {
    static let shared = BackupScheduler()

    var idleDelay: Duration = .seconds(120)
    private var pending: Task<Void, Never>?

    private init() {}

    func noteChange() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let delay = self?.idleDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.backupIfNeeded()
        }
    }

    /// Al pasar a segundo plano.
    func appDidEnterBackground() {
        LocalStore.shared.flushNow()
        pending?.cancel()
        Task { await backupIfNeeded() }
    }

    private func backupIfNeeded() async {
        guard LocalStore.shared.hasUnbackedChanges else { return }
        if case .conflict = BackupService.shared.lastError { return }
        try? await BackupService.shared.backupNow()
    }
}
