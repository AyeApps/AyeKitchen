Bloque B7. Corre en paralelo con I12 (no comparten archivos). Claude ya dejó: `OrderSoldBy` y los campos `sold_by` y `unit_label` de `OrderItem` en `backend/app/models/order.py`, y el contrato (párrafo "Por tanda o por pieza (B7)" de `/orders` y `suggested_price_per_yield_unit_cents` en `/recipes/{id}/cost`).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B7 del backend de AyeKitchen: vender una receta por tanda o por pieza.** Relee "Reglas que no se rompen" en `GEMINI.md` y, en `docs/api-contract.md`, el párrafo "Por tanda o por pieza (B7)" y la tabla de `/orders`, y el campo `suggested_price_per_yield_unit_cents` de `GET /recipes/{id}/cost`.

**Contexto.** Hoy una línea de pedido son tandas completas: si una receta rinde 12 galletas, no se pueden vender 4. Desde ahora cada línea dice si se vende por tanda (`sold_by: "batch"`, como hoy) o por la unidad que rinde la receta (`sold_by: "unit"`: 4 pz). Las líneas que ya existen son por tanda y no cambian.

**Ya existe, no lo cambies:** `OrderSoldBy`, `OrderItem.sold_by` (por defecto `batch`) y `OrderItem.unit_label` en `backend/app/models/order.py`.

**Alcance, dentro de `backend/app/`:**
- `schemas/order.py`
- `services/order_service.py`
- `tests/test_orders.py`
- `schemas/recipe.py`
- `services/costing_service.py` (solo el final de `calculate_recipe_cost`)
- `tests/test_costing.py`

1. **Precio sugerido por unidad.** `RecipeCostResponse` gana `suggested_price_per_yield_unit_cents: int`. En `calculate_recipe_cost`, se calcula desde el costo por unidad de rendimiento sin redondear (costo de la tanda sin redondear entre `yield_quantity`) multiplicado por `1 + margen/100`, y se redondea una sola vez con `round_to_cents`. Con `yield_quantity` 0 o inválido, vale 0. Nada más cambia en el costeo.
2. **Schemas de pedido.** `OrderItemInput` gana `sold_by: OrderSoldBy = OrderSoldBy.batch`. `OrderItemResponse` gana `sold_by` y `unit_label` (opcional), y `serialize_order` los llena desde la línea guardada.
3. **Crear** (`create_order`). Para cada línea:
   - `sold_by` `batch`: exactamente como hoy (precio por defecto `suggested_price_cents`, snapshot `batch_cost_cents`, `unit_label` nulo).
   - `sold_by` `unit`: precio por defecto `suggested_price_per_yield_unit_cents`; snapshot `round_to_cents` del costo por unidad (usa `Decimal(cost_per_yield_unit)` de la respuesta del costeo); `unit_label` = `yield_unit` de la receta.
   - El caché de costo por receta se sigue usando: una receta en dos líneas (una por tanda y otra por pieza) se costea una vez.
4. **Editar** (`update_order`). La línea anterior que se conserva se busca por la pareja (`recipe_id`, `sold_by`), no solo por `recipe_id`. Si la pareja ya existía, conserva su snapshot, su `unit_label` y su precio (salvo que venga uno nuevo), como hoy. Si no existía (receta nueva, o la misma receta cambiada de tanda a pieza), se calcula como una línea nueva con las reglas del punto 3. El chequeo de `PAYMENT_EXCEEDS_BALANCE` se queda igual.
5. **Totales.** `compute_order_totals` no cambia: `cantidad × precio unitario` vale para los dos modos.
6. **Pruebas.**
   - En `test_costing.py`: una receta que rinde 12 pz con tanda de $120.00 de costo y margen 30 da `suggested_price_cents` 15600 y `suggested_price_per_yield_unit_cents` 1300.
   - En `test_orders.py`:
     - Pedido con una línea `unit` de 4 pz de esa receta: precio unitario 1300, snapshot 1000, `unit_label` "pz", total 5200, costo 4000.
     - Una línea sin `sold_by` es `batch` y da lo mismo que hoy.
     - Una línea `unit` con cantidad 0.5 o con decimales se acepta; con 0 → `INVALID_REFERENCE` como hoy.
     - PATCH que conserva una línea `unit` existente mantiene su precio aunque cambie el costo de la receta.
     - PATCH que cambia una línea de `batch` a `unit` recalcula precio y snapshot por pieza.
     - Un pedido viejo guardado sin `sold_by` en la base (inserta un `Order` con la línea sin ese campo) se lee como `batch` con `unit_label` nulo.
     - Aislamiento: igual que las pruebas existentes, el otro usuario no puede usar la receta en una línea `unit`.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 115 pruebas; ninguna existente cambia su resultado.
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
