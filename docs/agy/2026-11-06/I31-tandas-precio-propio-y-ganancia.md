Bloque I31. Rama `local-first`. Va **después de K5 y de I30** (usa lo de K5 y toca `Features/Recipes/` y `Features/Orders/`, que I30 también toca). Pedido del usuario (2026-11-06, con capturas): que el pedido diga cuántas tandas hacer ("1.5, o haz 2 y te sobran x para vender"), arreglar el Total que se parte en dos renglones, mostrar el % de ganancia, y "Tu precio" en la receta además del sugerido.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I31 de AyeKitchen iOS: cuántas tandas hacer, "Tu precio" y el porcentaje de ganancia.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (regla 12: **no compiles la app**), `DESIGN.md` y `docs/agy/_pantallas-locales.md`. Lee `ios/KitchenKit/Sources/KitchenDomain/Rules/SalesQueries.swift` (K5: `Profit`, `RecipeSalePrice`, `salePrice(of:cost:)`, `suggestedProfit(cost:)`, `defaultLinePriceCents`, `BatchNeed`, `batchNeeds(for:)`), `OrderTotals.profitPercent` y los nuevos parámetros `salePriceCents`/`salePriceSoldBy` de `updateRecipe`. Usa esas funciones; **no recalcules dinero ni porcentajes en la vista**.

**Ya existe y NO se cambia:** `Core/`, `App/`, `ios/KitchenKit/`. Si te falta algo ahí, detente y pregunta.

**Alcance, solo dentro de `ios/aye-kitchen/aye-kitchen/Features/`:**
- `Orders/OrderDetailView.swift` (y `OrderDetailModel.swift` si hace falta)
- `Orders/OrderFormModel.swift` (solo el precio inicial de una línea) y `Orders/OrderFormView.swift` (solo el rótulo "Tu precio"/"Sugerido" de ese precio)
- `Recipes/RecipeDetailView.swift` (y `RecipeDetailModel.swift`)
- `Recipes/SalePriceSheet.swift` (nuevo)

1. **Detalle del pedido, sección nueva "Para este pedido"**, entre "Productos" y la tarjeta de dinero, con una fila por cada `BatchNeed` de `batchNeeds(for: order)`. Nada de esto se guarda; se calcula al vuelo.
   - Si no sobra nada (`leftoverUnits` es cero; **no** lo decidas por `exactBatches`, que viene redondeado a 2 decimales): "Haz 2 tandas de Pastel de vainilla" con `wholeBatches` (singular "1 tanda").
   - Si no: renglón principal "Necesitas 1.5 tandas de Galletas", y debajo, en texto secundario, "Si haces 2, te sobran 5 piezas para vender (unos $75.00)" usando `wholeBatches`, `leftoverUnits` con su unidad en palabras (pieza/piezas, g, ml; mira cómo ya se escribe la unidad en `RecipeDetailView`, "Rinde 1 pieza") y `leftoverValueCents`. Sin valor (nulo), sin el paréntesis.
   - Ícono a la izquierda (como las filas de "De dónde sale el costo"), números con `monospacedDigit()`. Si el pedido no tiene necesidades (todas las recetas borradas), la sección no aparece.
2. **Tarjeta de dinero del pedido:**
   - Arregla el "Total" que hoy se parte ("$270.0 / 0"): ningún importe se corta a la mitad. Usa `ViewThatFits`: tres columnas si caben en una línea; si no, Total arriba en grande y "Ya te pagaron" / "Te falta cobrar" en una fila debajo; y en tamaños de accesibilidad la pila vertical que ya existe. Cada importe con `lineLimit(1)` (puedes usar `minimumScaleFactor(0.8)` como último recurso, no como solución).
   - El renglón de abajo agrega el porcentaje: "Te cuesta $148.50 · Ganas $121.50 (82 %)". Si la ganancia es negativa: "Te cuesta $X · Pierdes $Y" en color de advertencia. Sin porcentaje si `profitPercent` es nulo.
3. **Detalle de la receta, tarjeta crema:**
   - Bajo "Te sugerimos cobrar", el renglón pasa a "Ganas $4.13 (50 %)" con `suggestedProfit(cost:)`.
   - Debajo del selector "¿Cuánto quieres ganar?", un bloque **"Tu precio"**:
     - Sin precio propio: un botón secundario "Poner mi precio" y la frase "¿Ya cobras otra cosa? Ponla y te decimos cuánto ganas."
     - Con precio propio (`salePrice(of:cost:)`): "Tu precio $15.00 por tanda" (o "por pieza"), debajo "Ganas $6.75 (82 %)", y si la receta rinde más de 1, el otro lado en texto secundario ("$3.00 por pieza · ganas $1.35"). Si pierde dinero: "Con este precio pierdes $X" en color de advertencia. Un botón "Cambiar" que abre la misma hoja.
4. **`SalePriceSheet`** (hoja con `NavigationStack`, "Cancelar" y "Guardar"): título "Tu precio". Campo de precio con teclado decimal (usa el mismo parser de precio que ya usa la app, `RecordPriceModel.parsePriceCents`). Si la receta rinde más de 1 unidad, un selector "Por tanda" / "Por pieza" (con la palabra de la unidad de la receta); si rinde 1, solo por tanda. Mientras escribe, muestra en vivo "Ganas $X (Y %)" o "Pierdes $X" con `Profit.make`. Guarda con `store.mutate { try $0.updateRecipe(id:, salePriceCents: .some(cents), salePriceSoldBy: .some(forma), ctx: $1) }`. Si ya tenía precio, un botón destructivo "Quitar mi precio" que manda `.some(nil)`. Errores de `DomainError` debajo del campo.
5. **Formulario de pedido:** el precio inicial de una línea nueva (y al cambiar entre tanda y pieza) viene de `defaultLinePriceCents` en vez del sugerido directo. Si viene del precio propio, el texto de ayuda dice "Tu precio"; si no, "Sugerido" (mira cómo se rotula hoy). Nada más cambia en el formulario.
6. **Accesibilidad y previews:** filas de tandas leídas como una sola frase; todo legible en AX3. Previews dentro de `#if DEBUG` con `LocalStore.preview` y datos armados en el archivo: pedido con 1.5 tandas, pedido con tandas exactas, receta con y sin precio propio, receta con pérdida, `SalePriceSheet` normal y AX3.

**Criterios de aceptación** (Claude compila y prueba en el simulador al auditar):
1. Un pedido de 15 piezas de una receta que rinde 10 dice "Necesitas 1.5 tandas…" y "Si haces 2, te sobran 5 piezas para vender (unos $…)"; uno de 18 tandas dice "Haz 18 tandas…".
2. El Total no se parte en ningún tamaño de letra; el renglón de abajo muestra el %.
3. "Poner mi precio" guarda, muestra la ganancia y el %, y los pedidos nuevos de esa receta empiezan con ese precio; "Quitar mi precio" vuelve al sugerido.
4. `git status` solo muestra archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
