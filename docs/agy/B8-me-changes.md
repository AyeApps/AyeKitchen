Bloque B8. Corre en paralelo con I13 (no comparten archivos). Claude ya dejó: el contrato de `GET /me/changes` (sección "/me") y el índice `(workspace_id, updated_at)` en todos los modelos de negocio.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B8 del backend de AyeKitchen: `GET /me/changes`, cuándo cambió cada sección.** Relee "Reglas que no se rompen" en `GEMINI.md` y, en `docs/api-contract.md`, la tabla de `/me` y toda la sección "`GET /me/changes`".

**Contexto.** La app va a guardar las listas de cada pestaña y solo las va a volver a pedir si algo cambió. Para saberlo pide `/me/changes`, una respuesta muy pequeña con la fecha del último cambio de lo que muestra cada sección. Si una escritura no actualiza `updated_at`, la app nunca se entera de ese cambio: por eso este bloque también revisa todas las escrituras.

**Ya existe, no lo cambies:** los índices `(workspace_id, updated_at)` declarados en los modelos de `backend/app/models/`.

**Alcance, dentro de `backend/app/`:**
- `schemas/me.py`
- `services/changes_service.py` (nuevo)
- `api/v1/endpoints/me.py`
- `tests/test_changes.py` (nuevo)
- Cualquier archivo de `services/` solo si al revisar encuentras una escritura que no pone `updated_at` (punto 3), y solo en esa línea.

1. **Servicio** `services/changes_service.py` con una función async que, dado el `workspace_id`, devuelve las cinco marcas del contrato.
   - Por cada colección, una sola consulta: documentos con ese `workspace_id`, **sin** filtrar `deleted_at`, orden `updated_at` descendente, límite 1, y toma su `updated_at`. Para `units` solo cuentan las del workspace (las del sistema tienen `workspace_id` nulo y no se tocan).
   - Combina como dice la tabla del contrato: cada sección es el máximo de las marcas de sus colecciones; `null` si todas son `null`. Haz cada consulta de colección una sola vez aunque varias secciones la usen.
   - Ninguna consulta dentro de un ciclo por documento; son unas 11 consultas fijas.
2. **Endpoint** `GET /me/changes` en `api/v1/endpoints/me.py`, con `CurrentWorkspace`, y su schema de respuesta en `schemas/me.py` con los cinco campos `datetime | None`.
3. **Revisión de escrituras.** Recorre cada función de `services/` que cree, edite, borre (soft delete), agregue o quite pagos, agregue precios, o haga `update_many`, y confirma que deja `updated_at` en la hora del cambio en cada documento que toca. Donde falte, agrégalo en esa línea sin cambiar nada más. Escribe en tu resumen final la lista de funciones revisadas y cuáles corregiste.
4. **Pruebas** en `tests/test_changes.py`:
   - Un workspace nuevo devuelve las cinco en `null`.
   - Crear un ingrediente cambia `catalog`, `recipes` y `home`, y no `orders` ni `customers`.
   - Agregar un precio a una marca cambia `catalog` y `recipes`.
   - Editar una receta cambia `recipes`, `orders` y `home`, y no `catalog`.
   - Crear un pedido, agregarle un pago y borrarlo cambian `orders`, `customers` y `home` cada vez.
   - Renombrar un cliente cambia `customers` y `orders`.
   - Borrar (soft) un proveedor cambia `catalog`.
   - Crear una versión de costeo cambia `recipes`.
   - Para comparar "cambió", haz la escritura después de leer la marca y verifica que la nueva es mayor (si hace falta, espera unos milisegundos entre una y otra).
   - Aislamiento: escrituras de `auth_headers_user_2` no cambian ninguna marca de `auth_headers`.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 125 pruebas; ninguna existente cambia su resultado.
2. `git status` solo muestra los archivos del alcance (y, si corregiste escrituras, esas líneas de `services/`).

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
