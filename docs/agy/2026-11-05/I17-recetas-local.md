Bloque I17. Rama `local-first`. Va después de I16 e I18 (ya hechos). Después van I19 (Inicio) e I20 (respaldo y limpieza).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I17 de AyeKitchen iOS: Recetas con datos locales.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` y sigue **todas** las reglas de `docs/agy/_pantallas-locales.md`. Las reglas y consultas están en `ios/KitchenKit/Sources/KitchenDomain/Rules/RecipeRules.swift` y `RecipeQueries.swift`; el costeo, la comparación de versiones y las conversiones en `Costing/` (`KitchenData.calculateRecipeCost`, `compareVersions`, `CostingIndex`). Catálogo, Pedidos y Clientes ya son locales: úsalos como referencia de estilo (`Features/Catalog/`, `Features/Orders/`).

**Contexto.** La app ya no le pide recetas ni costos al servidor: los lee, los calcula y los guarda en el teléfono con `LocalStore`. Este bloque cambia todas las pantallas de Recetas, sin cambiar lo que la usuaria ve ni los textos. Cambiar de versión o de marca ahora es instantáneo: ya no hay espera ni indicador de carga para el costo.

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/Recipes/`:** todos sus archivos (`RecipesView`, `RecipesModel`, `RecipeDetailView`, `RecipeDetailModel`, `RecipeEditorView`, `RecipeEditorModel`, `RecipeLineSheet`, `RecipeLineModel`, `RecipeItemPicker`, `RecipeItemPickerModel`, `AddExtraCostSheet`, `BrandChoiceSheet`, `BrandChoiceModel`, `CostVersionNameSheet`, `RecipeMockData`). Y, por la regla 4 de `_pantallas-locales.md`, las llamadas de una línea a tus vistas desde `Features/Home/`.

1. **Lista de recetas:** búsqueda, costo de tanda y "Falta precio" por receta (de `listRecipes`), borrar con el aviso de `IN_USE`. Calcula los costos una vez por `LocalStore.shared.revision`, no en cada dibujo.
2. **Detalle de la receta:** título nativo, rendimiento, tarjeta de costo ("Te cuesta", "Te sugerimos cobrar", margen editable con el selector de hoy), avisos de precios faltantes y viejos, desglose de líneas, selector de versiones con sus costos ("Base", versiones, "Nueva versión"), elegir marca de una línea (en la base fija la marca en la receta; en una versión cambia la elección de la versión; "Como en la base"), crear, renombrar y borrar versiones. Todo con las reglas y el costeo de KitchenKit; cambiar de versión recalcula al instante.
3. **Editor de receta** (crear y editar): nombre, descripción, rendimiento, porciones, líneas de ingrediente y subreceta con su unidad y marca fijada, costos fijos, con los errores `UNIT_NOT_CONVERTIBLE` (incluida la pregunta de equivalencia de hoy), `RECIPE_CYCLE`, `RECIPE_TOO_DEEP` y `DUPLICATE_NAME` con los textos de hoy.
4. **Selector de ingrediente o subreceta:** búsqueda en ingredientes y recetas locales (subrecetas sin ciclos, de `usableSubrecipes`). **Restaura** el flujo de crear un ingrediente desde el selector: `IngredientFormView(mode: .create, initialName:, onSave:)` ya existe; al guardar, el ingrediente nuevo queda elegido para la línea como antes (en I16 la llamada perdió el `onSave`).
5. **Navegación por id:** `RecipeDetailView(recipeId:)` (ya lo es), `RecipeEditorView` con `.create` / `.edit(recipeId:)`. Las líneas abren `IngredientDetailView(ingredientId:)` y `BrandDetailView(presentationId:)` del catálogo. Ajusta las llamadas de `Features/Home/` a tus firmas, una línea cada una.

**Criterios de aceptación.**
1. En `Features/Recipes/` no queda ningún `NetworkService`, `requestCaching`, `cached`, `ChangeTracker` ni tipo `Remote…`, y `RecipeMockData.swift` ya no existe (los previews usan `LocalStore.preview()`).
2. Con los datos de ejemplo, el Pastel muestra Base y "Con Tres Estrellas" con costos distintos, y cambiar entre ellas no muestra ningún indicador de carga.
3. En el simulador sin red: crear una receta con una subreceta, crear un ingrediente desde el selector y que quede elegido, agregar una versión, elegirle otra marca y borrarla, funcionan.
4. Build sin advertencias nuevas; `git status` solo muestra tu alcance (y las líneas de llamada ajustadas).

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance.**

### `FIN DEL PROMPT PARA GEMINI`
