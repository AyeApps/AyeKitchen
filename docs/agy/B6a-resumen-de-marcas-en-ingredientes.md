Bloque B6a. Corre en paralelo con B6b e I9 (no comparten archivos).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B6a del backend de AyeKitchen: resumen de marcas en cada ingrediente.** Relee "Reglas que no se rompen" en `GEMINI.md` y, en `docs/api-contract.md`, el párrafo "Resumen de marcas (B6a)" de `/ingredients` y la definición de "Presentación vigente" de `/presentations`.

**Contexto.** El ingrediente es el general ("Harina de trigo") y sus marcas son presentaciones. La app quiere mostrar en el catálogo cuántas marcas tiene cada ingrediente y cuál usa el costeo, sin pedir las presentaciones una por una.

**Alcance, dentro de `backend/app/`:**
- `schemas/ingredient.py`
- `services/ingredient_service.py`
- `api/v1/endpoints/ingredients.py`
- `tests/test_ingredients.py`

De `services/presentation_service.py` solo puedes importar y usar, sin modificarlo, `compute_cost_per_base_unit`. No modifiques ese archivo: otro bloque lo está cambiando al mismo tiempo.

1. **Schemas.** En `schemas/ingredient.py`, un schema nuevo `IngredientCurrentBrandResponse` con `presentation_id`, `brand`, `supplier_name` (opcional) y `cost_per_base_unit` (string opcional). `IngredientResponse` gana `brands_count: int = 0` y `current_brand: IngredientCurrentBrandResponse | None = None`.
2. **Servicio.** En `services/ingredient_service.py`, una función async nueva `get_brand_summaries(workspace_id, ingredient_ids)` que devuelve un diccionario de ingredient_id a (cantidad de marcas, marca vigente o nada). Debe hacer un número fijo de consultas, sin importar cuántos ingredientes reciba: una para todas las presentaciones activas de esos ingredientes, una para todos los `PriceRecord` activos de esas presentaciones ordenados por `recorded_at` y `created_at` descendente, y una para los proveedores activos que aparezcan. Ninguna consulta en un ciclo. La vigente se elige exactamente como `get_current_presentation` de `presentation_service`: entre las presentaciones con precio, la de registro más reciente; empate, la creada más recientemente; sin precio nunca es vigente. `cost_per_base_unit` sale de `compute_cost_per_base_unit` con el precio más reciente de esa presentación y su `package_quantity`. Todas las consultas filtran por `workspace_id` y `deleted_at` nulo.
3. **Endpoints.** En `api/v1/endpoints/ingredients.py`, la lista, el crear, el ver uno y el editar llenan `brands_count` y `current_brand` usando `get_brand_summaries`. En la lista se llama una sola vez con los ids de la página. Un ingrediente recién creado sale con 0 y nulo.
4. **Pruebas** en `tests/test_ingredients.py`:
   - Un ingrediente sin marcas: `brands_count` 0, `current_brand` nulo.
   - Tres marcas, una sin precio y dos con precio en fechas distintas: `brands_count` 3 y `current_brand` es la del precio más reciente, con su `brand`, `supplier_name` y `cost_per_base_unit` (ej. 2350 por 1000 g → "2.350000").
   - Una marca borrada no cuenta.
   - En la lista, cada ingrediente trae su propio resumen.
   - Aislamiento: las marcas de `auth_headers_user_2` no aparecen en el resumen de los ingredientes de `auth_headers`.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 100 pruebas; ninguna existente cambia su resultado.
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
