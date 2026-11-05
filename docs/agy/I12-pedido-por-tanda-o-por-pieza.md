Bloque I12. Corre en paralelo con B7 (no comparten archivos). Claude ya dejó en `Core/Models/`: `OrderSoldBy`, `OrderItem.soldBy` y `OrderItem.unitLabel` (opcionales) y `RecipeCost.suggestedPricePerYieldUnitCents` (opcional). Para probarlo contra producción, B7 tiene que estar desplegado.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I12 de AyeKitchen iOS: vender una receta por tanda o por pieza en el pedido.** Relee "Reglas de iOS" en `GEMINI.md` y, en `docs/api-contract.md`, el párrafo "Por tanda o por pieza (B7)" de `/orders` y el campo `suggested_price_per_yield_unit_cents` de `GET /recipes/{id}/cost`.

**Contexto.** Una usuaria hace galletas: su receta rinde una docena (12 pz), pero le piden 4. Hoy cada producto del pedido son tandas completas y el contador no baja de 1, así que no puede. Cada línea del pedido ahora puede venderse por tanda (como hoy) o por la unidad que rinde la receta (piezas, g o ml).

**Ya existe en `Core/Models/`, úsalo y no lo cambies:** `OrderSoldBy` (`.batch`, `.unit`), `OrderItem.soldBy` y `OrderItem.unitLabel` (nulos en pedidos viejos: trátalos como `.batch`), y `RecipeCost.suggestedPricePerYieldUnitCents`. La receta elegida (`RecipeListItem.recipe`) trae `yieldQuantity` y `yieldUnit`.

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/Orders/`:**
- `OrderFormModel.swift`
- `OrderFormView.swift`
- `OrderDetailView.swift`

1. **Borrador de línea** (`DraftOrderItem` y `OrderItemInput` en `OrderFormModel`). La línea guarda cómo se vende (`OrderSoldBy`), la unidad y lo que rinde la receta, y los dos precios sugeridos (por tanda y por unidad). `OrderItemInput` manda `soldBy`. Al agregar una receta, se pide `GET /recipes/{id}/cost` como hoy y se guardan los dos sugeridos.
2. **Por defecto.** Si la receta rinde más de 1 (`yieldQuantity` mayor que 1), la línea empieza **por pieza** con cantidad igual a lo que rinde (12) y el precio sugerido por unidad. Si rinde 1, empieza por tanda como hoy.
3. **Selector en cada línea** de `OrderFormView`, debajo del nombre, solo si la receta rinde más de 1: `Picker(.segmented)` con "Por pieza" y "Por tanda". Si `yieldUnit` es g o ml, la primera opción dice "Por g" o "Por ml". Al cambiar de modo:
   - Por pieza → por tanda: cantidad 1 y el precio sugerido por tanda.
   - Por tanda → por pieza: cantidad igual a lo que rinde y el precio sugerido por unidad.
   - Si la usuaria ya había escrito un precio distinto del sugerido, se reemplaza igual por el sugerido del modo nuevo (el precio es por unidad del modo).
4. **Cantidad.** Un `KitchenTextField` con teclado decimal y, a su lado, el `Stepper` de hoy (sube y baja de 1 en 1, mínimo 1 con los botones). Por pieza, la etiqueta dice "Piezas" (o "Gramos"/"Mililitros"); por tanda, "Tandas", y abajo, en `.inkMuted`, "1 tanda = 12 pz" con lo que rinde la receta. Se puede escribir cualquier cantidad mayor que 0 (4, 0.5, 250); si no es válida con `Quantity.parse` o es 0, el campo se marca y no se puede guardar.
5. **Precio.** La etiqueta dice "Precio por pieza" (o "por g"/"por ml") o "Precio por tanda", y "Te sugerimos cobrar" muestra el sugerido del modo elegido.
6. **Editar un pedido.** Las líneas existentes cargan su `soldBy` (nulo = tanda) y su `unitLabel`. Para mostrar el selector y "1 tanda = N" en una línea existente hace falta lo que rinde la receta: pídelo con el costo de la receta al abrir el formulario, como ya se hace al agregar; si falla, la línea se edita sin selector.
7. **Detalle del pedido** (`OrderDetailView`). Cada línea muestra la unidad: "4 pz × $13.00" por pieza y "1 tanda × $156.00" (o "2 tandas") por tanda. Las líneas viejas sin `soldBy` se muestran como tandas.
8. Previews: el formulario con una línea por pieza y otra por tanda, y el detalle con las dos, en tamaño normal y en `.accessibility3`.

**Criterios de aceptación.**
1. Con una receta que rinde 12 pz, agregarla al pedido la deja "Por pieza" con 12 piezas; cambiar a 4 piezas calcula el subtotal con el precio por pieza.
2. Cambiar a "Por tanda" deja 1 tanda con el precio sugerido de la tanda.
3. Una receta que rinde 1 no muestra el selector.
4. Un pedido viejo se abre, se edita y se guarda sin cambiar sus líneas.
5. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
