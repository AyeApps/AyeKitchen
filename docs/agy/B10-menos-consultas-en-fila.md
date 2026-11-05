Bloque B10. Corre en paralelo con I14a e I14b. Medido en producción el 2026-11-05 después de B9: `GET /me/` 0.51 s (una petición que casi no hace nada) y `GET /recipes/` 1.0 s. Cada consulta a Atlas cuesta ~60 ms y hoy varias van una detrás de otra.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B10 del backend de AyeKitchen: hacer en paralelo las consultas que hoy van una tras otra.** Relee "Reglas que no se rompen" en `GEMINI.md`. **Las respuestas de todas las rutas deben quedar idénticas**; solo cambia el orden y número de consultas.

**Contexto.** Cada consulta a MongoDB en producción tarda ~60 ms. Toda petición pasa por la autenticación, que hoy hace tres consultas en fila: buscar el token revocado (`RevokedToken`), el usuario (`User.get`) y su workspace. Eso solo ya cuesta ~180 ms en cada pantalla. La lista de recetas además hace en fila: las recetas, luego tres búsquedas de nombres (ingredientes, subrecetas, unidades), luego el workspace y luego la foto de costeo (B9), cuando la foto ya trae esos nombres.

**Alcance, dentro de `backend/app/`:**
- `core/deps.py`
- `services/recipe_service.py` (solo `list_recipes`)
- `services/costing_snapshot.py` (solo si hace falta para recibir el `Workspace` ya cargado)
- `api/v1/endpoints/recipes.py` (solo pasar el `Workspace` que ya da la dependencia)
- `tests/test_deps.py` (nuevo)
- `tests/test_recipes.py` (solo agregar pruebas)

1. **Autenticación en una sola vuelta.** En `core/deps.py`, después de validar el JWT (sin cambios), lanza **a la vez** con `asyncio.gather` las tres consultas: el token revocado por `jti`, el usuario por `sub` y el workspace cuyo dueño es ese `sub` (la misma consulta que hoy hace `get_current_workspace`). FastAPI ya cachea una dependencia dentro de la misma petición: haz que `CurrentUser` y `CurrentWorkspace` salgan de esa misma vuelta (por ejemplo una dependencia interna que devuelve los dos y que las otras dos usan), para que una ruta que pida ambos no consulte dos veces. Todo lo demás se queda igual, en el mismo orden de decisión:
   - token revocado → el mismo 401 de hoy (aunque las otras dos consultas ya hayan vuelto);
   - usuario que no existe → se auto-aprovisiona como hoy y se vuelve a leer;
   - workspace que no existe → se crea como hoy.
   No agregues cachés entre peticiones.
2. **Lista de recetas** (`list_recipes`):
   - La consulta de la página de recetas (con su conteo) y la carga de la foto de costeo van **a la vez**.
   - `load_costing_snapshot` recibe el `Workspace` que ya trae la dependencia, para no volver a buscarlo. El endpoint lo pasa al servicio.
   - Los nombres de ingredientes, subrecetas y unidades de cada línea salen de la foto, que ya los tiene. Solo para los ids que no estén en la foto (ingrediente o receta borrados) haz **una** consulta de respaldo por colección con esos ids, filtrando por `workspace_id`, para que el nombre se siga mostrando como hoy.
   - Las demás rutas de recetas no cambian en este bloque, salvo pasar el `Workspace` a `calculate_recipe_cost` donde el endpoint ya lo tiene (`GET /recipes/{id}/cost`), para que la foto no lo busque.
3. **Pruebas.**
   - En `tests/test_deps.py`: un token revocado sigue dando 401; un usuario nuevo se auto-aprovisiona y su workspace se crea; con `monkeypatch`, cuenta que una petición a `GET /me/` hace exactamente una llamada a cada una de las tres consultas (no dos al usuario ni dos al workspace).
   - En `tests/test_recipes.py` (agregar, no modificar las existentes): la lista sigue trayendo `ref_name` y `unit_name` correctos en una receta con subreceta y unidades; y una receta cuya línea apunta a un ingrediente borrado a mano en la base (soft delete directo) sigue mostrando su nombre.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 138 pruebas; ninguna existente cambia su resultado ni se modifica.
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
