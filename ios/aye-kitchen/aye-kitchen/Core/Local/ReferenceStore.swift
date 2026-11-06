import CryptoKit
import Foundation
import ImageIO
import KitchenDomain
import Observation
import UIKit
import UniformTypeIdentifiers

/// Almacén de imágenes de referencia en el teléfono (docs/backup-format.md).
///
/// - Guarda las imágenes en `Application Support/Kitchen/<cuenta>/references/<id>.jpg` (o `.heic`),
///   con protección de archivo `.completeFileProtectionUntilFirstUserAuthentication`.
/// - Comprime a JPEG calidad 0.7 (lado mayor 1600 px, respetando orientación; máx. 2 MB)
///   y calcula SHA-256 antes de guardarlas.
/// - Mantiene una pequeña caché en memoria (`NSCache`) para visualización fluida.
@Observable
final class ReferenceStore {
    static let shared = ReferenceStore()

    private var accountId: String?
    private let imageCache = NSCache<NSString, UIImage>()

    private init() {
        imageCache.countLimit = 60
    }

    // MARK: - Cuenta

    /// Abre la carpeta de referencias para la cuenta indicada.
    func open(accountId: String) {
        guard self.accountId != accountId else { return }
        self.accountId = accountId
        imageCache.removeAllObjects()
    }

    /// Cierra la cuenta y limpia la caché en memoria.
    func close() {
        accountId = nil
        imageCache.removeAllObjects()
    }

    // MARK: - Operaciones locales

    /// Agrega una imagen de referencia a un dueño activo.
    ///
    /// 1. Fuera del hilo principal:
    ///    - Reduce con ImageIO (`kCGImageSourceThumbnailMaxPixelSize: 1600`, respetando orientación).
    ///    - Codifica JPEG calidad 0.7; si pasa de 2 MB, reduce calidad en pasos hasta que quepa.
    ///    - Calcula medidas (width, height, sizeBytes) y huella SHA-256 en hex.
    /// 2. Guarda el archivo en disco con protección de archivo.
    /// 3. Registra la referencia en `LocalStore.shared.mutate { try $0.addReference(...) }`.
    /// 4. Si la regla falla, borra el archivo guardado y relanza el error.
    func add(imageData: Data, to owner: ReferenceOwner) async throws -> ReferenceImage {
        guard accountId != nil else {
            throw DomainError.invalidValue(detail: "No hay una cuenta activa para guardar referencias.")
        }
        guard let dir = referencesDirectoryURL else {
            throw DomainError.invalidValue(detail: "No se pudo acceder a la carpeta de referencias.")
        }

        // Procesa la imagen fuera del hilo principal
        let processed = try await Task.detached(priority: .userInitiated) {
            try Self.processImage(data: imageData)
        }.value

        let id = UUID().uuidString.lowercased()
        let fileURL = dir.appendingPathComponent("\(id).jpg")

        // Guarda el archivo con protección
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try processed.data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            throw DomainError.invalidValue(detail: "No se pudo guardar la imagen en el dispositivo.")
        }

        let refImage = ReferenceImage(
            id: id,
            contentType: "image/jpeg",
            sizeBytes: processed.data.count,
            width: processed.width,
            height: processed.height,
            sha256: processed.sha256,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Registra en LocalStore
        do {
            let saved = try LocalStore.shared.mutate { data, ctx -> ReferenceImage in
                try data.addReference(refImage, to: owner, ctx)
                return data.references.first(where: { $0.id == id }) ?? refImage
            }
            if let image = UIImage(data: processed.data) {
                imageCache.setObject(image, forKey: id as NSString)
            }
            return saved
        } catch {
            // Si la regla falla, borra el archivo y relanza
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    /// Quita la referencia del dueño y borra el archivo del teléfono.
    func remove(_ id: String, from owner: ReferenceOwner) throws {
        try LocalStore.shared.mutate { data, ctx in
            try data.removeReference(id, from: owner, ctx)
        }
        deleteLocalFile(for: id)
    }

    /// Imagen en memoria o leída de disco, si existe.
    func image(for id: String) -> UIImage? {
        if let cached = imageCache.object(forKey: id as NSString) {
            return cached
        }
        guard let url = fileURL(for: id),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        imageCache.setObject(img, forKey: id as NSString)
        return img
    }

    /// URL del archivo local si existe en disco (.jpg o .heic).
    func fileURL(for id: String) -> URL? {
        guard let dir = referencesDirectoryURL else { return nil }
        let jpgURL = dir.appendingPathComponent("\(id).jpg")
        if FileManager.default.fileExists(atPath: jpgURL.path) {
            return jpgURL
        }
        let heicURL = dir.appendingPathComponent("\(id).heic")
        if FileManager.default.fileExists(atPath: heicURL.path) {
            return heicURL
        }
        return nil
    }

    /// Indica si el archivo ya está descargado en el teléfono.
    func hasLocalFile(_ id: String) -> Bool {
        fileURL(for: id) != nil
    }

    /// Guarda bytes descargados del respaldo en el disco local y actualiza la caché.
    func saveDownloaded(id: String, data: Data, contentType: String) throws {
        guard let dir = referencesDirectoryURL else {
            throw DomainError.invalidValue(detail: "No hay una cuenta activa.")
        }
        deleteLocalFile(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = contentType == "image/heic" ? "heic" : "jpg"
        let url = dir.appendingPathComponent("\(id).\(ext)")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let img = UIImage(data: data) {
            imageCache.setObject(img, forKey: id as NSString)
        }
    }

    /// Borra el archivo local si existe (por ejemplo al borrar una referencia).
    func deleteLocalFile(for id: String) {
        guard let dir = referencesDirectoryURL else { return }
        let jpgURL = dir.appendingPathComponent("\(id).jpg")
        let heicURL = dir.appendingPathComponent("\(id).heic")
        try? FileManager.default.removeItem(at: jpgURL)
        try? FileManager.default.removeItem(at: heicURL)
        imageCache.removeObject(forKey: id as NSString)
    }

    /// Borra todas las imágenes de la cuenta abierta (al borrar todos los datos).
    func deleteAllLocalFiles() {
        if let dir = referencesDirectoryURL {
            try? FileManager.default.removeItem(at: dir)
        }
        imageCache.removeAllObjects()
    }

    // MARK: - Privados

    private var referencesDirectoryURL: URL? {
        guard let accountId,
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Kitchen", isDirectory: true)
            .appendingPathComponent(accountId, isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
    }

    private struct ProcessedImage: Sendable {
        let data: Data
        let width: Int
        let height: Int
        let sha256: String
    }

    private nonisolated static func processImage(data: Data) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw DomainError.invalidValue(detail: "El archivo no es una imagen válida.")
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DomainError.invalidValue(detail: "No se pudo procesar la imagen.")
        }

        let width = thumbnail.width
        let height = thumbnail.height
        let maxSizeBytes = 2 * 1024 * 1024

        var quality: Double = 0.7
        var compressed = encodeJPEG(cgImage: thumbnail, quality: quality)

        while let current = compressed, current.count > maxSizeBytes, quality > 0.15 {
            quality -= 0.1
            compressed = encodeJPEG(cgImage: thumbnail, quality: max(quality, 0.05))
        }

        guard let finalData = compressed, finalData.count <= maxSizeBytes else {
            throw DomainError.invalidValue(detail: "La imagen es demasiado pesada y no se pudo reducir a menos de 2 MB.")
        }

        let digest = SHA256.hash(data: finalData)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()

        return ProcessedImage(data: finalData, width: width, height: height, sha256: sha256)
    }

    private nonisolated static func encodeJPEG(cgImage: CGImage, quality: Double) -> Data? {
        guard let cfData = CFDataCreateMutable(kCFAllocatorDefault, 0) else { return nil }
        guard let destination = CGImageDestinationCreateWithData(
            cfData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return cfData as Data
    }
}
