Bloque K4. Rama `local-first`. Corre en paralelo con B12. Claude ya dejó en KitchenKit `ReferenceImage`, `KitchenData.references` y `referenceIds` en `Ingredient`, `Presentation`, `Recipe`, `Order` y `Expense` (ver "Referencias" en `docs/backup-format.md`).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque K4 de AyeKitchen: las reglas de las imágenes de referencia en KitchenKit.** Trabaja en la rama `local-first`. Lee la sección "Referencias" de `docs/backup-format.md`, el comentario de `ios/KitchenKit/Sources/KitchenDomain/Rules/MutationContext.swift`, `Rules/SoftDelete.swift`, `ReferenceImage` en `Entities.swift` y `KitchenData.swift`.

**Contexto.** Ingredientes, marcas, recetas, pedidos y gastos pueden tener hasta 5 imágenes de referencia opcionales. La app comprime la imagen y guarda sus bytes aparte; a KitchenKit solo le llegan sus datos (`ReferenceImage`). Este bloque agrega las reglas para agregarlas, quitarlas y consultarlas.

**Ya existe, no lo cambies:** todo lo que hay en `Sources/KitchenDomain/` fuera de tus archivos nuevos (las entidades ya tienen `referenceIds` y `KitchenData` ya tiene `references`).

**Alcance, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Rules/ReferenceRules.swift` (nuevo)
- `Tests/KitchenDomainTests/ReferenceRulesTests.swift` (nuevo)
- `Sources/KitchenDomain/SoftDelete` no; si necesitas que `ReferenceImage` sea `SoftDeletable`, agrega esa conformidad en tu archivo.

1. **Dueño de una referencia:** `public enum ReferenceOwner: Hashable, Sendable` con `ingredient(String)`, `presentation(String)`, `recipe(String)`, `order(String)`, `expense(String)`.
2. **Agregar:** `mutating func addReference(_ image: ReferenceImage, to owner: ReferenceOwner, _ ctx: MutationContext) throws` — el dueño debe existir y estar activo (`notFound` si no); máximo 5 referencias activas por dueño (`invalidValue` con "Puedes guardar hasta 5 referencias"); `image.id` no puede existir ya (`invalidValue`). Agrega la imagen a `references` (con `createdAt`/`updatedAt` de `ctx`) y su id al final de `referenceIds` del dueño (creando la lista si era nula); actualiza `updatedAt` del dueño.
3. **Quitar:** `mutating func removeReference(_ referenceId: String, from owner: ReferenceOwner, _ ctx: MutationContext) throws` — la quita de `referenceIds` (si queda vacía, `nil`) y marca la imagen con `deletedAt`. Si no está en ese dueño, `notFound`.
4. **Reordenar** (opcional pero útil): `mutating func moveReference(_ referenceId: String, in owner: ReferenceOwner, toIndex: Int, _ ctx: MutationContext) throws`.
5. **Consultas:** `func references(of owner: ReferenceOwner) -> [ReferenceImage]` (activas, en el orden de `referenceIds`); `func activeReferences() -> [ReferenceImage]`; `func deletedReferenceIds() -> [String]` (para que la app borre bytes y el respaldo los quite del servidor).
6. **Al borrar el dueño:** cuando un ingrediente, marca, receta, pedido o gasto queda borrado, sus referencias siguen existiendo pero ya no se consultan por ese dueño; no cambies las reglas existentes para esto.
7. **Pruebas** (`MutationContext` de hora e ids fijos): agregar a cada tipo de dueño; el sexto falla y no cambia nada; quitar deja `nil` cuando ya no hay; dueño inexistente o borrado; reordenar; `deletedReferenceIds`; ida y vuelta por `KitchenCoding` con referencias.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las 89 de hoy y las tuyas) sin advertencias nuevas.
2. `git status` solo muestra los dos archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No compiles la app de iOS. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `backend/`.

### `FIN DEL PROMPT PARA GEMINI`
