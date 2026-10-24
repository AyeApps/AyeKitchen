# AyeKitchen — Contrato de la API v1

Fuente de verdad entre `backend/`, `web/` e `ios/`. Si un cliente necesita algo que no está aquí, se cambia **este archivo primero** y luego el código.

Base: `http://localhost:8006/api/v1` (local) · `https://api-kitchen.ayeapps.com/api/v1` (prod).

## Convenciones

- **Auth:** `Authorization: Bearer <access_token>` emitido por aye-auth (`POST https://api-auth.ayeapps.com/api/v1/auth/login` con `app_client: "kitchen"`). El backend valida el JWT con el secreto compartido y auto-aprovisiona el usuario y su workspace personal.
- **Aislamiento:** todo recurso pertenece al workspace del usuario. Un id de otro workspace responde `404` (nunca `403`, para no revelar que existe).
- **Ids:** strings.
- **Dinero:** enteros en centavos, campos terminados en `_cents`. `2350` = $23.50. Nunca float.
- **Cantidades:** strings decimales (`"0.5"`, `"1000"`). El cliente envía string o número; el backend responde siempre string.
- **Redondeo:** el backend calcula con `Decimal` sin redondear y redondea a centavos (half-up, `round_to_cents` en `app/models/base.py`) **una sola vez por cada total mostrado**. Un total se calcula desde los valores sin redondear, no sumando líneas ya redondeadas.
- **Fechas:** ISO 8601 en UTC.
- **Listas paginadas** (`?page=1&limit=20`, `limit` máx. 100): `{"items": [...], "total": 45, "page": 1, "limit": 20, "pages": 3}` (`app/schemas/pagination.py`).
- **Errores:** `{"detail": "texto para humanos", "code": "CODIGO_ESTABLE"}` vía `AppError` (`app/core/errors.py`). Los clientes deciden por `code`. Errores de validación de FastAPI (422 estándar) quedan como están.
- **Borrado:** siempre soft delete (`deleted_at`). Los recursos borrados no aparecen en listas ni se resuelven por id.
- **Barra final:** las colecciones van con `/` final (`/ingredients/`), los recursos sin ella (`/ingredients/{id}`).

### Códigos de error

| code | HTTP | Cuándo |
|---|---|---|
| `NOT_FOUND` | 404 | Recurso inexistente, borrado o de otro workspace |
| `SYSTEM_UNIT_READONLY` | 403 | Intento de editar/borrar una unidad del sistema |
| `UNIT_NOT_CONVERTIBLE` | 422 | La unidad no se puede llevar a la unidad base del ingrediente/subreceta |
| `DUPLICATE_NAME` | 409 | Nombre repetido (case-insensitive) en el mismo workspace para unidades, ingredientes, proveedores o recetas |
| `IN_USE` | 409 | Borrar algo que otra entidad activa referencia (ingrediente en receta, presentación fijada, subreceta usada, unidad usada) |
| `RECIPE_CYCLE` | 422 | La receta se usaría a sí misma directa o indirectamente |
| `RECIPE_TOO_DEEP` | 422 | Después de guardar, alguna cadena de subrecetas del workspace tendría más de 10 niveles (contando hacia arriba: recetas que usan a la que se guarda) |
| `INVALID_REFERENCE` | 422 | Un id referenciado en el body no existe en el workspace (proveedor, ingrediente, receta, presentación de otro ingrediente) |
| `PAYMENT_EXCEEDS_BALANCE` | 422 | El pago deja el saldo del pedido negativo, o un cambio de líneas dejaría el total por debajo de lo ya pagado |

---

## /me

| Método | Ruta | Respuesta |
|---|---|---|
| GET | `/me/` | `{id, email, name, avatar_url, workspace: {id, name, currency, default_margin_percent, price_stale_days}}` |

Implementado en el esqueleto.

---

## /units — Tabla general de conversiones (B1)

`Unit`: `{id, name, abbreviation, base_unit: "g"|"ml"|"pz", factor_to_base: "240", is_system: bool}`

`1 <unit> = factor_to_base <base_unit>`.

| Método | Ruta | Body | Notas |
|---|---|---|---|
| GET | `/units/` | — | Sin paginar. Unidades del sistema + las del workspace. Orden: base_unit, luego factor |
| POST | `/units/` | `{name, abbreviation, base_unit, factor_to_base}` | Crea unidad del workspace. `factor_to_base > 0` |
| PATCH | `/units/{id}` | parcial | Sistema → `SYSTEM_UNIT_READONLY`. Cambiar `base_unit` si la unidad está usada en una receta activa o en una conversión de ingrediente activo → `IN_USE` (cambiar `factor_to_base` sí se permite: es corregir la medida) |
| DELETE | `/units/{id}` | — | 204. Sistema → `SYSTEM_UNIT_READONLY`. Usada en receta o conversión de ingrediente → `IN_USE` |

**Unidades del sistema** (`workspace_id = None`, sembradas al arrancar, idempotente):

| name | abbreviation | base_unit | factor_to_base |
|---|---|---|---|
| gramo | g | g | 1 |
| kilogramo | kg | g | 1000 |
| libra | lb | g | 453.592 |
| onza | oz | g | 28.3495 |
| mililitro | ml | ml | 1 |
| litro | l | ml | 1000 |
| taza | tz | ml | 240 |
| cucharada | cda | ml | 15 |
| cucharadita | cdta | ml | 5 |
| onza líquida | fl oz | ml | 29.5735 |
| pieza | pz | pz | 1 |
| docena | doc | pz | 12 |

## /ingredients (B1)

`Ingredient`: `{id, name, base_unit, group, notes, conversions: [{unit_id, unit_name, quantity_in_base}], created_at, updated_at}`

`conversions` = equivalencias propias: "1 taza de Harina = 125 g". Ganan sobre la tabla general.

| Método | Ruta | Body / Query | Notas |
|---|---|---|---|
| GET | `/ingredients/` | `?page&limit&q&group` | Paginado. `q` busca en name (case-insensitive). Orden por name |
| POST | `/ingredients/` | `{name, base_unit, group?, notes?, conversions?: [{unit_id, quantity_in_base}]}` | `unit_id` debe existir (sistema o workspace) → si no `INVALID_REFERENCE`. Sin `unit_id` repetidos |
| GET | `/ingredients/{id}` | — | |
| PATCH | `/ingredients/{id}` | parcial; `conversions` reemplaza la lista completa | `base_unit` no se puede cambiar si tiene presentaciones activas o si una receta activa lo usa → `IN_USE`. Quitar de `conversions` una unidad que una receta activa usa en una línea de este ingrediente → `IN_USE` (cambiar su `quantity_in_base` sí se permite) |
| DELETE | `/ingredients/{id}` | — | 204. Usado en una receta activa → `IN_USE`. Borra (soft) sus presentaciones |

### Regla de conversión (servicio `convert_to_base`, la usan B3 y los clientes vía costo)

Para llevar `quantity` en `unit_id` a la `base_unit` del ingrediente, en este orden:
1. `unit_id` vacío → la cantidad ya está en la unidad base.
2. El ingrediente tiene una conversión propia para ese `unit_id` → `quantity × quantity_in_base`.
3. La unidad tiene la misma `base_unit` que el ingrediente → `quantity × factor_to_base`.
4. Si no → `UNIT_NOT_CONVERTIBLE` con detail del estilo "Define cuántos g pesa 1 taza de Harina de trigo".

Ej.: Harina (g) con conversión taza=125 g: "2 taza" → 250 g. Leche (ml) sin conversión propia: "2 taza" → 480 ml. Harina sin conversión propia: "2 taza" → error.

## /suppliers (B1)

`Supplier`: `{id, name, notes, created_at, updated_at}`

| Método | Ruta | Notas |
|---|---|---|
| GET | `/suppliers/` | Sin paginar, orden por name |
| POST | `/suppliers/` | `{name, notes?}` |
| PATCH | `/suppliers/{id}` | parcial |
| DELETE | `/suppliers/{id}` | 204. Las presentaciones que lo usan quedan con `supplier_id = null` |

---

## /presentations — Marcas, proveedores y precios (B2)

`Presentation`:
```
{id, ingredient_id, ingredient_name, brand, supplier_id, supplier_name,
 package_quantity: "1000", base_unit: "g", barcode,
 latest_price_cents: 2350 | null, latest_price_at: datetime | null,
 cost_per_base_unit: "2.350000" | null,   # centavos por g/ml/pz, 6 decimales, solo para mostrar (2350 / 1000 g)
 is_current: bool,                        # es la que usa el costeo por defecto para su ingrediente
 price_age_days: int | null,              # días desde latest_price_at (fecha local del workspace); null sin precio
 price_is_stale: bool,                    # price_age_days > workspace.price_stale_days
 created_at, updated_at}
```

"Presentación vigente" de un ingrediente = la presentación activa cuyo `PriceRecord` más reciente (`recorded_at`) es el más nuevo entre todas las del ingrediente. Empate → la creada más recientemente. Presentaciones sin precio nunca son vigentes.

| Método | Ruta | Body / Query | Notas |
|---|---|---|---|
| GET | `/presentations/` | `?ingredient_id&page&limit` | Paginado. Orden: `latest_price_at` desc (sin precio al final) |
| POST | `/presentations/` | `{ingredient_id, brand, supplier_id?, package_quantity, package_unit_id?, barcode?, price_cents?}` | `package_unit_id` opcional: si viene, `package_quantity` se convierte a la base con la regla de conversión (ej. "1 kg" → 1000 g). Si viene `price_cents`, crea el primer `PriceRecord`. `package_quantity > 0` |
| GET | `/presentations/{id}` | — | |
| PATCH | `/presentations/{id}` | `{brand?, supplier_id?, package_quantity?, package_unit_id?, barcode?}` | El precio NO se cambia aquí: se agrega un registro |
| DELETE | `/presentations/{id}` | — | 204. Fijada en una receta activa → `IN_USE` |
| GET | `/presentations/stale` | `?page&limit` | **Precios por actualizar.** Paginado. Presentaciones activas con precio viejo (`price_is_stale`) que el costeo de verdad usa: son la vigente de su ingrediente y ese ingrediente aparece en una receta activa, o están fijadas en una receta activa. Orden: `latest_price_at` asc (la más vieja primero). Cada item es un `Presentation` más `used_in_recipes: int` (recetas activas distintas que la usan). Va declarada antes de `/presentations/{id}` en el router |
| GET | `/presentations/{id}/prices` | — | Historial completo, `recorded_at` desc: `[{id, price_cents, recorded_at, note}]` |
| POST | `/presentations/{id}/prices` | `{price_cents, recorded_at?, note?}` | 201. Agrega un precio; `recorded_at` por defecto ahora |

Servicios que B3 consume:
- `get_current_presentation(workspace_id, ingredient_id)` → presentación vigente con su último precio, o `None`.
- `get_latest_price(workspace_id, presentation_id)` → último `PriceRecord` o `None`.

---

## /recipes — Recetas, subrecetas y costo (B3)

`Recipe`:
```
{id, name, description,
 items: [{kind: "ingredient"|"recipe", ref_id, ref_name, quantity: "300", unit_id, unit_name,
          pinned_presentation_id}],
 extra_costs: [{name, cost_cents}],
 yield_quantity: "1", yield_unit: "pz", servings, margin_percent,
 created_at, updated_at}
```

| Método | Ruta | Body / Query | Notas |
|---|---|---|---|
| GET | `/recipes/` | `?page&limit&q` | Paginado, orden por name. Cada item de la lista incluye además `batch_cost_cents` y `complete` del costeo. Si el costo de una receta no se puede calcular (`AppError`), esa receta sale con `batch_cost_cents: null` y `complete: false`; la lista nunca falla por una receta |
| GET | `/recipes/{id}/usable-as-subrecipe` | — | Lista `[{id, name, yield_unit}]` de recetas que se pueden agregar como subreceta de `{id}` sin crear ciclo (excluye `{id}` y a quien la usa) |
| POST | `/recipes/` | campos de Recipe sin ids derivados | Valida referencias (`INVALID_REFERENCE`), que `pinned_presentation_id` pertenezca a ese ingrediente, que cada línea sea convertible (`UNIT_NOT_CONVERTIBLE`), ciclos (`RECIPE_CYCLE`) y profundidad (`RECIPE_TOO_DEEP`) |
| GET | `/recipes/{id}` | — | |
| PATCH | `/recipes/{id}` | parcial; `items` y `extra_costs` reemplazan la lista completa | Mismas validaciones |
| DELETE | `/recipes/{id}` | — | 204. Usada como subreceta en otra receta activa → `IN_USE` |
| GET | `/recipes/{id}/cost` | — | Desglose de costo, ver abajo |

### `GET /recipes/{id}/cost`

```
{recipe_id,
 lines: [{kind, ref_id, ref_name, quantity, unit_name,
          quantity_in_base: "250", base_unit: "g",
          presentation_id, presentation_label: "Marca X · Walmart · 1000 g", pinned: bool,
          cost_cents: 588,              # redondeado solo para mostrar
          missing_price: bool,
          price_is_stale: bool}],         # ingrediente: la presentación usada tiene precio viejo; subreceta: alguna línea suya, a cualquier profundidad, lo tiene
 ingredients_cost_cents, extras_cost_cents,
 batch_cost_cents,                       # total de una tanda
 cost_per_yield_unit: "5.875000",        # centavos por g/ml/pz del rendimiento, 6 decimales (lo usa quien la tome como subreceta)
 cost_per_serving_cents | null,
 margin_percent,                          # el efectivo (receta o workspace)
 suggested_price_cents,                   # batch_cost × (1 + margin/100)
 complete: bool,                          # false si alguna línea, incluso dentro de una subreceta, no tiene precio
 has_stale_prices: bool}                  # true si alguna línea, incluso dentro de una subreceta, usa un precio viejo
```

**Algoritmo** (todo en `Decimal` sin redondear hasta el final):
- Línea de ingrediente: `quantity_in_base` = `convert_to_base`. Presentación = la fijada si está activa; si no, la vigente. Costo = `quantity_in_base × precio_cents / package_quantity`. Sin presentación con precio → costo 0, `missing_price: true`.
- Línea de subreceta: la cantidad se convierte a la `yield_unit` de la subreceta con la tabla general (misma `base_unit`; si no, `UNIT_NOT_CONVERTIBLE`). Costo = `cantidad × costo_total_sin_redondear_subreceta / yield_quantity`. Se calcula recursivamente; `missing_price` de la subreceta se propaga.
- `batch_cost` = suma sin redondear de líneas + extras. Cada `*_cents` de la respuesta se redondea una vez desde su valor sin redondear.
- Si una presentación fijada fue borrada, la línea usa la vigente y `pinned: false`.
- Si la presentación fijada está activa pero no tiene ningún precio, **no** se usa la vigente: la línea queda `pinned: true`, `missing_price: true`, costo 0. Así la usuaria ve que le falta capturar el precio de la marca que eligió.
- Defensa: si al calcular se llegara a más de 10 niveles de subrecetas (datos corruptos), se detiene la recursión y esa línea queda con `missing_price: true`; nunca un error 500.

Ejemplo de verificación: Harina 1000 g a $23.50 (2350), línea de 300 g → `cost_cents` 705. Tres líneas de 0.4 centavos cada una muestran 0 cada una, pero suman 1.2 → `ingredients_cost_cents` 1.

---

## /orders — Pedidos y pagos (B4)

`Order`:
```
{id, customer_name, customer_phone, delivery_at, status: "pendiente"|"en_proceso"|"entregado"|"cancelado", notes,
 items: [{recipe_id, recipe_name, quantity, unit_price_cents, unit_cost_cents_snapshot}],
 payments: [{id, amount_cents, paid_at, method}],
 total_cents, paid_cents, balance_cents, cost_cents, profit_cents,
 created_at, updated_at}
```
`total = Σ quantity × unit_price`, `cost = Σ quantity × unit_cost_snapshot`, `profit = total − cost`, `balance = total − paid`.

| Método | Ruta | Body / Query | Notas |
|---|---|---|---|
| GET | `/orders/` | `?page&limit&status&from&to` | Paginado. `from`/`to` filtran `delivery_at`. Orden `delivery_at` asc |
| POST | `/orders/` | `{customer_name, customer_phone?, delivery_at, items: [{recipe_id, quantity, unit_price_cents?}] (mínimo 1), notes?}` | `unit_price_cents` por defecto = `suggested_price_cents` de la receta. `unit_cost_cents_snapshot` = `batch_cost_cents` de la receta en ese momento (lo calcula el backend; el cliente no lo envía) |
| GET | `/orders/{id}` | — | |
| PATCH | `/orders/{id}` | parcial; `items` reemplaza la lista (mínimo 1 línea) | Una línea cuya `recipe_id` ya estaba en el pedido conserva su snapshot **y su `unit_price_cents` anterior** si no se envía uno nuevo: el precio acordado con el cliente nunca cambia solo. Solo las líneas nuevas toman `suggested_price_cents` por defecto y calculan snapshot. Si el nuevo `total_cents` quedaría por debajo de `paid_cents` → `PAYMENT_EXCEEDS_BALANCE` y no se guarda nada |
| DELETE | `/orders/{id}` | — | 204 |
| POST | `/orders/{id}/payments` | `{amount_cents, paid_at?, method?}` | 201, devuelve el Order. Saldo negativo → `PAYMENT_EXCEEDS_BALANCE` |
| DELETE | `/orders/{id}/payments/{payment_id}` | — | Devuelve el Order |

## /expenses (B4)

`Expense`: `{id, description, amount_cents, spent_at, category, supplier_id, created_at}`

| Método | Ruta | Notas |
|---|---|---|
| GET | `/expenses/` | `?page&limit&from&to&category`, orden `spent_at` desc |
| POST | `/expenses/` | `{description, amount_cents, spent_at?, category?, supplier_id?}` |
| PATCH | `/expenses/{id}` | parcial |
| DELETE | `/expenses/{id}` | 204 |

## /summary (B4)

`GET /summary/monthly?year=2026&month=10` — límites del mes en la `timezone` del workspace.

```
{year, month,
 income_cents,            # pagos recibidos (paid_at) en el mes, de pedidos no cancelados
 expenses_cents,          # gastos (spent_at) en el mes
 net_cents,               # income − expenses
 orders_delivered, orders_pending,   # por delivery_at en el mes
 sales_cents,             # total de pedidos entregados en el mes
 estimated_profit_cents,  # profit de pedidos entregados en el mes (con snapshot)
 receivable_cents}        # saldo pendiente de pedidos no cancelados con entrega en el mes
```
