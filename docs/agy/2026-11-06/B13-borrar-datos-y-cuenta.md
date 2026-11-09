Bloque B13. Rama `local-first`. Corre en paralelo con I29 (el iPhone ya sabe las rutas por el contrato). Claude dejó las dos rutas en `docs/api-contract.md`, sección `/me`. Decisión del usuario (2026-11-06): dos opciones, "Borrar mis datos de AyeKitchen" y "Eliminar mi cuenta Aye".

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B13 del backend de AyeKitchen: borrar los datos de una cuenta en el servidor.** Trabaja en la rama `local-first`. Relee "Reglas que no se rompen" en `GEMINI.md` y las filas `DELETE /me/data` y `DELETE /me/` de la sección `/me` de `docs/api-contract.md`. Como estilo: `api/v1/endpoints/me.py`, `api/v1/endpoints/backup.py` y `services/reference_service.py`.

**Contexto.** La app guarda todo en el teléfono; el servidor guarda respaldos e imágenes, y todavía conserva las colecciones viejas de negocio (B1–B10). La persona puede pedir borrar sus datos de AyeKitchen o eliminar su cuenta (Apple lo exige). En los dos casos lo de su workspace en este servidor debe desaparecer **de verdad** (borrado físico, no `deleted_at`).

**Alcance, dentro de `backend/app/`:**
- `services/account_service.py` (nuevo)
- `api/v1/endpoints/me.py` (agregar las dos rutas)
- `tests/test_account_deletion.py` (nuevo)

1. **Servicio** `erase_workspace_data(workspace_id)`: borra físicamente (`delete_many` o equivalente de Beanie, sin cargar documentos uno por uno) de cada modelo de negocio los documentos con ese `workspace_id`: `Unit` (solo los que tienen ese `workspace_id`; **nunca** los del sistema, que tienen `workspace_id` nulo), `Ingredient`, `Supplier`, `Presentation`, `PriceRecord`, `Recipe`, `CostVersion`, `Customer`, `Order`, `Expense`, `Backup` y `ReferenceImage`. Toma la lista de modelos de `app/db/mongodb.py` a mano en tu archivo (no cambies ese archivo). Después devuelve los ajustes del `Workspace` a los de fábrica (los valores por defecto del propio modelo: nombre, moneda, zona, margen, días de precio viejo) y lo guarda.
2. **Servicio** `delete_account(user, workspace)`: llama `erase_workspace_data`, y luego borra físicamente el `Workspace` y el `User` de Kitchen. No toca `RevokedToken` ni nada de aye-auth (de eso se encarga la app llamando a aye-auth después).
3. **Rutas** en `me.py`: `DELETE /me/data` → 204 con `erase_workspace_data` del workspace del usuario actual. `DELETE /me/` → 204 con `delete_account`. Decláralas con `status_code=204` y sin cuerpo, igual que las de borrar en `backup.py`. Que no choquen con `GET /me/` ni `/me/changes`.
4. **Pruebas:**
   - Con datos en varias colecciones (crea al menos ingrediente, proveedor, marca con precio, receta, cliente, pedido, gasto, una unidad propia, un respaldo y una imagen de referencia por las rutas existentes), `DELETE /me/data` → 204; después ninguna de esas colecciones tiene documentos de ese workspace (consulta los modelos directo, incluidos los que tenían `deleted_at`), las unidades del sistema siguen ahí, `GET /me/` responde 200 con los ajustes de fábrica, y `GET /backup/` y `GET /backup/references/` vienen vacíos.
   - Aislamiento: los datos de `auth_headers_user_2` siguen intactos después de que el usuario 1 borra.
   - `DELETE /me/data` dos veces → 204 las dos.
   - `DELETE /me/` → 204; el `Workspace` y el `User` de Kitchen de ese usuario ya no existen, y los datos del usuario 2 siguen intactos.
   - Si después de `DELETE /me/` el mismo token pide `GET /me/`, el comportamiento es el que ya tiene `deps.py` (auto-aprovisiona un usuario y negocio nuevos y vacíos): pruébalo y deja una nota en el test; **no cambies `deps.py`**.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 163 pruebas; ninguna existente cambia su resultado.
2. `git status` solo muestra tu alcance.

Si algo choca con el alcance (un modelo sin `workspace_id`, un test, el linter), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `ios/`.

### `FIN DEL PROMPT PARA GEMINI`
