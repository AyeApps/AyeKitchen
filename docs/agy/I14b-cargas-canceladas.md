Bloque I14b. Corre en paralelo con B10 e I14a (no comparten archivos). Claude ya dejó `Error.isCancellation` en `Core/Network/APIError.swift` y lo usa `Features/Catalog/IngredientBrandsSection.swift`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I14b de AyeKitchen iOS: una carga cancelada no es "sin internet".** Relee "Reglas de iOS" en `GEMINI.md` y el comentario de `isCancellation` en `Core/Network/APIError.swift`.

**Contexto.** Cuando una vista desaparece o se reconstruye a media carga, SwiftUI cancela su `.task` y con él la petición. iOS lo reporta como `URLError.cancelled` y la app lo muestra como "No pudimos conectarnos. Revisa tu internet…", aunque la red esté bien. Al tocar "Reintentar" carga a la primera. Ya pasó en las marcas del ingrediente (corregido por Claude en `IngredientBrandsSection.swift`, úsalo de referencia).

**Ya existe en `Core/`, úsalo y no lo cambies:** `error.isCancellation`, verdadero para `CancellationError`, `URLError.cancelled` y `APIError.network` con `.cancelled`.

**Alcance, solo los Model de pantallas con carga, en `ios/aye-kitchen/aye-kitchen/Features/`:**
- `Catalog/BrandDetailModel.swift`, `Catalog/CatalogModel.swift`, `Catalog/RecordPriceModel.swift`
- `Customers/CustomerDetailModel.swift`, `Customers/CustomersModel.swift`
- `Home/HomeModel.swift`
- `Orders/OrderDetailModel.swift`, `Orders/OrderFormModel.swift`, `Orders/OrdersModel.swift`, `Orders/RecipePickerModel.swift`
- `Recipes/BrandChoiceModel.swift`, `Recipes/RecipeDetailModel.swift`, `Recipes/RecipeEditorModel.swift`, `Recipes/RecipeItemPickerModel.swift`, `Recipes/RecipesModel.swift`

1. En cada función que **lee** datos (cargar, recargar, recargar en silencio, buscar, siguiente página, pedir el costo de una receta al agregarla a un pedido…), agrega antes del `catch` general un `catch where error.isCancellation` que:
   - no muestre error ni cambie a estado de error;
   - deje los datos que ya había;
   - quite el indicador de carga si la función lo había puesto;
   - en las recargas que devuelven `Bool` para el `ChangeTracker`, devuelva `false`.
2. Las funciones que **escriben** (guardar, borrar, pagar, cambiar margen, elegir marca…) no cambian: las lanza la usuaria con un botón y su error sí se muestra.
3. Si en alguna de estas pantallas la vista vuelve a pedir solo cuando el estado es "error" o "vacío", revisa que después de una cancelación la siguiente aparición sí vuelva a pedir (como en `IngredientBrandsSection`). Si para eso hace falta tocar la View, detente y pregunta.

**Criterios de aceptación.**
1. `grep -n "isCancellation"` encuentra el manejo en cada función de lectura de los archivos del alcance.
2. Ninguna función de escritura cambió.
3. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
