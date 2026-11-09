Bloque I25. Rama `local-first`. Corre en paralelo con I24 (no comparten archivos).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I25 de AyeKitchen iOS: consejos en contexto (TipKit) y pantallas vacías que guían.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (incluida la regla 12: **no compiles la app**) y las reglas de `docs/agy/_pantallas-locales.md`. Lee `ios/aye-kitchen/aye-kitchen/Core/Tips/KitchenTips.swift` (todos los consejos, sus textos ya aprobados y sus reglas) y `Core/Tips/FirstSteps.swift`.

**Contexto.** Para que la app no abrume, cada pantalla enseña lo suyo en el momento justo con un consejo de TipKit (uno por pantalla, sale una vez y no vuelve al cerrarlo), y cada lista vacía explica qué es y lleva a crear lo primero.

**Ya existe, úsalo y no lo cambies:** los `Tip` de `KitchenTips.swift`, `KitchenTips.requestResetOnNextLaunch()`, `FirstSteps.markFinanceVisited()`. TipKit ya se configura al arrancar.

**Alcance:** `Features/Catalog/` (`CatalogView`, `IngredientBrandsSection`), `Features/Recipes/` (`RecipeDetailView`, y su Model si hace falta para la regla), `Features/Orders/` (`OrderFormView`, y su Model si hace falta), `Features/Finance/FinanceView.swift`, `Features/Settings/SettingsView.swift`, y las vistas con lista vacía de esas carpetas. **No toques** `Features/Home/`.

1. **Colocar cada consejo** (en línea con `TipView(tip)` dentro de la lista, salvo que diga otra cosa):
   - `CatalogBrandsTip`: arriba de la lista del Catálogo.
   - `IngredientCurrentBrandTip`: arriba de las marcas del ingrediente; pon `IngredientCurrentBrandTip.ingredientHasBrands = true` cuando el ingrediente tiene al menos una marca.
   - `RecipeChangeBrandTip`: arriba del desglose "De dónde sale el costo".
   - `RecipeVersionsTip`: junto al selector de versiones (o como `.popoverTip` sobre "Nueva versión"/"Comparar con otras marcas"); pon `RecipeVersionsTip.recipeHasIngredientWithSeveralBrands = true` cuando algún ingrediente de la receta tiene 2 o más marcas activas.
   - `OrderSoldByTip`: arriba de la primera línea que tiene selector "Por pieza / Por tanda"; pon `OrderSoldByTip.hasRecipeYieldingSeveral = true` cuando hay una línea de una receta que rinde más de 1.
   - `FinanceExpensesTip`: arriba de la lista de gastos del mes.
   - `BackupTip`: en la fila de Respaldo de Ajustes (`.popoverTip` o en línea).
   Usa `.tipBackground` o estilos del sistema que respeten los tokens; nada de colores sueltos.
2. **Finanzas:** al aparecer `FinanceView`, llama `FirstSteps.markFinanceVisited()`.
3. **Ajustes:** una fila "Volver a ver los consejos" (en una sección "Ayuda") que llama `KitchenTips.requestResetOnNextLaunch()` y muestra "Los verás otra vez la próxima vez que abras la app."
4. **Pantallas vacías** (Catálogo, Recetas, Pedidos, Clientes, Proveedores, gastos de Finanzas, unidades propias): cada una con `ContentUnavailableView` que diga qué es en una frase y un botón principal para crear lo primero (el mismo que abre el "+" de esa pantalla). Conserva los textos que ya existen si son de este estilo; cambia solo los que no expliquen o no tengan botón.

**Criterios de aceptación** (Claude compila al auditar):
1. Cada consejo aparece una vez en su pantalla y no vuelve después de cerrarlo; los que tienen regla solo salen cuando se cumple.
2. Las listas vacías muestran explicación y botón para crear.
3. `git status` solo muestra tu alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Home/`.

### `FIN DEL PROMPT PARA GEMINI`
