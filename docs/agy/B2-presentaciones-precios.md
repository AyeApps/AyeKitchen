### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B2 de AyeKitchen: presentaciones (marca, proveedor, tamaño) e historial de precios (backend).** El bloque B1 ya está hecho: existen `app/services/conversion_service.py`, `ingredient_service.py` y `supplier_service.py`.

Antes de empezar lee completos `GEMINI.md`, `docs/api-contract.md` (Convenciones, Códigos de error y la sección /presentations), `backend/app/models/presentation.py`, `ingredient.py`, `supplier.py`, `recipe.py`, `base.py`, y los archivos de B1 (`app/services/conversion_service.py`, `app/services/ingredient_service.py`, `app/api/v1/endpoints/ingredients.py`, `app/schemas/ingredient.py`) para copiar su estilo exacto de schemas, servicios, serialización y errores.

**Alcance: solo estos archivos.**
- Crear `backend/app/schemas/presentation.py` y `backend/app/services/presentation_service.py`.
- Llenar el router ya montado `backend/app/api/v1/endpoints/presentations.py`.
- Crear `backend/app/tests/test_presentations.py`.

**Comportamiento.**
- Respuesta `Presentation` exactamente con los campos del contrato, incluidos los derivados `ingredient_name`, `supplier_name`, `base_unit` (la del ingrediente), `latest_price_cents`, `latest_price_at`, `cost_per_base_unit` e `is_current`.
- `cost_per_base_unit`: último precio en centavos dividido entre `package_quantity`, en Decimal, cuantizado a 6 decimales y serializado como string. Es solo para mostrar; nunca se usa para calcular otra cosa. Nulo si no hay precio.
- "Presentación vigente" de un ingrediente: entre sus presentaciones activas con al menos un `PriceRecord` activo, la que tenga el `recorded_at` más reciente; en empate, la de `created_at` más reciente. Sin precio nunca es vigente. `is_current` es verdadero solo para esa.
- POST: `ingredient_id` debe ser un ingrediente activo del workspace; `supplier_id`, si viene, un proveedor activo del workspace; si no, `INVALID_REFERENCE`. Si viene `package_unit_id`, convierte `package_quantity` a la base del ingrediente con `convert_to_base` de B1 y guarda ya convertido (por ejemplo, 1 kg se guarda como 1000 en un ingrediente en g). `package_quantity` mayor que cero. Si viene `price_cents` (entero mayor o igual a cero), crea el primer `PriceRecord` con `recorded_at` ahora. Responde 201.
- PATCH: mismos campos opcionales y mismas validaciones; no acepta precio (el precio solo cambia agregando un registro).
- DELETE: si alguna receta activa del workspace tiene una línea con `pinned_presentation_id` igual a esta presentación, `IN_USE`; si no, soft delete. Sus `PriceRecord` se conservan.
- GET lista con `PaginatedResponse`, filtro opcional `ingredient_id`, orden por `latest_price_at` descendente con las que no tienen precio al final. Calcula los últimos precios con una sola consulta a `PriceRecord` para toda la página, no una por presentación.
- `/presentations/{id}/prices`: GET devuelve el historial completo ordenado por `recorded_at` descendente; POST agrega un registro (`price_cents` mayor o igual a cero, `recorded_at` opcional, `note` opcional) y responde 201 con el registro creado.
- Exporta en `presentation_service.py` dos funciones asíncronas que el bloque B3 va a consumir, con estos nombres exactos: `get_current_presentation(workspace_id, ingredient_id)`, que devuelve la presentación vigente junto con su último `PriceRecord` o nulo; y `get_latest_price(workspace_id, presentation_id)`, que devuelve el último `PriceRecord` activo de esa presentación o nulo.

**Reglas generales.** `CurrentWorkspace` en cada endpoint, filtro por `workspace_id` y `deleted_at` nulo en cada consulta, 404 `NOT_FOUND` para ids de otro workspace o borrados, `AppError` con los códigos del contrato, `updated_at` en cada PATCH.

**Criterios de aceptación.**
1. Tests como mínimo para: crear con `price_cents` 2350 y `package_quantity` 1000 da `cost_per_base_unit` "2.350000" y `latest_price_cents` 2350; crear con `package_unit_id` de kilogramo y cantidad 1 guarda 1000; agregar un precio nuevo cambia `latest_price_cents` y el historial queda en orden descendente; entre dos marcas del mismo ingrediente, `is_current` sigue a la que recibió el precio más reciente; `get_current_presentation` devuelve nulo cuando ninguna tiene precio; `IN_USE` al borrar una presentación fijada en una receta (crea la receta directamente con el modelo `Recipe`, porque sus endpoints aún no existen); `INVALID_REFERENCE` con proveedor de otro workspace; aislamiento: el usuario 2 recibe 404 sobre presentaciones y precios del usuario 1.
2. Desde `backend/`: `./venv/bin/python -m pytest -q` pasa completo, incluidos todos los tests anteriores, y `./venv/bin/ruff check . --exclude venv` no reporta errores.
3. Ningún archivo fuera del alcance listado fue modificado.

Si algo choca con el alcance (un test, el linter, un tipo, un campo que falta en un modelo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
