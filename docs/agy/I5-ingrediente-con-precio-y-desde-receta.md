Bloques I5a e I5b. I5a va primero; I5b usa el parámetro `initialName` que agrega I5a, así que espera a que I5a esté auditado.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I5a de AyeKitchen iOS: precio y paquete al crear un ingrediente.** Relee "Reglas de iOS" en `GEMINI.md` y la sección `/presentations` de `docs/api-contract.md`.

**Contexto.** Hoy "Nuevo ingrediente" (`Features/Catalog/IngredientFormView.swift`) solo guarda nombre, cómo se compra, grupo, notas y equivalencias. El precio y la cantidad del paquete viven en una marca (`Presentation`), que solo se crea después, desde el detalle del ingrediente, con "Agregar marca" (`BrandFormView`). La usuaria no encuentra dónde poner el precio. El contrato ya permite crear la marca con su primer precio en una sola llamada: `POST /presentations/` con `ingredient_id`, `brand` (obligatorio, de 1 a 100 caracteres), `package_quantity` (> 0), `package_unit_id` opcional y `price_cents` opcional.

**Alcance: solo `ios/aye-kitchen/aye-kitchen/Features/Catalog/IngredientFormView.swift`.** De `BrandFormView.swift` solo puedes leer y reutilizar, sin modificarlos, `PresentationCreateRequest` (línea 54), `BrandFormModel.parsePriceCents` (línea 302) y el aspecto de `packageSizeField`, `quantityInput`, `unitMenu` y `priceField` (desde la línea 457). Copia el aspecto de esas subvistas y no extraigas nada de `BrandFormView.swift`.

1. **Sección nueva "¿Cuánto te costó?", solo en modo `.create`.** Va entre la primera sección y "Equivalencias". Pie de sección: "Opcional. Puedes agregar más marcas después." Tiene tres campos, igual que en `BrandFormView`:
   - "Marca", texto libre, con el ejemplo "Ej. Selecta, Lala…".
   - "Tamaño del paquete", con la cantidad (teclado decimal) y un menú de unidad. El menú muestra solo las unidades de `allUnits` cuya `baseUnit` es la del ingrediente. Por defecto se elige la de `factorToBase` "1". Si la usuaria cambia "¿Cómo lo compras?", la unidad elegida se cambia a la de factor 1 del nuevo tipo.
   - "Precio", con teclado decimal y el símbolo "$" adelante.
   En modo `.edit` la sección no aparece; el precio se edita en Marcas, como hoy.
2. **Cuándo se crea la marca.** Si "Precio" está vacío, no se crea marca y el guardado funciona exactamente como hoy. Si tiene algo:
   - Debe ser válido con `parsePriceCents`, y la cantidad del paquete debe ser válida con `Quantity.parse` y mayor que cero. Si no, marca el campo en rojo, como las equivalencias inválidas, muestra "Revisa el precio y el tamaño del paquete." y no mandes nada.
   - Si "Marca" está vacía, se manda "Sin marca". No inventes ningún otro dato.
3. **Orden de las llamadas.** Primero `POST /ingredients/`, como hoy. Con el ingrediente creado, `POST /presentations/` con su id, la marca, `supplier_id` nulo, la cantidad, el id de la unidad elegida y el precio en centavos. Si la segunda llamada falla, el ingrediente ya existe. En ese caso, llama `onSave` con el ingrediente, no cierres el formulario y muestra en `errorMessage`: "Guardamos el ingrediente, pero no el precio. Agrégalo desde Marcas en el ingrediente." Mientras se ve ese mensaje, el botón Guardar dice "Listo" y solo cierra la hoja, para que no se vuelva a crear el ingrediente. En modo mock no hay red: devuelve el ingrediente como hoy.
4. **Nombre inicial.** Agrega a `IngredientFormView` un parámetro opcional `initialName: String = ""` que, solo en `.create`, llena el campo Nombre. Lo usará I5b. Las llamadas existentes en `CatalogView.swift` e `IngredientDetailView.swift` siguen compilando sin cambios.
5. Previews: el de "Nuevo ingrediente" muestra la sección nueva con las unidades de prueba que ya existen.

**Criterios de aceptación.**
1. Al crear "Mantequilla" (Peso) con Marca "Lala", paquete 1 kg y precio 95.50, el detalle del ingrediente muestra una marca "Lala" de 1,000 g a $95.50.
2. Al crear un ingrediente sin precio, se hace una sola llamada y no aparece ninguna marca, igual que hoy.
3. Con precio y Marca vacía, se crea la marca "Sin marca".
4. Con precio "abc" o con paquete 0, no se hace ninguna llamada y los campos quedan marcados.
5. Al editar un ingrediente no aparece la sección.
6. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra `IngredientFormView.swift`.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`

---

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I5b de AyeKitchen iOS: crear un ingrediente desde el selector de la receta.** I5a ya está hecho: `IngredientFormView(mode: .create, initialName:, onSave:)` crea el ingrediente y, opcionalmente, su marca con precio. Relee "Reglas de iOS" en `GEMINI.md`.

**Contexto.** Al editar una receta, "Agregar a la receta" abre `RecipeItemPicker` (`Features/Recipes/RecipeItemPicker.swift`). En la pestaña "Ingredientes" solo se puede elegir un ingrediente que ya existe. Al tocar uno, `selectedTarget = .ingredient(ingredient)` abre `RecipeLineSheet` (línea 64) para poner la cantidad. Si el ingrediente no existe, la usuaria tiene que salir de la receta e ir al Catálogo.

**Alcance: solo `Features/Recipes/RecipeItemPicker.swift` y `Features/Recipes/RecipeItemPickerModel.swift`.** Usa `IngredientFormView` sin modificarlo.

1. **Botón "Nuevo ingrediente".** En la pestaña Ingredientes, como primera fila de la lista y siempre visible (con resultados, sin resultados y con búsqueda), pon un botón con `plus.circle.fill` y el texto "Nuevo ingrediente". Si hay texto en la búsqueda, el texto es "Crear “<búsqueda>”". Con el texto vacío de "No se encontraron ingredientes." también se ve el botón. Usa el mismo estilo de "Agregar marca" en `Features/Catalog/IngredientBrandsSection.swift` (línea 114).
2. **Al tocarlo,** abre como hoja `IngredientFormView(mode: .create, initialName: <búsqueda sin espacios>)`.
3. **Al guardar.** En `onSave`, agrega el ingrediente al principio de `model.ingredients` con un método nuevo del modelo que no duplique por id. Guarda el ingrediente en un estado pendiente. Cuando se cierre la hoja del formulario, usa su `onDismiss` para pasar ese pendiente a `selectedTarget = .ingredient(...)` y limpiarlo. Así se abre `RecipeLineSheet` para poner la cantidad y el flujo sigue igual que al elegir uno existente. No presentes dos hojas al mismo tiempo. Si la usuaria cancela el formulario, no pasa nada.
4. En la pestaña "Mis recetas" no cambia nada.

**Criterios de aceptación.**
1. En el editor de una receta busco "Cajeta", toco "Crear “Cajeta”" y el formulario abre con Nombre "Cajeta". Lo guardo con precio, se abre la hoja de cantidad de Cajeta, pongo 200 g y la línea aparece en la receta con su costo.
2. Si cancelo el formulario, sigo en el selector sin cambios.
3. El ingrediente nuevo aparece en el Catálogo.
4. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los dos archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
