Bloque I26. Rama `local-first`. Va después de B12 y K4. Después va I27 (pantallas).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I26 de AyeKitchen iOS: guardar, comprimir y respaldar las imágenes de referencia en el teléfono.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (regla 12: **no compiles la app**). Lee la sección "Referencias" de `docs/backup-format.md`, "Imágenes de referencia (B12)" de `docs/api-contract.md`, `ios/KitchenKit/Sources/KitchenDomain/Rules/ReferenceRules.swift` (K4) y los comentarios de `Core/Local/LocalStore.swift` y `Core/Local/BackupService.swift`.

**Contexto.** Las imágenes de referencia son opcionales y de apoyo. Este bloque hace la parte sin pantallas: comprimirlas, guardar sus bytes como archivos de la cuenta, registrarlas con las reglas de K4, y subirlas y bajarlas con el respaldo. Las pantallas son el bloque I27.

**Excepción a la regla 1 de iOS:** en este bloque **sí** puedes crear y modificar archivos en `Core/Local/` (es parte del núcleo local). Nada más de `Core/`.

**Alcance:**
- `ios/aye-kitchen/aye-kitchen/Core/Local/ReferenceStore.swift` (nuevo)
- `ios/aye-kitchen/aye-kitchen/Core/Local/BackupService.swift` (agregar la sincronización de imágenes)
- `ios/aye-kitchen/aye-kitchen/Core/Local/LocalBootstrap.swift` (solo si hace falta bajar imágenes al restaurar)

1. **`ReferenceStore`** (`@Observable final class`, `static let shared`, MainActor por defecto como el resto):
   - Carpeta de la cuenta: `Application Support/Kitchen/<cuenta>/references/<id>.jpg` (o `.heic`), con protección de archivo como `LocalStore`. Se abre con la misma cuenta que `LocalStore` (llámalo desde donde `LocalStore` abre la cuenta, en `LocalBootstrap.prepare`).
   - `func add(imageData: Data, to owner: ReferenceOwner) async throws -> ReferenceImage`: fuera del hilo principal, reduce con ImageIO (`CGImageSourceCreateThumbnailAtIndex` con `kCGImageSourceThumbnailMaxPixelSize` 1600, respetando la orientación), codifica JPEG calidad 0.7, calcula SHA-256 (CryptoKit) y medidas; si pasa de 2 MB, baja la calidad hasta que quepa. Guarda el archivo y luego registra con `LocalStore.shared.mutate { try $0.addReference(image, to: owner, $1) }`. Si la regla falla, borra el archivo y relanza.
   - `func remove(_ id: String, from owner: ReferenceOwner) throws`: `removeReference` en el almacén y borra el archivo.
   - `func image(for id: String) -> UIImage?` y `func fileURL(for id: String) -> URL?`, con una caché en memoria pequeña (`NSCache`).
   - `func hasLocalFile(_ id: String) -> Bool`.
2. **Respaldo de imágenes** en `BackupService`:
   - `func syncReferences() async`: pide `GET /backup/references/`; sube (`PUT` con bytes crudos, `Content-Type` y `?sha256=`) las referencias activas que el servidor no tiene o tiene con otra huella; borra en el servidor (`DELETE`) las de `deletedReferenceIds()`; y baja las activas que faltan como archivo local. Una a la vez, sin detener todo si una falla. Para mandar y recibir bytes crudos agrega a `NetworkService` lo mínimo necesario **solo si** `requestRawJSON` no te sirve; en ese caso es la única línea de `Core/Network` que puedes tocar, y dilo en tu resumen.
   - Llama `syncReferences()` después de cada `backupNow()` exitoso y después de `restoreLatest()`.
3. Sin interfaz en este bloque.

**Criterios de aceptación** (Claude compila al auditar):
1. Agregar una referencia guarda el archivo, la registra en los datos y, tras el respaldo, aparece en `GET /backup/references/` con la misma huella.
2. Restaurar en un teléfono vacío baja las imágenes.
3. Quitar una referencia borra el archivo y, tras el respaldo, desaparece del servidor.
4. `git status` solo muestra tu alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo. **No reviertas cambios que veas en archivos fuera de tu alcance.**

### `FIN DEL PROMPT PARA GEMINI`
