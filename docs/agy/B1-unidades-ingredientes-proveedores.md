### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B1 de AyeKitchen: unidades de conversión, ingredientes y proveedores (backend).**

Antes de empezar lee completos `GEMINI.md`, `docs/api-contract.md` (secciones Convenciones, Códigos de error, /units, /ingredients, /suppliers) y los modelos `backend/app/models/unit.py`, `ingredient.py`, `supplier.py`, `base.py`, además de `backend/app/core/deps.py` y `backend/app/core/errors.py`. Como referencia de estilo de capas (endpoint → servicio → modelo, serialización con una función `_serialize_*`) usa el repo hermano `../aye-finance/backend/app/api/v1/endpoints/accounts.py`, `../aye-finance/backend/app/services/account_service.py` y `../aye-finance/backend/app/schemas/account.py`. No toques ese repo.

**Alcance: solo estos archivos.**
- Crear `backend/app/schemas/unit.py`, `backend/app/schemas/ingredient.py`, `backend/app/schemas/supplier.py`.
- Crear `backend/app/services/unit_service.py`, `backend/app/services/ingredient_service.py`, `backend/app/services/supplier_service.py`, `backend/app/services/conversion_service.py`.
- Llenar los routers vacíos ya montados `backend/app/api/v1/endpoints/units.py`, `ingredients.py`, `suppliers.py` (conserva la variable `router`; no cambies prefijos en `app/api/v1/router.py`).
- Editar `backend/main.py` únicamente para llamar a la siembra de unidades del sistema dentro de `lifespan`, justo después de `await init_db()`.
- Crear `backend/app/tests/test_units.py`, `test_ingredients.py`, `test_suppliers.py`, `test_conversion.py`.

**Unidades (`/units`).**
- Siembra: función en `unit_service.py` que inserta las 12 unidades del sistema de la tabla del contrato con `workspace_id` nulo. Idempotente: si ya existe una unidad del sistema con esa `abbreviation`, no la duplica ni la modifica. También llama a esta siembra desde el fixture `init_test_db` de `backend/app/tests/conftest.py` después de `init_beanie`, y vuelve a sembrar al final de `clear_database` (que hoy borra todo), para que los tests siempre vean las unidades del sistema. Ese es el único cambio permitido en `conftest.py`.
- La respuesta incluye `is_system` (verdadero cuando `workspace_id` es nulo) y `factor_to_base` como string.
- GET lista sin paginar las del sistema más las del workspace actual, ordenadas por `base_unit` y luego por `factor_to_base`.
- POST, PATCH y DELETE operan solo sobre unidades del workspace. Una unidad del sistema responde `SYSTEM_UNIT_READONLY`. `factor_to_base` debe ser mayor que cero. Nombre o abreviatura repetidos (sin distinguir mayúsculas, contra sistema y workspace) responden `DUPLICATE_NAME`.
- DELETE de una unidad que aparece en `conversions` de algún ingrediente activo, o en `items[].unit_id` de alguna receta activa (modelo `Recipe` en `app/models/recipe.py`, aunque sus endpoints aún no existan), responde `IN_USE`.

**Ingredientes (`/ingredients`).**
- Lista paginada con `PaginatedResponse` (`app/schemas/pagination.py`), filtros `q` (contiene, sin distinguir mayúsculas, sobre `name`) y `group`, orden por `name`.
- La respuesta de cada conversión incluye `unit_name` resuelto.
- En POST y PATCH, cada `unit_id` de `conversions` debe existir (sistema o del workspace) o responde `INVALID_REFERENCE`; un `unit_id` repetido en la lista también es `INVALID_REFERENCE`; `quantity_in_base` mayor que cero. PATCH con `conversions` reemplaza la lista completa.
- PATCH que cambia `base_unit` cuando el ingrediente tiene presentaciones activas (modelo `Presentation`) responde `IN_USE`.
- DELETE: si alguna receta activa tiene una línea `kind=ingredient` con ese `ref_id`, `IN_USE`. Si no, soft delete del ingrediente y de sus presentaciones activas.
- Nombre repetido en el workspace (sin distinguir mayúsculas, solo activos) responde `DUPLICATE_NAME`.

**Proveedores (`/suppliers`).** CRUD simple según el contrato, lista sin paginar ordenada por nombre, `DUPLICATE_NAME` igual que ingredientes. DELETE pone `supplier_id` nulo en las presentaciones activas del workspace que lo usaban y hace soft delete del proveedor.

**Servicio de conversión (`conversion_service.py`).** Función asíncrona `convert_to_base` que recibe el workspace id, una cantidad Decimal, un `unit_id` opcional y el documento `Ingredient`, y devuelve un Decimal en la `base_unit` del ingrediente, aplicando exactamente los 4 pasos de "Regla de conversión" del contrato, en ese orden. El error del paso 4 es `AppError` 422 `UNIT_NOT_CONVERTIBLE` con un detail que nombre la unidad, la unidad base y el ingrediente. Una unidad de otro workspace cuenta como inexistente (`INVALID_REFERENCE`). Agrega en el mismo archivo una segunda función `convert_between_base_units` que convierte una cantidad en un `unit_id` a una `BaseUnit` destino usando solo la tabla general (la usará el bloque B3 para subrecetas): mismo `base_unit` multiplica por el factor, distinto lanza `UNIT_NOT_CONVERTIBLE`, `unit_id` vacío devuelve la cantidad tal cual. Sin redondeos en ninguna de las dos.

**Reglas generales.** Todo endpoint de negocio usa `CurrentWorkspace` y filtra por `workspace_id` y `deleted_at` nulo; un id de otro workspace es 404 `NOT_FOUND` con `AppError`. Las listas excluyen borrados. Soft delete siempre con `soft_delete()`. Actualiza `updated_at` en cada PATCH.

**Criterios de aceptación.**
1. Los tests cubren como mínimo: siembra idempotente (sembrar dos veces deja 12 unidades del sistema); crear, listar, editar y borrar una unidad propia; `SYSTEM_UNIT_READONLY` al editar "taza"; `DUPLICATE_NAME`; los tres ejemplos de conversión del contrato (harina con taza=125 g y 2 tazas da 250; leche con 2 tazas da 480; harina sin conversión propia da `UNIT_NOT_CONVERTIBLE`); ingrediente con conversión a unidad inexistente da `INVALID_REFERENCE`; paginación y filtro `q`; borrar proveedor deja la presentación con `supplier_id` nulo; aislamiento: el usuario 2 recibe 404 al leer, editar o borrar un ingrediente, unidad o proveedor del usuario 1 y no los ve en sus listas.
2. Desde `backend/`: `./venv/bin/python -m pytest -q` pasa completo (hoy pasan 5 tests; deben seguir pasando) y `./venv/bin/ruff check . --exclude venv` no reporta errores.
3. Ningún archivo fuera del alcance listado fue modificado.

Si algo choca con el alcance (un test, el linter, un tipo, un campo que falta en un modelo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
