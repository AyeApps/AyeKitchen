Bloque B9. Solo backend. Medido en producción el 2026-11-05 con 3 recetas: `GET /recipes/` 4.3 s, `GET /recipes/{id}/cost` 2.3 s, `GET /recipes/{id}/versions/compare` 3.5 s, contra ~0.45 s de una lista simple. Cada consulta a Atlas cuesta ~50–60 ms desde el VPS y el costeo hace varias por línea de receta.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B9 del backend de AyeKitchen: que el costeo lea todo de una vez en lugar de consultar por cada línea.** Relee "Reglas que no se rompen" en `GEMINI.md` y, en `docs/api-contract.md`, el algoritmo de `GET /recipes/{id}/cost`, "Versiones de costeo (B6b)" y "Regla de conversión". **El resultado de todas las rutas debe quedar idéntico**; solo cambia cuántas consultas se hacen.

**Contexto.** En producción cada consulta a MongoDB tarda unos 50–60 ms. Hoy `costing_service` hace varias consultas por cada línea de cada receta (el ingrediente, la unidad, la marca fijada o elegida, su último precio, la marca vigente con sus precios, el proveedor, la subreceta, el workspace) y `conversion_service` pide la unidad otra vez. Con 3 recetas, la lista de recetas tarda 4.3 s y el costo de una receta 2.3 s. Un workspace de un negocio de comida tiene pocos cientos de documentos: cabe leerlos de una vez.

**Alcance, dentro de `backend/app/`:**
- `services/costing_snapshot.py` (nuevo)
- `services/costing_service.py`
- `services/conversion_service.py` (solo agregar funciones; las actuales no cambian su firma)
- `services/recipe_service.py` (solo `list_recipes`)
- `services/cost_version_service.py` (solo `compare_cost_versions`)
- `services/order_service.py` (solo donde llama a `calculate_recipe_cost`)
- `tests/test_costing_snapshot.py` (nuevo)

1. **Foto de costeo** en `services/costing_snapshot.py`: una estructura con todo lo que necesita el costeo de un workspace y una función async que la carga con un número fijo de consultas, sin ciclos de consultas:
   - el `Workspace`;
   - todas las unidades del sistema y del workspace, por id;
   - los ingredientes activos del workspace, por id;
   - las recetas activas del workspace, por id;
   - las presentaciones activas del workspace, por id y agrupadas por ingrediente;
   - el `PriceRecord` activo más reciente de cada presentación (por `recorded_at` y luego `created_at`, igual que hoy), en **una** consulta (agregación con orden y agrupado por `presentation_id`, o una sola consulta ordenada que se recorre en memoria);
   - los proveedores activos del workspace, por id.
   Todas filtran por `workspace_id` y `deleted_at` nulo (las unidades del sistema, por `workspace_id` nulo).
   La foto da, sin tocar la base: la marca vigente de un ingrediente (misma regla que `get_current_presentation`), el último precio de una presentación, y la conversión a la unidad base (misma regla que `convert_to_base` y `convert_between_base_units`, con los mismos errores `UNIT_NOT_CONVERTIBLE` y el mismo texto).
2. **Conversión.** En `conversion_service.py` agrega versiones que reciben el mapa de unidades en lugar de consultar, y haz que las funciones async actuales las usen por dentro después de pedir la unidad, para que la regla viva en un solo lugar.
3. **Costeo.** `calculate_recipe_cost` gana el parámetro opcional `snapshot`. Si no viene, carga uno al empezar. Todo el cálculo (líneas de ingrediente, marca elegida por versión, fijada o vigente, proveedor de la etiqueta, staleness, subrecetas recursivas con su caché, conversión) usa la foto y **no hace ninguna consulta**. `_compute_ingredient_line_cost` y `_compute_subrecipe_unrounded_cost` pasan a recibir la foto. Los textos, el redondeo, `missing_price`, `price_is_stale`, `brand_source`, la defensa de 10 niveles y el orden de las líneas no cambian.
4. **Quien costea varias recetas carga una sola foto y la pasa:**
   - `list_recipes`: una foto para toda la página (y la misma `cache` de subrecetas).
   - `compare_cost_versions`: una foto para la base y todas las versiones.
   - `create_order` y `update_order`: una foto por petición, solo si alguna línea necesita costo.
5. **Pruebas** en `tests/test_costing_snapshot.py`:
   - **Sin consultas por línea:** arma un workspace con 3 recetas (una con subreceta, una con marca fijada, una con versión). Luego, con `monkeypatch`, haz que `Ingredient.find_one`, `Recipe.find_one`, `Presentation.find_one`, `Supplier.find_one`, `Unit.get`, `PriceRecord.find_one` y las funciones `get_current_presentation` y `get_latest_price` lancen un error si se llaman, y verifica que `GET /recipes/`, `GET /recipes/{id}/cost`, `GET /recipes/{id}/cost?version_id=` y `GET /recipes/{id}/versions/compare` responden 200 con los mismos valores que antes de parchear.
   - La marca vigente de la foto coincide con `get_current_presentation` en un caso con empate de fecha.
   - Una unidad no convertible da el mismo `UNIT_NOT_CONVERTIBLE` y el mismo texto con y sin foto.
   - Aislamiento: la foto de un workspace no trae datos del otro usuario.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 134 pruebas; **ninguna existente cambia su resultado ni se modifica** (son la garantía de que el costo quedó igual).
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
