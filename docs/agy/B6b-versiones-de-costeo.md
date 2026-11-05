Bloque B6b. Corre en paralelo con B6a e I9. Claude ya dejó el esqueleto: el modelo `CostVersion` en `backend/app/models/cost_version.py`, registrado en `DOCUMENT_MODELS`, y la sección "Versiones de costeo (B6b)" del contrato. I10 espera a que B6b esté auditado.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B6b del backend de AyeKitchen: versiones de costeo de una receta.** Relee "Reglas que no se rompen" en `GEMINI.md` y, en `docs/api-contract.md`, toda la sección "Versiones de costeo (B6b)", las filas de `/recipes` marcadas con B6b y los campos `brand_source`, `version_id` y `version_name` de `GET /recipes/{id}/cost`.

**Contexto.** La usuaria quiere comparar cuánto le sale una receta con distintas marcas ("Con Selecta", "Con Tres Estrellas") sin duplicar la receta. Una versión solo guarda qué marca usar por ingrediente; todo lo demás sale de la receta. La versión base es la receta tal cual y no se guarda.

**Ya existe, no lo cambies:** el modelo `CostVersion` y `CostVersionChoice` en `backend/app/models/cost_version.py` y su registro en `app/db/mongodb.py`. Tampoco cambies los modelos de receta ni de presentación.

**Alcance, dentro de `backend/app/`:**
- `schemas/cost_version.py` (nuevo)
- `services/cost_version_service.py` (nuevo)
- `tests/test_cost_versions.py` (nuevo)
- `api/v1/endpoints/recipes.py`
- `schemas/recipe.py`
- `services/costing_service.py`
- `services/recipe_service.py`
- `services/presentation_service.py` (solo `delete_presentation`)

1. **Schemas** en `schemas/cost_version.py`: entrada para crear (`name` de 1 a 60, `choices` opcional), para editar (parcial; `choices` reemplaza la lista), la respuesta `CostVersion` del contrato (cada elección con `ingredient_name` y `brand` resueltos) y la fila de comparación. En `schemas/recipe.py`, `CostLineResponse` gana `brand_source` opcional (texto "version", "recipe" o "current") y `RecipeCostResponse` gana `version_id` y `version_name` opcionales.
2. **Servicio** `services/cost_version_service.py` con listar, crear, editar, borrar (soft delete) y buscar una versión de una receta. Toda búsqueda filtra por `workspace_id`, `recipe_id` y `deleted_at` nulo; la receta se obtiene con `get_recipe` de `recipe_service` (404 si no existe). Una versión que no existe o es de otra receta → 404 `NOT_FOUND` con "Versión no encontrada". Validaciones, al crear y al editar:
   - `name` recortado. Si es "Base" (sin distinguir mayúsculas) o repite el de otra versión activa de la misma receta (sin distinguir mayúsculas, excluyéndose a sí misma al editar) → 409 `DUPLICATE_NAME` con "Ya tienes una versión con ese nombre".
   - Cada `ingredient_id` debe estar en una línea `kind=ingredient` de la receta y no repetirse en `choices`; cada `presentation_id` debe ser una presentación activa del mismo workspace y de ese ingrediente. Si no → 422 `INVALID_REFERENCE` con un detalle en palabras ("Esa marca no es de la harina de trigo").
3. **Costeo** en `services/costing_service.py`:
   - `calculate_recipe_cost` gana un parámetro opcional `version` (un `CostVersion` o nada). Con versión, para cada línea directa de ingrediente busca la elección de ese ingrediente y se la pasa a `_compute_ingredient_line_cost` como un nuevo parámetro opcional con el id de la presentación elegida.
   - En `_compute_ingredient_line_cost`, el orden es el del contrato: primero la elegida por la versión si está activa y es de ese ingrediente; si no, la fijada en la línea; si no, la vigente. Una elegida activa sin precio deja la línea en costo 0 y sin caer a otra marca, igual que hoy con una fijada. `_IngredientCostResult` gana la fuente de la marca.
   - Cada línea de ingrediente llena `brand_source` ("version", "recipe" o "current"; nulo si no hubo marca). `pinned` es verdadero cuando la fuente es "version" o "recipe". Las líneas de subreceta llevan `brand_source` nulo y se costean sin versión, como hoy.
   - La respuesta llena `version_id` y `version_name` cuando hay versión. Con versión, no guardes el costo de la receta principal en `cache` (solo las subrecetas).
   - Sin versión, todo debe dar exactamente lo mismo que hoy.
4. **Endpoints** en `api/v1/endpoints/recipes.py`, en el mismo router:
   - `GET /{id}/cost` gana el query opcional `version_id`; si viene, busca la versión con el servicio (404 si no) y costea con ella.
   - `GET /{id}/versions/`, `POST /{id}/versions/` (201), `PATCH /{id}/versions/{version_id}`, `DELETE /{id}/versions/{version_id}` (204).
   - `GET /{id}/versions/compare`: la base primero (`version_id` nulo, nombre "Base") y luego cada versión por `created_at`. Usa un solo `cache` para todo el cálculo.
   - Declara `compare` antes de las rutas con `{version_id}`.
5. **Receta** en `services/recipe_service.py`: cuando `update_recipe` cambia `items`, quita de las versiones activas de esa receta las elecciones de ingredientes que ya no están en una línea de ingrediente. `delete_recipe` hace soft delete de sus versiones después de borrar la receta.
6. **Presentación** en `services/presentation_service.py`, solo `delete_presentation`: después del soft delete, quita esa presentación de las elecciones de todas las versiones activas del workspace. El chequeo `IN_USE` actual se queda igual. No toques `list_stale_presentations` ni ninguna otra función.
7. **Pruebas** en `tests/test_cost_versions.py`, con datos como los del ejemplo del contrato (harina 1000 g a $23.50 y otra marca de harina 1000 g a $30.00, receta con 300 g):
   - CRUD de versiones; nombre repetido y "Base" → `DUPLICATE_NAME`.
   - Elección con un ingrediente que no está en la receta, repetido, o con marca de otro ingrediente → `INVALID_REFERENCE`.
   - `/cost` sin versión da 705 y `brand_source` "current"; con la versión que elige la de $30.00 da 900, `brand_source` "version", `pinned` verdadero, y `version_name` lleno.
   - Una línea fijada en la receta y sin elección en la versión sale con `brand_source` "recipe".
   - Una elegida sin precio da `missing_price` y costo 0.
   - `compare` devuelve la base y las versiones en orden, con los mismos `batch_cost_cents` que `/cost`.
   - Quitar el ingrediente de la receta lo quita de las elecciones; borrar la presentación la quita y el costo cae a la vigente; borrar la receta borra sus versiones.
   - `version_id` de otra receta → 404.
   - Aislamiento: `auth_headers_user_2` no ve, no edita, no borra versiones de `auth_headers`, ni puede elegir sus marcas.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 100 pruebas; ninguna existente cambia su resultado (en especial `test_costing.py` y `test_recipes.py`).
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
