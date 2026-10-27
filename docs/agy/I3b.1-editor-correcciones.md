### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I3b.1 de AyeKitchen iOS: correcciones al editor de recetas y enlaces del desglose.** El bloque I3b ya está hecho; la auditoría encontró un error que puede borrar datos y dos cosas más. Relee "Reglas de iOS" en `GEMINI.md` (reglas 3, 4 y 5).

**Alcance: solo la carpeta `ios/aye-kitchen/aye-kitchen/Features/Recipes/`.** Para el punto 3 puedes usar sin modificarlos `BrandDetailView(presentation:onBrandChangedOrDeleted:)` e `IngredientDetailView(ingredient:onUpdate:onDelete:)` de `Features/Catalog/`. Otros agentes trabajan al mismo tiempo en `Features/Catalog/` y `Features/Home/`: no toques esas carpetas.

1. **Error grave: datos inventados cuando falla la red.** En `RecipeEditorView.swift`, `openLineForEditing` (líneas 310 a 352) pide el ingrediente o la receta de la línea y, si la petición falla, abre la hoja con un `Ingredient` inventado (unidad base g y sin equivalencias) o una subreceta inventada (rinde en pz). Con ese ingrediente inventado, si la usuaria responde la pregunta de equivalencia, `saveLine` en `RecipeLineModel.swift` (línea 400) manda `PATCH /ingredients/{id}` con la lista de equivalencias del ingrediente inventado (vacía) más la nueva, y **borra las equivalencias reales del ingrediente**. Además, la hoja ofrecería unidades equivocadas para un ingrediente por volumen o por pieza. Corrígelo así: quita los dos fallbacks; si la petición falla, no abras la hoja y muestra el error en la alerta del editor ("No pudimos abrir este ingrediente. Revisa tu conexión e intenta de nuevo."). Mueve esa carga de `RecipeEditorView` a `RecipeEditorModel` (la vista no llama a la red). En ningún lugar de la carpeta se construye un `Ingredient`, `Recipe` o `Presentation` con datos inventados fuera de los previews.
2. **Unidades que no cargan.** En `RecipeEditorModel.loadInitialData` (líneas 279 a 310), si `GET /units/` falla el error se descarta y el editor queda sin unidades para elegir. Haz que el editor muestre `ErrorStateView` con reintento mientras no haya unidades cargadas. La búsqueda del nombre de la marca fijada (el `try?` de la línea 292) puede seguir siendo silenciosa: solo es un texto de apoyo.
3. **Tocar una línea de ingrediente en el desglose.** En `RecipeDetailView.swift` (líneas 284 a 289) solo las subrecetas navegan. Haz que una línea de ingrediente también navegue: si tiene `presentation_id`, carga `GET /presentations/{presentation_id}` y abre `BrandDetailView` con esa marca (para registrar su precio); si no tiene (falta precio porque no hay marcas), carga `GET /ingredients/{ref_id}` y abre `IngredientDetailView` (para agregar una marca). Al regresar, el desglose se recarga. La carga va en un `@Observable` model de esta carpeta; mientras carga, la fila muestra un `ProgressView` y, si falla, una alerta con el error. Las filas de costo fijo siguen sin navegar.

**Criterios de aceptación.**
1. Con el backend apagado, tocar una línea de ingrediente en el editor muestra la alerta y no abre la hoja; `grep` de `Ingredient(` y `Recipe(` fuera de bloques `#if DEBUG` en `Features/Recipes/` no encuentra nada.
2. Con el backend apagado al abrir el editor, se ve `ErrorStateView`; al encender el backend y reintentar, aparecen las unidades.
3. En el desglose, tocar una línea "Falta precio" con marca abre esa marca; tocar una sin marcas abre el ingrediente; registrar el precio y regresar actualiza el costo.
4. `RecipeEditorView.swift` ya no contiene `NetworkService`.
5. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra cambios dentro de `ios/aye-kitchen/aye-kitchen/Features/Recipes/`.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
