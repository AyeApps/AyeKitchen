Bloque K3. Rama `local-first`. Corre en paralelo con I23. I21 (Ajustes) e I22 (Finanzas) esperan a este bloque.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque K3 de AyeKitchen: ajustes del negocio, tablero de costos de recetas y categorías de gasto, en KitchenKit.** Trabaja en la rama `local-first`. Lee el comentario de `ios/KitchenKit/Sources/KitchenDomain/Rules/MutationContext.swift`, `Rules/SoftDelete.swift`, `Costing/DomainError.swift`, `KitchenSettings` en `Entities.swift`, y como estilo `Rules/RecipeQueries.swift` y `Rules/ExpenseRules.swift`.

**Contexto.** La app va a tener una pantalla de Ajustes (nombre del negocio, margen por defecto, días para que un precio sea viejo, moneda) y una pestaña de Finanzas con un tablero de costos de todas las recetas. Este bloque agrega a KitchenKit lo que esas pantallas necesitan; las pantallas son otros bloques.

**Ya existe, no lo cambies:** todo lo que hay en `Sources/KitchenDomain/` fuera de tus archivos nuevos. Para costos usa `KitchenData.calculateRecipeCost` / `CostingIndex`; no lo dupliques.

**Alcance, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Rules/SettingsRules.swift` (nuevo)
- `Sources/KitchenDomain/Rules/CostDashboardQueries.swift` (nuevo)
- `Tests/KitchenDomainTests/SettingsAndDashboardTests.swift` (nuevo)

1. **Ajustes:** un `mutating func updateSettings` con cambios parciales (como los `*UpdateDraft` de otros archivos) para `name` (recortado, de 1 a 80 caracteres), `defaultMarginPercent` (0 a 1000), `priceStaleDays` (1 a 3650) y `currency` (3 letras mayúsculas). Fuera de rango o vacío → `invalidValue` con un texto en palabras de la cocina ("El margen va de 0 % a 1000 %"). Si lanza, nada cambia.
2. **Tablero de costos de recetas:** una consulta con `now: Date` que, para cada receta activa, dé: id y nombre, rendimiento (cantidad y unidad), porciones, costo de tanda, costo por unidad de rendimiento (centavos, redondeado una vez) y por porción, margen efectivo, precio sugerido por tanda y por unidad, ganancia sugerida por tanda (precio sugerido − costo, en centavos), `complete` y `hasStalePrices`. Una receta cuyo costeo lanza aparece con costos nulos y `complete` falso (como la lista de recetas). Orden configurable con un enum: por nombre, por costo de tanda (mayor primero), por ganancia sugerida (mayor primero) y "por revisar" (primero las incompletas, luego las de precios viejos, luego por nombre). Además, totales del tablero: cuántas recetas, cuántas incompletas y cuántas con precios viejos. Nombres de tipos que empiecen por `CostDashboard`.
3. **Categorías de gasto:** una consulta que devuelva las categorías distintas de los gastos activos (sin vacías), ordenadas por cuántas veces se usaron y luego por nombre, para sugerirlas al capturar un gasto.
4. **Pruebas** con `MutationContext` de hora e ids fijos: rangos de ajustes y que un error no cambia nada; el tablero con el ejemplo de B7 (receta de 12 pz, tanda de $120 de costo, margen 30: costo por pieza 1000, precio por pieza 1300, ganancia por tanda 3600); una receta sin precio sale incompleta y primero en "por revisar"; cambiar `defaultMarginPercent` cambia el precio sugerido de una receta sin margen propio; las categorías salen sin repetir y en el orden pedido.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las 81 de hoy y las tuyas) sin advertencias nuevas.
2. `git status` solo muestra los tres archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. Las ayudas privadas van como `private`/`fileprivate` en tus archivos. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Orders/`.

### `FIN DEL PROMPT PARA GEMINI`
