Bloque B11. Corre en paralelo con K1. Claude ya dejó: el modelo `Backup` (`backend/app/models/backup.py`) registrado en `DOCUMENT_MODELS`, el router vacío montado en `/backup`, la sección "/backup" y los códigos `BACKUP_*`/`INVALID_BACKUP` en `docs/api-contract.md`, y `docs/backup-format.md`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B11 del backend de AyeKitchen: respaldos del teléfono y casos de prueba del costeo.** Relee "Reglas que no se rompen" en `GEMINI.md`, la sección "/backup" y la tabla de errores de `docs/api-contract.md`, y todo `docs/backup-format.md`.

**Contexto.** La app pasa a ser local: guarda y calcula todo en el teléfono. El servidor solo autentica y guarda respaldos. Este bloque hace tres cosas: (1) guardar y devolver respaldos, (2) armar un primer respaldo con los datos que hoy están en las colecciones, para que la app los descargue una vez, y (3) generar un archivo de casos de prueba con los resultados del costeo actual, para que el costeo en Swift (bloque K1) dé exactamente lo mismo.

**Ya existe, no lo cambies:** `backend/app/models/backup.py`, su registro en `app/db/mongodb.py` y el montaje en `app/api/v1/router.py`.

**Alcance, dentro de `backend/app/`:**
- `api/v1/endpoints/backup.py` (llenar)
- `schemas/backup.py` (nuevo)
- `services/backup_service.py` (nuevo)
- `services/export_service.py` (nuevo)
- `tests/test_backup.py` (nuevo)
- `tests/test_kitchen_fixtures.py` (nuevo)
- y el archivo generado `ios/KitchenKit/Tests/KitchenDomainTests/Fixtures/costing_cases.json`

1. **Subir y bajar respaldos**, exactamente como la sección "/backup" del contrato:
   - `PUT /backup/` lee el cuerpo crudo (`await request.body()`), lo parsea como JSON solo para validar `schema_version` (entero, ≤ 1), `device_id` (texto no vacío) y `exported_at` (fecha ISO); si algo falla, 422 `INVALID_BACKUP`. Más de 10 MB → 413 `BACKUP_TOO_LARGE`. Guarda **los bytes originales** comprimidos con `gzip` en `Backup.data`, con `size_bytes` del original. Regla de conflicto y `force` como dice el contrato (409 `BACKUP_CONFLICT`, con la fecha del respaldo ajeno en el `detail`). Después de guardar, borra físicamente los respaldos del workspace más allá de los 5 más recientes. Responde 201 `BackupInfo`.
   - `GET /backup/` y `GET /backup/latest` como en el contrato. `latest` responde los bytes descomprimidos con `media_type="application/json"` sin volver a serializar.
   - Todo filtrado por el `workspace_id` del usuario.
2. **Exportar lo actual** (`GET /backup/export-current`, en `services/export_service.py`): arma el documento de `docs/backup-format.md` con todas las colecciones del workspace, incluidos los borrados, siguiendo la sección "Migración" al pie de la letra: ids actuales, unidades del sistema traducidas a `sys.*` por abreviatura (en `recipes[].items[].unit_id` y en `ingredients[].conversions[].unit_id`; las unidades del negocio van en `units` con su id), `recipe_name` en cada línea de pedido, `settings` desde el workspace, `device_id: "server-export"`, `photo_id: null`, cantidades como texto decimal sin exponente, fechas ISO en UTC con milisegundos y `Z`. Un número fijo de consultas (una por colección), sin consultas en ciclos.
3. **Casos de prueba del costeo** (`tests/test_kitchen_fixtures.py`). Una prueba que arma por la API, con `auth_headers`, varios escenarios y escribe `ios/KitchenKit/Tests/KitchenDomainTests/Fixtures/costing_cases.json` **solo si** existe la variable de entorno `KITCHEN_FIXTURES_OUT` con esa ruta (sin la variable, la prueba corre igual pero no escribe nada). Formato:
   `{generated_at, cases: [{name, now, data, recipe_costs: [{recipe_id, version_id, expected}]}]}` donde `now` es la hora en que se generó (ISO), `data` es la respuesta de `GET /backup/export-current` y `expected` es la respuesta exacta de `GET /recipes/{id}/cost` (con `?version_id=` cuando no es nulo).
   Escenarios mínimos, cada uno en un workspace nuevo o limpio: (a) el ejemplo del contrato (harina 1000 g a $23.50, línea de 300 g → 705); (b) conversión con equivalencia propia (taza = 125 g) y con la tabla general (taza de leche = 240 ml), más una unidad del negocio; (c) marca fijada, fijada sin precio, fijada borrada, y empate de fecha entre dos marcas; (d) versión que elige otra marca y versión con marca sin precio; (e) subreceta con unidad distinta (kg dentro de una receta que rinde g) y una receta que la usa; (f) extras, porciones, margen de la receta y margen del negocio; (g) un precio viejo (más de `price_stale_days`) y uno reciente; (h) una receta que rinde 12 pz (precio por pieza); (i) redondeo: tres líneas de 0.4 centavos. Cada escenario costea todas sus recetas, con y sin sus versiones.
4. **Pruebas** en `tests/test_backup.py`: subir y bajar devuelve los mismos bytes; se conservan solo 5; `INVALID_BACKUP` y `BACKUP_TOO_LARGE`; conflicto con otro `device_id` y sin `base_backup_id` correcto → 409, y con `force=true` pasa; el mismo dispositivo con su `base_backup_id` no choca; `latest` sin respaldos → 404; `export-current` traduce unidades a `sys.*`, trae los borrados y el `recipe_name`; aislamiento entre `auth_headers` y `auth_headers_user_2` en todas las rutas.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 143 pruebas; ninguna existente cambia su resultado.
2. Además corre una vez `KITCHEN_FIXTURES_OUT=../ios/KitchenKit/Tests/KitchenDomainTests/Fixtures/costing_cases.json ./venv/bin/python -m pytest -q app/tests/test_kitchen_fixtures.py` desde `backend/` y deja el archivo generado.
3. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
