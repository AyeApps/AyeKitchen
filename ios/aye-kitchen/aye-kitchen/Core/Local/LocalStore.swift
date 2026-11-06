import Foundation
import KitchenDomain
import Observation

/// Los datos del negocio en el teléfono (docs/backup-format.md). Única fuente de verdad de la app.
///
/// - Vive en memoria mientras la app corre y se guarda en
///   `Application Support/Kitchen/<cuenta>/kitchen.json` (un archivo por cuenta).
/// - Las pantallas LEEN con `data` y las consultas de KitchenKit (`data.ingredients(...)`,
///   `data.calculateRecipeCost(...)`…), y ESCRIBEN solo con `mutate`, que aplica una regla de
///   KitchenKit, guarda el archivo y avisa al respaldo. Nunca modifiques `data` de otra forma.
/// - `revision` sube con cada cambio: úsalo en `.onChange`/`.task(id:)` si una vista calcula algo caro.
///
/// Uso desde un Model (bloques I16–I19):
///
///     let store = LocalStore.shared
///     let list = store.data.catalogIngredients(query: text, now: .now)           // leer
///     try store.mutate { data, ctx in try data.createIngredient(input, ctx) }   // escribir
///
/// `mutate` lanza `DomainError` (decide por `error.code`, muestra `error.detail`).
@Observable
final class LocalStore {
    static let shared = LocalStore()

    enum State: Equatable {
        /// Sin cuenta o todavía leyendo el archivo.
        case idle
        /// Datos listos.
        case ready
        /// No hay archivo local: `LocalBootstrap` debe traer los datos (respaldo o servidor).
        case needsData
        /// El archivo existe pero no se pudo leer (lo escribió una versión más nueva o está dañado).
        case unreadable(String)
    }

    private(set) var state: State = .idle
    private(set) var data: KitchenData
    /// Sube con cada cambio guardado.
    private(set) var revision = 0
    /// Hay cambios que todavía no se respaldan.
    private(set) var hasUnbackedChanges = false

    private var accountId: String?
    private var saveTask: Task<Void, Never>?
    /// Avisa a `BackupService` que hubo un cambio (para el respaldo automático).
    var onChange: (() -> Void)?

    private init() {
        data = KitchenData.empty(deviceId: LocalStore.deviceId)
    }

    #if DEBUG
    /// Para previews: un almacén aparte, ya listo, con estos datos. No lee ni escribe archivos.
    /// Los Model reciben `store: LocalStore = .shared`; en el preview pásales este.
    static func preview(_ data: KitchenData = .previewSample) -> LocalStore {
        let store = LocalStore()
        store.data = data
        store.state = .ready
        return store
    }
    #endif

    // MARK: Cuenta y archivo

    /// Lee el archivo de esta cuenta. Si no existe, `state` queda en `.needsData`.
    func open(accountId: String) {
        guard self.accountId != accountId || state != .ready else { return }
        self.accountId = accountId
        saveTask?.cancel()
        revision = 0
        hasUnbackedChanges = UserDefaults.standard.bool(forKey: unbackedKey)
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            data = KitchenData.empty(deviceId: Self.deviceId)
            state = .needsData
            return
        }
        do {
            data = try KitchenCoding.decode(Data(contentsOf: url))
            state = .ready
        } catch KitchenCodingError.newerSchema {
            state = .unreadable("Tus datos los guardó una versión más nueva de AyeKitchen. Actualiza la app.")
        } catch {
            state = .unreadable("No pudimos leer tus datos guardados.")
        }
    }

    /// Cierra la cuenta (cerrar sesión). El archivo se queda en el teléfono para cuando vuelva a entrar.
    func close() {
        flushNow()
        accountId = nil
        data = KitchenData.empty(deviceId: Self.deviceId)
        state = .idle
        revision = 0
    }

    /// Cierra sin guardar y borra la carpeta de esta cuenta y su marca de respaldo (al eliminar la cuenta).
    func discardAccount() {
        saveTask?.cancel()
        UserDefaults.standard.removeObject(forKey: unbackedKey)
        if let folder = fileURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: folder)
        }
        accountId = nil
        data = KitchenData.empty(deviceId: Self.deviceId)
        state = .idle
        revision = 0
        hasUnbackedChanges = false
    }

    // MARK: Escribir

    /// Aplica una regla de KitchenKit sobre una copia; si no lanza, la copia pasa a ser los datos,
    /// se guarda el archivo y se marca para respaldo. Si lanza, nada cambia.
    @discardableResult
    func mutate<T>(_ change: (inout KitchenData, MutationContext) throws -> T) throws -> T {
        guard state == .ready else {
            throw DomainError.invalidValue(detail: "Tus datos todavía no están listos.")
        }
        var copy = data
        let result = try change(&copy, MutationContext())
        data = copy
        afterChange()
        return result
    }

    /// Reemplaza todo (primera descarga o restaurar un respaldo). No marca cambios por respaldar:
    /// lo que llega ya está en el servidor.
    func replaceAll(with newData: KitchenData, backedUp: Bool) {
        var adopted = newData
        adopted.deviceId = Self.deviceId
        data = adopted
        state = .ready
        revision += 1
        setUnbacked(!backedUp)
        flushNow()
    }

    /// El respaldo se subió: los cambios hasta aquí ya están en el servidor.
    func markBackedUp(revision backedRevision: Int) {
        if backedRevision == revision {
            setUnbacked(false)
        }
    }

    // MARK: Internos

    private func afterChange() {
        revision += 1
        setUnbacked(true)
        scheduleSave()
        onChange?()
    }

    private func setUnbacked(_ value: Bool) {
        hasUnbackedChanges = value
        UserDefaults.standard.set(value, forKey: unbackedKey)
    }

    /// Guarda medio segundo después del último cambio, fuera del hilo principal.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushNow()
        }
    }

    /// Escribe ya (al cerrar la cuenta, al irse la app a segundo plano).
    func flushNow() {
        saveTask?.cancel()
        guard state == .ready, let url = fileURL else { return }
        var snapshot = data
        snapshot.exportedAt = Date()
        writeSequence += 1
        let payload = snapshot
        let sequence = writeSequence
        Task.detached(priority: .utility) {
            await LocalFileWriter.shared.write(payload, to: url, sequence: sequence)
        }
    }

    private var writeSequence = 0

    private var fileURL: URL? {
        guard let accountId,
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Kitchen", isDirectory: true)
            .appendingPathComponent(accountId, isDirectory: true)
            .appendingPathComponent("kitchen.json")
    }

    private var unbackedKey: String { "LocalStore.unbacked.\(accountId ?? "-")" }

    /// Id estable de este teléfono para `device_id` del respaldo.
    static var deviceId: String {
        let key = "LocalStore.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString.lowercased()
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}

/// Escribe el archivo fuera del hilo principal. Si llegan dos escrituras desordenadas, la más
/// vieja (secuencia menor) se ignora: el archivo nunca retrocede.
actor LocalFileWriter {
    static let shared = LocalFileWriter()
    private var lastWritten: [URL: Int] = [:]

    func write(_ data: KitchenData, to url: URL, sequence: Int) {
        guard sequence > (lastWritten[url] ?? 0) else { return }
        do {
            let encoded = try KitchenCoding.encode(data)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastWritten[url] = sequence
        } catch {
            // Si falla, el siguiente cambio lo vuelve a intentar; los datos siguen en memoria.
        }
    }
}

