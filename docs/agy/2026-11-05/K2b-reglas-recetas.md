Bloque K2b. Corre en paralelo con K2a y K2c (cada uno en sus propios archivos). Claude ya dejó en `ios/KitchenKit/Sources/KitchenDomain/`: `DomainError` con todos los códigos del contrato, `Rules/MutationContext.swift` (la convención de las reglas está en su comentario) y `Rules/SoftDelete.swift`. El costeo ya está en `Costing/` (K1).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque K2b de AyeKitchen: las reglas de recetas y versiones de costeo en Swift.** Lee el comentario de `Rules/MutationContext.swift`, `Rules/SoftDelete.swift`, `Costing/DomainError.swift`, y en `docs/api-contract.md` la sección `/recipes` completa (incluidas "Versiones de costeo (B6b)" y los códigos `RECIPE_CYCLE` y `RECIPE_TOO_DEEP`). La referencia exacta del comportamiento es el backend: `backend/app/services/recipe_service.py`, `cost_version_service.py` y sus pruebas `backend/app/tests/test_recipes.py` y `test_cost_versions.py`. Léelos, no los modifiques.

**Contexto.** La app pasa a guardar y calcular todo en el teléfono, sobre `KitchenData`. Este bloque traduce a Swift lo que hoy hace el servidor con recetas y versiones: mismas validaciones, mismos códigos y mismos textos de `detail`.

**Ya existe, no lo cambies:** todo lo que hay en `Sources/KitchenDomain/`. Para costos usa `CostingIndex` / `KitchenData.calculateRecipeCost` y `compareVersions` de `Costing/`; para validar que una línea es convertible usa las conversiones de `CostingIndex`. No las dupliques.

**Alcance, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Rules/RecipeRules.swift` (nuevo): escrituras de recetas y versiones.
- `Sources/KitchenDomain/Rules/RecipeQueries.swift` (nuevo): lecturas.
- `Tests/KitchenDomainTests/RecipeRulesTests.swift` (nuevo).

1. **Escrituras** (métodos `mutating` de `KitchenData` con `MutationContext`):
   - Recetas: crear, editar (parcial; `items` y `extraCosts` reemplazan la lista) y borrar, con las validaciones de `validate_recipe_items_and_yield` en el mismo orden (referencias, `pinned_presentation_id` solo en ingredientes y de ese ingrediente, cantidades > 0, convertibilidad, rendimiento), ciclos (`recipeCycle`) y profundidad máxima de 10 niveles contando hacia arriba (`recipeTooDeep`), nombre repetido (`duplicateName`), borrar una receta usada como subreceta en otra activa (`inUse`). Al editar `items`, quita de sus versiones activas las elecciones de ingredientes que ya no están; al borrar la receta, borra sus versiones.
   - Versiones: crear, editar (parcial; `choices` reemplaza), borrar, con las reglas de B6b y B6b.1 (nombre recortado, "Base" reservado, repetido en la misma receta, ingrediente que no está en la receta o repetido, marca de otro ingrediente con el texto "Esa marca no es de <nombre>").
2. **Lecturas** (no `mutating`, con `now: Date`):
   - Lista de recetas activas con búsqueda opcional por nombre, ordenadas por nombre, cada una con `batch_cost_cents` y `complete` del costeo (una receta cuyo costeo lanza sale con costo nulo y `complete` falso, como el backend).
   - Recetas que se pueden usar como subreceta de una (`usable-as-subrecipe`): sin ciclos.
   - Versiones activas de una receta por `createdAt`.
   Define las estructuras de resultado que necesites en `RecipeQueries.swift`, con nombres que empiecen por `Recipe` para no chocar con otros bloques.
3. **Pruebas** en `RecipeRulesTests.swift` (Swift Testing, con `MutationContext` de hora e ids fijos): traduce los casos de `test_recipes.py` y `test_cost_versions.py` que apliquen (aislamiento entre usuarios no aplica), y además: un ciclo directo y uno indirecto; una cadena de 11 niveles; una operación que lanza deja `KitchenData` igual que antes.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las de hoy y las tuyas) sin advertencias nuevas.
2. `git status` solo muestra los tres archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. Las ayudas privadas que necesites van como `private`/`fileprivate` dentro de tus archivos (otros bloques trabajan al mismo tiempo en el mismo paquete). No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
