Bloque I9. Corre en paralelo con B6a y B6b. Claude ya dejó en `Core/`: `Ingredient.brandsCount` y `Ingredient.currentBrand` (B6a, opcionales) y `Money.formatPerUnit`. Con un servidor sin B6a los campos llegan nulos y la pantalla debe verse como hoy.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I9 de AyeKitchen iOS: que se entienda que el ingrediente es general y las marcas van adentro.** Relee "Reglas de iOS" en `GEMINI.md` y el párrafo "Resumen de marcas (B6a)" de `/ingredients` en `docs/api-contract.md`.

**Contexto.** Un ingrediente ("Harina de trigo") es general; cada marca que compras (Selecta, Tres Estrellas) vive dentro de él con su tamaño y su precio, y la receta solo dice "harina de trigo". Hoy la app no lo deja ver: el catálogo solo muestra nombres y al crear un ingrediente la marca parece parte de él.

**Ya existe en `Core/`, úsalo y no lo cambies:** `Ingredient.brandsCount: Int?`, `Ingredient.currentBrand: IngredientCurrentBrand?` (con `brand`, `supplierName` y `costPerBaseUnit`) y `Money.formatPerUnit(costPerBaseUnit:baseUnit:)`, que da "$23.50 el kg", "$23.50 el litro" o "$3.20 la pieza".

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/Catalog/`:**
- `CatalogView.swift`
- `IngredientFormView.swift`
- `IngredientDetailView.swift`
- `IngredientBrandsSection.swift`

1. **Fila del catálogo** (`CatalogView`). Debajo del nombre, en vez de solo `buyingUnitDescription`:
   - Con `brandsCount` mayor que 0: "1 marca" o "N marcas", y si hay `currentBrand` con `costPerBaseUnit`, " · " y "Usamos " + la marca + " · " + el precio de `Money.formatPerUnit`. Ej.: "3 marcas · Usamos Selecta · $23.50 el kg".
   - Con `brandsCount` 0: "Sin marcas todavía" en `.warningText`.
   - Con `brandsCount` nulo (servidor viejo): `buyingUnitDescription`, como hoy.
   - Con letra de accesibilidad, la marca y el precio pasan a otra línea. El precio nunca se trunca.
   - Actualiza los datos de prueba del preview para que se vean los tres casos.
2. **Nuevo ingrediente** (`IngredientFormView`, solo modo `.create`). La sección "¿Cuánto te costó?" pasa a llamarse "Primera marca" y su pie dice: "Opcional. El ingrediente es general, como harina de trigo; aquí va la marca que compras. Puedes agregar más marcas después y elegir cuál usar en cada receta." Nada más cambia en el formulario ni en cómo se guarda.
3. **Detalle del ingrediente** (`IngredientDetailView`). "Marcas y precios" pasa a ser la primera sección, con este pie: "Tus recetas usan la marca marcada como La que usamos. Puedes elegir otra en cada receta." "Cómo lo compras" queda después.
4. **Filas de marca** (`IngredientBrandsSection`). En el subtítulo de cada marca con precio, agrega al final " · " y el precio de `Money.formatPerUnit` con su `costPerBaseUnit` y `baseUnit`, para comparar marcas de distinto tamaño. Ej.: "$23.50 por 1,000 g · hace 3 días · $23.50 el kg". Si `costPerBaseUnit` es nulo, como hoy.

**Criterios de aceptación.**
1. Los previews de `CatalogView` muestran una fila con marcas y precio, una "Sin marcas todavía" y una con el texto de hoy, en tamaño normal y en `.accessibility3`.
2. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los cuatro archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
