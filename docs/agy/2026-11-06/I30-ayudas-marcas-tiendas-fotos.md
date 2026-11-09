Bloque I30. Rama `local-first`. Pedido del usuario (2026-11-06): más consejos en lo complicado (equivalencias, costos fijos…), precio obligatorio al agregar otra marca, tienda en la primera marca de un ingrediente, un lugar fácil para editar las tiendas, y "Referencias" pasa a llamarse "Fotos" en la interfaz. Claude ya dejó los consejos nuevos en `Core/Tips/KitchenTips.swift` (con sus textos) y el mensaje de KitchenKit "Puedes guardar hasta 5 fotos".

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I30 de AyeKitchen iOS: ayudas, marcas con precio, tiendas y "Fotos".** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (regla 12: **no compiles la app**), `DESIGN.md` y `docs/agy/_pantallas-locales.md`. Lee `Core/Tips/KitchenTips.swift` (los consejos que vas a colocar ya existen ahí, con sus textos; no los cambies) y mira cómo se colocan los que ya están: `TipView(CatalogBrandsTip())` en `Features/Catalog/CatalogView.swift`, `.popoverTip(BackupTip(), …)` en `Features/Settings/SettingsView.swift`. Como modelo de ayuda permanente, `Features/Catalog/BaseUnitHelpSheet.swift` y su botón "¿Cuál elijo?" en `IngredientFormView.swift`.

**Ya existe y NO se cambia:** `Core/`, `App/`, `ios/KitchenKit/`. Los nombres en el código (`ReferencesSection`, `ReferenceStore`, `referenceIds`…) se quedan igual; solo cambian los textos que ve la persona. Si te falta algo fuera de `Features/`, detente y pregunta.

**Alcance, solo dentro de `ios/aye-kitchen/aye-kitchen/Features/`:**
- `Catalog/`: `IngredientFormView.swift`, `BrandFormView.swift` (y su modelo si está en el mismo archivo), `CatalogView.swift`, `IngredientDetailView.swift`; nuevos `StorePickerField.swift` y `ConversionsHelpSheet.swift`.
- `Recipes/`: `RecipeEditorView.swift`, `RecipeItemPicker.swift`; nuevo `FixedCostsHelpSheet.swift`.
- `Settings/SettingsView.swift`.
- `Shared/References/` (los tres archivos, solo textos).

**1. Consejos nuevos (TipKit), uno en cada lugar:**
- `IngredientConversionsTip`: `TipView` arriba del contenido de la sección "Equivalencias" de `IngredientFormView`.
- `BrandPackageSizeTip`: `TipView` arriba del campo "Tamaño del paquete" en `BrandFormView` (solo al crear) y en la sección "Primera marca" de `IngredientFormView`. Es el mismo consejo: TipKit lo muestra una vez y al cerrarlo en un lugar ya no sale en el otro.
- `CatalogStoresTip`: `.popoverTip` en el botón de Tiendas (ícono `storefront`) de la barra del Catálogo.
- `RecipeYieldTip`: `TipView` debajo del título "¿Cuánto rinde?" en `RecipeEditorView`.
- `RecipeFixedCostsTip`: `TipView` debajo del título "Costos fijos" en `RecipeEditorView`.
- `RecipeSubrecipeTip`: `TipView` arriba de la lista de recetas en `RecipeItemPicker`, solo cuando hay recetas que se pueden usar (`usableSubrecipes` no vacío).

**2. Ayuda que siempre está (además del consejo), para las dos cosas más difíciles:**
- Junto al título "Equivalencias" de `IngredientFormView`, un botón chico "¿Qué es esto?" (mismo estilo que "¿Cuál elijo?") que abre `ConversionsHelpSheet`, igual en forma a `BaseUnitHelpSheet` (hoja con desplazamiento y botón "Listo"). Título "Equivalencias". Texto, en párrafos cortos: "Tus recetas dicen tazas, cucharadas o pizcas, pero compras por peso, litro o pieza." / "Una equivalencia nos dice cuánto pesa (o mide) una de esas medidas para este ingrediente. Ejemplo: 1 taza de harina = 125 g; 1 taza de azúcar = 200 g." / "Cada ingrediente pesa distinto, por eso se pone en cada uno. Si una receta usa una medida que no tiene equivalencia, te la preguntamos en ese momento." / "Si no sabes cuánto pesa, mídelo una vez en tu báscula y anótalo."
- Junto al título "Costos fijos" de `RecipeEditorView`, el mismo botón "¿Qué es esto?" que abre `FixedCostsHelpSheet`. Título "Costos fijos". Texto: "Son gastos de la receta que no son ingredientes: la caja, la base de cartón, la vela, el gas o la luz del horno." / "Pon cuánto te cuesta cada uno por tanda. Se suman a lo que te cuesta la receta y se toman en cuenta en el precio que te sugerimos." / "Ejemplo: caja $25 y gas $10 → la receta te cuesta $35 más."

**3. Precio obligatorio al agregar otra marca** (`BrandFormView`, solo al crear): el campo dice "Precio" (sin "(opcional)"); no se puede guardar sin un precio válido: el botón de guardar queda desactivado como con los otros campos obligatorios, y si escribió algo que no es un precio, el campo se marca con "Escribe el precio que pagaste, por ejemplo 32.50". Al editar una marca nada cambia (el precio se cambia con "Registrar precio").

**4. Tienda en la primera marca de un ingrediente** (`IngredientFormView`, al crear):
- Extrae el selector de tienda de `BrandFormView` (`storePickerField`: "Sin tienda", la lista, "Nueva tienda…" con su alerta) a un componente `StorePickerField` en `Catalog/StorePickerField.swift`, y úsalo en los dos formularios. La creación de la tienda nueva usa la misma regla que ya usa `BrandFormView` (léela, no inventes otra).
- En la sección "Primera marca", el orden es: Marca, Tienda, Tamaño del paquete, Precio. Al guardar, la marca se crea con esa tienda (hoy se manda `supplierId: nil`).
- La primera marca sigue siendo opcional como bloque: si marca, tamaño y precio están vacíos, se guarda solo el ingrediente. Pero si llenó cualquiera de ellos, el precio y el tamaño son obligatorios (hoy, si falta el precio, la marca se descarta sin avisar): márcalos y no guardes. Cambia el pie de la sección a: "Opcional. El ingrediente es general, como harina de trigo; aquí va la marca que compras, dónde y a cuánto. Puedes agregar más marcas después."

**5. Editar tiendas desde Ajustes:** en `SettingsView`, sección general, una fila "Tus tiendas" (con el ícono `storefront` y el número de tiendas a la derecha, como "Unidades propias") que abre `SuppliersView()` en una hoja (`.sheet`; `SuppliersView` ya trae su propio `NavigationStack`, no la metas en un `NavigationLink`). El botón del Catálogo se queda.

**6. "Referencias" pasa a "Fotos"** en todo texto visible (títulos, botones, menús, confirmaciones, alertas, etiquetas de accesibilidad), sin tocar nombres en el código:
- Título de la sección: "Fotos". Botón: "Agregar foto". Miniatura: "Foto 1 de 3". Visor: "Quitar foto", confirmación "¿Quitar esta foto? No cambia nada más.", y "Ya no quedan fotos.". Errores: "No se pudo guardar la foto" (y lo mismo en los demás mensajes que digan referencia).
- `IngredientDetailView`: `Section("Referencias")` → `Section("Fotos")`.
- `SettingsView`: en el mensaje de borrar datos, "fotos de referencia" → "fotos".
- Revisa con una búsqueda que no quede la palabra "referencia" en ningún texto visible de `Features/`.

**7. Previews:** los existentes siguen compilando; agrega previews de `ConversionsHelpSheet` y `FixedCostsHelpSheet` (normal y AX3).

**Criterios de aceptación** (Claude compila y prueba al auditar):
1. Cada consejo sale una vez en su lugar y "Volver a ver los consejos" los vuelve a mostrar.
2. "¿Qué es esto?" abre su hoja en Equivalencias y en Costos fijos.
3. No se puede agregar otra marca sin precio; al crear un ingrediente con marca se elige la tienda y queda guardada; con marca pero sin precio, no se guarda y se marca el campo.
4. "Tus tiendas" en Ajustes abre las tiendas y permite agregar, renombrar y borrar.
5. No aparece "Referencias"/"referencia" en la interfaz; dice "Fotos".
6. `git status` solo muestra archivos dentro de `Features/`.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
