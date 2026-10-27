### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I3 de AyeKitchen iOS: lista de recetas y desglose de costo.** El backend ya está hecho y el esqueleto de la app de iPhone ya existe en `ios/aye-kitchen/aye-kitchen/`. Antes de empezar lee `GEMINI.md` completo (en especial "Reglas de iOS"), `DESIGN.md` (sobre todo "Desglose de costo (componente firma)" y "Control segmentado"), y en `docs/api-contract.md` la sección `/recipes`, incluido `GET /recipes/{id}/cost`. Este bloque no incluye crear ni editar recetas: eso es el bloque siguiente.

**Alcance: solo la carpeta `ios/aye-kitchen/aye-kitchen/Features/Recipes/`.** Hoy tiene `RecipesView.swift` con un estado vacío provisional; reemplázalo. Puedes crear los archivos que necesites dentro de esa carpeta. Usa sin modificarlos los modelos `Recipe`, `RecipeItem`, `ExtraCost`, `RecipeListItem`, `RecipeCost`, `CostLine` y `Page` de `Core/Models/`, `NetworkService.shared`, `ComingSoonSheet` y los componentes de `Design/`.

**1. Lista de recetas (`RecipesView`).**
- `NavigationStack` con título grande "Recetas". El "+" (`AddToolbarButton`, etiqueta "Nueva receta") sigue abriendo `ComingSoonSheet(title: "Nueva receta")`.
- `GET /recipes/` con `limit=50` y carga de la siguiente página al llegar al final; `.searchable` "Buscar receta" que manda `q` (espera ~300 ms y cancela la anterior); `.refreshable`. Lista nativa `insetGrouped` sobre `.canvasBackground`.
- Cada fila: el nombre en `.headline` y debajo "Te cuesta $X" con `batch_cost_cents` (`.subheadline`, `.inkMuted`, cifras tabulares). Si `complete` es falso, a la derecha `Chip("Falta precio", tone: .warning)`. Si `batch_cost_cents` es nulo, en lugar del costo: "No pudimos calcular el costo".
- Deslizar para borrar con confirmación (`DELETE /recipes/{id}`); `IN_USE` → "No se puede borrar: otra receta la usa como parte de ella."
- Sin recetas: "Todavía no hay recetas" / "Arma una receta y te decimos cuánto te cuesta." Error: `ErrorStateView`.

**2. Detalle con el desglose de costo (`RecipeDetailView`), como el artboard "Costo de una receta — iPhone" del lienzo.**
- Carga en paralelo `GET /recipes/{id}` y `GET /recipes/{id}/cost`; si cualquiera falla, `ErrorStateView`. `.refreshable` recarga ambos.
- Barra: título inline vacío o con el nombre al hacer scroll, y botón "Editar" que por ahora abre `ComingSoonSheet(title: "Editar receta")`.
- Encabezado: el nombre en `.title` heavy y debajo, en `.inkMuted`, el rendimiento: "Rinde 1 pieza · 12 porciones" (cantidad con `Quantity.format`, unidad en palabra: gramos, mililitros, piezas, en singular si es 1; la parte de porciones solo si `servings` existe).
- Tarjeta crema (`.softCard()`) con dos columnas iguales:
  - "Te cuesta" (`.subheadline` bold, `.inkSecondary`), el `batch_cost_cents` en `.title` heavy con cifras tabulares, y debajo "$X por porción" con `cost_per_serving_cents` si existe.
  - "Te sugerimos cobrar", el `suggested_price_cents` igual de grande pero en `.tint`, y debajo "Ganas $Y" (sugerido menos costo, en centavos enteros).
  - En tamaños de accesibilidad las dos columnas van una debajo de la otra. Los montos nunca se cortan.
  - Debajo, dentro de la misma tarjeta: "¿Cuánto quieres ganar?" y un `Picker` segmentado con 20 %, 30 %, 40 % y 60 %, seleccionado en el `margin_percent` del costo. Si el margen actual no es ninguno de los cuatro, ninguno aparece seleccionado y se lee "Ahora ganas el N %". En tamaños de accesibilidad mayores a AX1 pasa a `Picker` de menú.
  - Al elegir un margen: `PATCH /recipes/{id}` con solo `margin_percent`, luego vuelve a pedir el costo. Mientras guarda, el control se queda con lo elegido; si falla, regresa al anterior y muestra el error.
- Avisos, entre la tarjeta y la lista, solo si aplican: si `complete` es falso, "A esta receta le faltan precios: lo que te cuesta puede ser más." con `Chip` de advertencia; si `has_stale_prices`, "Algunos precios tienen más de N días." con N = `price_stale_days` del workspace (`session.me?.workspace`, entorno `SessionStore`).
- "De dónde sale el costo" (`.sectionTitleStyle()`): una fila por cada `CostLine`, en el orden del backend, y después una fila por cada `ExtraCost` de la receta. Cada fila: un ícono en un cuadrado de 40 pt escalable con radio `Radius.control` (ingrediente: SF Symbol `basket` sobre `.warningSoft`; subreceta: `birthday.cake` sobre `.accentSoftStrong`; costo fijo: `shippingbox` sobre `.neutralSoft`; ícono en `.accentTextDeep`); el nombre en `.body` bold; debajo el detalle en `.subheadline` `.inkMuted` (ingrediente: "300 g · Marca X · Walmart · 1000 g", es decir cantidad, unidad y `presentation_label`; subreceta: "Tu receta · 300 g"; costo fijo: "Costo fijo"); a la derecha el monto con cifras tabulares. Una línea con `missing_price` lleva `Chip("Falta precio", tone: .warning)` en lugar del monto; una con `price_is_stale`, `Chip("Precio viejo", tone: .warning)` debajo del detalle.
- Tocar una línea de subreceta navega al detalle de esa receta (`ref_id`). Las de ingrediente por ahora no hacen nada.
- En tamaños de accesibilidad el monto de cada línea pasa debajo del nombre en vez de a la derecha.

**Criterios de aceptación.**
1. Con la receta de ejemplo del contrato (harina 1000 g a $23.50, línea de 300 g), la línea muestra $7.05 y la tarjeta muestra los mismos totales que `GET /recipes/{id}/cost`.
2. Cambiar el margen a 60 % guarda en el backend y el precio sugerido cambia; al volver a abrir la receta sigue en 60 %.
3. Una receta con un ingrediente sin precio muestra el chip "Falta precio" en la lista, el aviso en el detalle y el chip en su línea.
4. Previews de la lista y del detalle con datos de ejemplo (incluida una línea sin precio y una con precio viejo), también en `.accessibility3`, con las columnas apiladas y ningún monto cortado.
5. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED`, y `git status` solo muestra cambios dentro de `ios/aye-kitchen/aye-kitchen/Features/Recipes/`.

Si algo choca con el alcance (un modelo al que le falta un campo, un componente que no alcanza, un error de compilación fuera de tu carpeta), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
