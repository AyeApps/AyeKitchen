### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B4 de AyeKitchen: pedidos con pagos, gastos y resumen mensual (backend).** Los bloques B1, B2 y B3 ya están hechos.

Antes de empezar lee completos `GEMINI.md`, `docs/api-contract.md` (Convenciones, Códigos de error y las secciones /orders, /expenses y /summary), `backend/app/models/order.py`, `workspace.py`, `base.py`, y `app/services/costing_service.py` (`calculate_recipe_cost`) junto con `app/services/recipe_service.py`. Copia el estilo de schemas, servicios y errores de los bloques anteriores.

**Alcance: solo estos archivos.**
- Crear `backend/app/schemas/order.py`, `backend/app/schemas/expense.py`, `backend/app/schemas/summary.py`.
- Crear `backend/app/services/order_service.py`, `backend/app/services/expense_service.py`, `backend/app/services/summary_service.py`.
- Llenar los routers ya montados `backend/app/api/v1/endpoints/orders.py`, `expenses.py`, `summary.py`.
- Crear `backend/app/tests/test_orders.py`, `test_expenses.py`, `test_summary.py`.

**Pedidos (`/orders`).**
- Respuesta `Order` del contrato con `recipe_name` en cada línea y los derivados `total_cents`, `paid_cents`, `balance_cents`, `cost_cents` y `profit_cents`. Las multiplicaciones de cantidad por precio o costo se hacen en Decimal y cada total se redondea una sola vez con `round_to_cents`.
- POST: cada `recipe_id` debe ser una receta activa del workspace (`INVALID_REFERENCE`); `quantity` mayor que cero. Para cada línea calcula el costo de la receta con `calculate_recipe_cost`: `unit_cost_cents_snapshot` es su `batch_cost_cents`, y si el cliente no manda `unit_price_cents`, usa su `suggested_price_cents`. El cliente nunca puede enviar el snapshot; si lo manda, se ignora. Calcula cada receta distinta una sola vez por petición.
- PATCH: campos parciales. Si viene `items`, reemplaza la lista: las líneas cuya `recipe_id` ya existía en el pedido conservan su snapshot anterior; solo las nuevas o las que cambiaron de receta calculan uno nuevo. Si viene `status`, acepta cualquiera de los cuatro valores.
- DELETE: soft delete.
- Lista paginada con filtros `status`, `from` y `to` sobre `delivery_at` (inclusive), orden por `delivery_at` ascendente.
- Pagos: POST `/orders/{id}/payments` agrega un pago (monto mayor que cero, `paid_at` opcional, `method` opcional) y responde 201 con el pedido completo; si el pago deja `balance_cents` negativo, `PAYMENT_EXCEEDS_BALANCE`. DELETE `/orders/{id}/payments/{payment_id}` lo quita y responde el pedido; un `payment_id` inexistente es `NOT_FOUND`.

**Gastos (`/expenses`).** CRUD según el contrato. Lista paginada con filtros `from`, `to` (sobre `spent_at`, inclusive) y `category`, orden por `spent_at` descendente. `supplier_id`, si viene, debe ser un proveedor activo del workspace (`INVALID_REFERENCE`).

**Resumen (`GET /summary/monthly?year&month`).** Valida `month` entre 1 y 12 y `year` entre 2000 y 2100 (422 estándar de FastAPI). Los límites del mes se calculan en la `timezone` del workspace con `zoneinfo` y se convierten a UTC para las consultas. Los campos y sus definiciones son exactamente los del contrato: `income_cents` cuenta pagos por su `paid_at` dentro del mes, de pedidos no cancelados y no borrados, aunque la entrega sea en otro mes; `orders_delivered` y `sales_cents` cuentan pedidos con estado entregado y `delivery_at` en el mes; `orders_pending` cuenta pedidos con estado pendiente o en proceso y `delivery_at` en el mes; `estimated_profit_cents` es la suma de `profit` de los entregados del mes; `receivable_cents` es la suma de saldos de pedidos no cancelados con entrega en el mes; `net_cents` es ingresos menos gastos.

**Reglas generales.** `CurrentWorkspace` en cada endpoint, filtro por `workspace_id` y `deleted_at` nulo en cada consulta, 404 `NOT_FOUND`, `AppError` con los códigos del contrato, `updated_at` en cada PATCH.

**Criterios de aceptación.**
1. Tests como mínimo para: crear un pedido sin precio toma el `suggested_price_cents` y guarda el snapshot; cambiar después el precio de un ingrediente NO cambia `cost_cents` de ese pedido; PATCH que agrega una línea nueva calcula su snapshot sin tocar el de las existentes; pagos parciales actualizan `paid_cents` y `balance_cents`; `PAYMENT_EXCEEDS_BALANCE`; borrar un pago; filtros de la lista; CRUD de gastos con filtro por mes; resumen mensual con un pago hecho en octubre de un pedido entregado en noviembre (cuenta en `income_cents` de octubre y en `sales_cents` de noviembre); un pago a las 23:30 del 31 de octubre hora de México cuenta en octubre aunque en UTC ya sea noviembre; pedidos cancelados excluidos; aislamiento entre los dos usuarios en pedidos, pagos, gastos y resumen.
2. Desde `backend/`: `./venv/bin/python -m pytest -q` pasa completo, incluidos todos los tests anteriores, y `./venv/bin/ruff check . --exclude venv` no reporta errores.
3. Ningún archivo fuera del alcance listado fue modificado.

Si algo choca con el alcance (un test, el linter, un tipo, un campo que falta en un modelo, una función de un bloque anterior que no se comporta como dice el contrato), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
