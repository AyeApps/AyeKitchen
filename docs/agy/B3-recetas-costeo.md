### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B3 de AyeKitchen: recetas, subrecetas y cálculo de costo (backend).** Los bloques B1 y B2 ya están hechos. Este es el bloque central del producto: el número que ve la usuaria tiene que ser exacto.

Antes de empezar lee completos `GEMINI.md`, `docs/api-contract.md` (Convenciones, Códigos de error y la sección /recipes completa, incluido el algoritmo y el ejemplo de verificación), `backend/app/models/recipe.py`, `base.py` (en especial `round_to_cents`), `workspace.py`, y de los bloques anteriores `app/services/conversion_service.py` (`convert_to_base`, `convert_between_base_units`) y `app/services/presentation_service.py` (`get_current_presentation`, `get_latest_price`). Copia el estilo de schemas, servicios y errores de `app/services/presentation_service.py` y `app/api/v1/endpoints/presentations.py`.

**Alcance: solo estos archivos.**
- Crear `backend/app/schemas/recipe.py`, `backend/app/services/recipe_service.py` (CRUD y validaciones) y `backend/app/services/costing_service.py` (solo el cálculo).
- Llenar el router ya montado `backend/app/api/v1/endpoints/recipes.py`.
- Crear `backend/app/tests/test_recipes.py` y `backend/app/tests/test_costing.py`.

**CRUD y validaciones (`recipe_service.py`).**
- La respuesta `Recipe` es la del contrato e incluye `ref_name` y `unit_name` resueltos en cada línea.
- En POST y PATCH, en este orden: cada línea `kind=ingredient` apunta a un ingrediente activo del workspace y cada `kind=recipe` a una receta activa del workspace, si no `INVALID_REFERENCE`; `pinned_presentation_id`, si viene, solo se permite en líneas de ingrediente y debe ser una presentación activa de ese mismo ingrediente, si no `INVALID_REFERENCE`; `unit_id`, si viene, debe existir; cada línea de ingrediente debe ser convertible con `convert_to_base` y cada línea de subreceta con `convert_between_base_units` hacia la `yield_unit` de la subreceta (propaga `UNIT_NOT_CONVERTIBLE`); `quantity` y `yield_quantity` mayores que cero.
- Ciclos: al guardar, recorre el árbol de subrecetas desde la receta que se guarda (con sus líneas nuevas). Si en algún camino aparece la propia receta, `RECIPE_CYCLE`. Si algún camino supera 10 niveles, `RECIPE_TOO_DEEP`. Una receta nueva no puede formar ciclo, pero sí exceder la profundidad.
- PATCH con `items` o `extra_costs` reemplaza la lista completa. Nombre repetido en el workspace (sin distinguir mayúsculas, solo activas) es `DUPLICATE_NAME`.
- DELETE: si otra receta activa la usa como subreceta, `IN_USE`; si no, soft delete.
- `GET /recipes/{id}/usable-as-subrecipe`: recetas activas del workspace que se pueden agregar como subreceta de `{id}` sin crear ciclo; excluye `{id}` y toda receta que directa o indirectamente contenga a `{id}`.
- Lista paginada con filtro `q` y orden por nombre; cada elemento agrega `batch_cost_cents` y `complete` calculados con el servicio de costeo.

**Costeo (`costing_service.py`).** Una función pública asíncrona `calculate_recipe_cost(workspace_id, recipe)` que devuelve la estructura de `GET /recipes/{id}/cost` del contrato. Sigue el algoritmo del contrato al pie de la letra:
- Todo el cálculo interno va en Decimal sin redondear. Las líneas de ingrediente usan la presentación fijada si sigue activa (`pinned: true`), y si no, la vigente de `get_current_presentation` (`pinned: false`). Costo de la línea igual a cantidad en base por precio en centavos entre `package_quantity`. Sin precio, costo cero y `missing_price: true`.
- Las líneas de subreceta convierten la cantidad a la `yield_unit` de la subreceta con `convert_between_base_units` y cuestan cantidad por costo total sin redondear de la subreceta entre su `yield_quantity`. El costo de la subreceta se obtiene recursivamente con una función interna que devuelve el total sin redondear y si está completo; usa un caché por receta dentro de una misma llamada para no recalcular la misma subreceta dos veces.
- `presentation_label` con el formato "Marca · Proveedor · cantidad unidad" (sin proveedor: "Marca · cantidad unidad").
- `batch_cost` es la suma sin redondear de líneas más extras. `margin_percent` efectivo es el de la receta o, si es nulo, el `default_margin_percent` del workspace. `suggested_price` es el `batch_cost` por uno más el margen entre cien. `cost_per_yield_unit` es el `batch_cost` entre `yield_quantity`, cuantizado a 6 decimales como string. `cost_per_serving` es el `batch_cost` entre `servings` si existe.
- Cada campo terminado en `_cents` se redondea con `round_to_cents` una sola vez, desde su valor sin redondear. Nunca sumes valores ya redondeados.
- `complete` es falso si cualquier línea, incluso dentro de una subreceta a cualquier profundidad, tiene `missing_price`.
- `GET /recipes/{id}/cost` llama a esta función.

**Reglas generales.** `CurrentWorkspace` en cada endpoint, filtro por `workspace_id` y `deleted_at` nulo en cada consulta, 404 `NOT_FOUND`, `AppError` con los códigos del contrato, `updated_at` en cada PATCH.

**Criterios de aceptación.**
1. `test_costing.py` cubre como mínimo: el ejemplo del contrato (harina de 1000 g a 2350, línea de 300 g, `cost_cents` 705); línea en tazas con conversión propia (2 tazas de harina con taza de 125 g a 2350 por 1000 g dan 588); el caso de redondeo del contrato (tres líneas de 0.4 centavos muestran 0 cada una y `ingredients_cost_cents` 1); presentación fijada contra vigente (con dos marcas de precios distintos, sin fijar usa la de precio más reciente y fijada usa la elegida); extras sumados al `batch_cost`; margen de receta contra margen del workspace en `suggested_price_cents`; subreceta (betún que rinde 800 g y cuesta 4000, usar 200 g aporta 1000); subreceta dentro de subreceta; `missing_price` en una sub-subreceta deja `complete` falso en la receta raíz.
2. `test_recipes.py` cubre como mínimo: CRUD; `RECIPE_CYCLE` directo (A usa A) e indirecto (A usa B, luego B intenta usar A); `RECIPE_TOO_DEEP` con 11 niveles; `usable-as-subrecipe` excluye a la propia receta y a sus ancestros; `IN_USE` al borrar una subreceta en uso; `INVALID_REFERENCE` con presentación fijada de otro ingrediente; `UNIT_NOT_CONVERTIBLE` con tazas en un ingrediente en gramos sin conversión propia; aislamiento entre los dos usuarios en lectura, costo, edición y borrado.
3. Desde `backend/`: `./venv/bin/python -m pytest -q` pasa completo, incluidos todos los tests anteriores, y `./venv/bin/ruff check . --exclude venv` no reporta errores.
4. Ningún archivo fuera del alcance listado fue modificado.

Si algo choca con el alcance (un test, el linter, un tipo, un campo que falta en un modelo, una función de B1 o B2 que no se comporta como dice el contrato), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
