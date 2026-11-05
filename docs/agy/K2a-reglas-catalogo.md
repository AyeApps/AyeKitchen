Bloque K2a. Corre en paralelo con K2b y K2c (cada uno en sus propios archivos). Claude ya dejó en `ios/KitchenKit/Sources/KitchenDomain/`: `DomainError` con todos los códigos del contrato, `Rules/MutationContext.swift` (la convención de las reglas está en su comentario) y `Rules/SoftDelete.swift` (`isActive`, `active(_:)`, `activeIndex(of:)`).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque K2a de AyeKitchen: las reglas del catálogo en Swift (unidades, ingredientes, proveedores, marcas y precios).** Lee el comentario de `Rules/MutationContext.swift`, `Rules/SoftDelete.swift`, `Costing/DomainError.swift`, y en `docs/api-contract.md` las secciones `/units`, `/ingredients` (incluido "Resumen de marcas (B6a)"), `/suppliers` y `/presentations`. La referencia exacta del comportamiento es el backend: `backend/app/services/unit_service.py`, `ingredient_service.py`, `supplier_service.py`, `presentation_service.py` y sus pruebas `backend/app/tests/test_units.py`, `test_ingredients.py`, `test_suppliers.py`, `test_presentations.py`. Léelos, no los modifiques.

**Contexto.** La app pasa a guardar y calcular todo en el teléfono, sobre `KitchenData`. Este bloque traduce a Swift lo que hoy hace el servidor con el catálogo: mismas validaciones, mismos códigos de error y mismos textos de `detail`. Las unidades del sistema viven en `SystemUnits` (ids `sys.*`) y no se pueden editar ni borrar.

**Ya existe, no lo cambies:** todo lo que hay en `Sources/KitchenDomain/` (entidades, `KitchenData`, `SystemUnits`, `Costing/`, `Rules/MutationContext.swift`, `Rules/SoftDelete.swift`). Usa `CostingIndex` de `Costing/` para la marca vigente, el último precio, la conversión y los precios viejos; no lo dupliques.

**Alcance, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Rules/CatalogRules.swift` (nuevo): escrituras.
- `Sources/KitchenDomain/Rules/CatalogQueries.swift` (nuevo): lecturas.
- `Tests/KitchenDomainTests/CatalogRulesTests.swift` (nuevo).

1. **Escrituras** (métodos `mutating` de `KitchenData` con `MutationContext`, según la convención): unidades (crear, editar, borrar), ingredientes (crear con equivalencias, editar, borrar), proveedores (crear, editar, borrar), marcas (crear con `package_unit_id` opcional que convierte la cantidad a la base y con primer precio opcional; editar; borrar) y precios (agregar un registro con `recordedAt` opcional). Cada una con **todas** las validaciones del servicio equivalente y en el mismo orden: nombres repetidos sin distinguir mayúsculas entre activos (`duplicateName`), unidad del sistema (`systemUnitReadonly`), referencias que no existen o están borradas (`invalidReference`), las reglas de `IN_USE` del contrato (cambiar `base_unit` en uso, quitar una equivalencia que usa una receta activa, borrar un ingrediente usado en una receta activa, borrar una unidad usada, borrar una marca fijada en una receta activa), los efectos al borrar (borrar un ingrediente borra sus marcas; borrar un proveedor deja `supplierId` nulo en sus marcas; borrar una marca la quita de las elecciones de las versiones activas) y `package_quantity > 0`. Lo que en el backend da 422 estándar de Pydantic (nombre vacío, largo) aquí es `invalidValue` con un texto en palabras de la cocina.
2. **Lecturas** (métodos no `mutating` que reciben `now: Date`):
   - Unidades disponibles (sistema + negocio activas, orden por `base_unit` y luego factor).
   - Ingredientes activos con búsqueda opcional por nombre y filtro por grupo, ordenados por nombre, cada uno con su resumen de marcas (`brands_count` y marca vigente con `cost_per_base_unit`, como B6a).
   - Marcas de un ingrediente con lo que hoy trae `Presentation` en el contrato (último precio, `cost_per_base_unit`, `is_current`, `price_age_days`, `price_is_stale`, nombre de proveedor), en el orden del contrato.
   - Historial de precios de una marca.
   - "Precios por actualizar" (`/presentations/stale`) con `used_in_recipes`, en el orden del contrato.
   - Proveedores activos por nombre.
   Define las estructuras de resultado que necesites en `CatalogQueries.swift`, con nombres que empiecen por `Catalog` para no chocar con otros bloques.
3. **Pruebas** en `CatalogRulesTests.swift` (Swift Testing, con `MutationContext` de hora e ids fijos): traduce los casos de `test_units.py`, `test_ingredients.py`, `test_suppliers.py` y `test_presentations.py` que apliquen (todo lo de aislamiento entre usuarios no aplica: un archivo es un solo negocio), y además: una operación que lanza deja `KitchenData` igual que antes; borrar un ingrediente borra sus marcas; borrar una marca la quita de una versión.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las 16 pruebas de hoy y las tuyas) sin advertencias nuevas.
2. `git status` solo muestra los tres archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. Las ayudas privadas que necesites van como `private`/`fileprivate` dentro de tus archivos (otros bloques trabajan al mismo tiempo en el mismo paquete). No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
