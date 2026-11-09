Bloque I10. **Espera a que B6b esté auditado y desplegado.** Claude ya dejó en `Core/Models/Recipes.swift`: `CostVersion`, `CostVersionChoice`, `CostVersionComparison`, `BrandSource`, `RecipeCost.versionId/versionName` y `CostLine.brandSource`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I10 de AyeKitchen iOS: elegir la marca desde el costo y comparar versiones.** Relee "Reglas de iOS" en `GEMINI.md` y, en `docs/api-contract.md`, `GET /recipes/{id}/cost` y la sección "Versiones de costeo (B6b)".

**Contexto.** La receta dice "harina de trigo" y el costo usa una marca. La usuaria quiere, desde el costo de la receta, cambiar la marca de un ingrediente y comparar versiones ("Con Selecta", "Con Tres Estrellas") para ver cómo le pegan los precios, sin duplicar la receta. La versión "Base" es la receta tal cual.

**Ya existe en `Core/Models/Recipes.swift`, úsalo y no lo cambies:** `CostVersion`, `CostVersionChoice`, `CostVersionComparison`, `BrandSource`, `RecipeCost.versionId`, `RecipeCost.versionName` y `CostLine.brandSource`. Para las marcas de un ingrediente usa `GET /presentations/?ingredient_id=` con `Page<Presentation>`, como `RecipeLineSheet`.

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/Recipes/`:**
- `RecipeDetailModel.swift`
- `RecipeDetailView.swift`
- `BrandChoiceSheet.swift` (nuevo)
- `CostVersionNameSheet.swift` (nuevo)

1. **Selector de versión** arriba de la tarjeta de costo, en `RecipeDetailView`. Al cargar, el modelo pide además `GET /recipes/{id}/versions/compare` y `GET /recipes/{id}/versions/`. Si solo existe la base, se muestra un botón secundario "Comparar con otras marcas" que abre `CostVersionNameSheet`. Si hay versiones, una fila horizontal con desplazamiento con un `Chip` por fila de la comparación: nombre y `batchCostCents` con `Money.format`, la elegida resaltada, y al final un chip "Nueva versión". Al tocar una, el modelo pide `/recipes/{id}/cost?version_id=` (sin parámetro para la base) y la tarjeta y el desglose muestran esa versión. Con letra de accesibilidad, los chips van uno debajo del otro.
2. **Elegir marca de una línea.** Tocar una línea de ingrediente del desglose ya no abre la marca: abre `BrandChoiceSheet` con las marcas de ese ingrediente. Cada fila: marca y tienda, precio del paquete, el precio de `Money.formatPerUnit` y una palomita en la que usa la línea ahora. La primera fila es "La que usamos por defecto", que quita la elección. Abajo, un enlace "Ver marcas del ingrediente" que hace lo que hace hoy `openIngredientLine`. Si no hay marcas, el mensaje "Todavía no tiene marcas. Agrégalas en Catálogo." y el mismo enlace.
3. **Qué guarda elegir una marca.**
   - En una versión: `PATCH /recipes/{id}/versions/{version_id}` con la lista completa de `choices` de esa versión, cambiando o quitando la de ese ingrediente. Luego recarga el costo de esa versión y la comparación.
   - En la base: `PATCH /recipes/{id}` con `items`, la lista completa de la receta igual que hoy, cambiando solo `pinned_presentation_id` de las líneas de ese ingrediente (nulo para "La que usamos por defecto"). Antes de guardar, la hoja avisa: "Esto cambia la marca de la receta." Luego recarga receta, costo y comparación.
4. **Etiqueta en la línea.** En `CostLineRow`, si `brandSource` es `.version` muestra un `Chip("Esta versión", tone: .inProgress)`, si es `.recipe` un `Chip("Fijada")`. Nulo o `.current`, nada nuevo.
5. **Crear, renombrar y borrar versiones.** `CostVersionNameSheet` pide el nombre ("Ej. Con Selecta") y hace `POST /recipes/{id}/versions/` con `choices` vacío; al guardar, la nueva queda elegida. Con una versión elegida, un menú en la toolbar con "Cambiar nombre" (`PATCH` solo con `name`) y "Borrar versión" (`DELETE`, con confirmación "¿Borrar la versión X? La receta no cambia."), que regresa a la base. `DUPLICATE_NAME` se muestra como "Ya tienes una versión con ese nombre".
6. **Modelo.** Todo lo de red va en `RecipeDetailModel`, con la versión elegida, la comparación y las versiones en su estado. Si la comparación falla, el detalle se sigue viendo sin el selector. Los structs de petición nuevos van en el archivo que los usa, `nonisolated` y `Sendable`.
7. Previews de `BrandChoiceSheet` y `CostVersionNameSheet` con datos de prueba, en tamaño normal y en `.accessibility3`, y uno del detalle con dos versiones.

**Criterios de aceptación.**
1. Con una receta de harina 300 g y dos marcas ($23.50 y $30.00 el kg), crear "Con Tres Estrellas" y elegirle la de $30.00 muestra $9.00 en esa versión y $7.05 en "Base", y los chips muestran los dos costos.
2. Elegir marca en la base cambia `pinned_presentation_id` de la receta y la línea muestra "Fijada".
3. Borrar la versión regresa a la base sin cambiar la receta.
4. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
