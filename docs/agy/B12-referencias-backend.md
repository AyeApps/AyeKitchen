Bloque B12. Rama `local-first`. Corre en paralelo con K4. Claude ya dejó la sección "Imágenes de referencia (B12)" en `docs/api-contract.md` y la sección "Referencias" en `docs/backup-format.md`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B12 del backend de AyeKitchen: guardar las imágenes de referencia del teléfono.** Trabaja en la rama `local-first`. Relee "Reglas que no se rompen" en `GEMINI.md`, la sección "Imágenes de referencia (B12)" y la tabla de errores de `docs/api-contract.md`, y la sección "Referencias" de `docs/backup-format.md`. Como estilo, `services/backup_service.py` y `api/v1/endpoints/backup.py` (B11).

**Contexto.** La app guarda imágenes de referencia opcionales (empaque de una marca, pastel terminado, ticket). Sus datos van en el respaldo; sus bytes se suben uno por uno a estas rutas. El servidor no los interpreta.

**Alcance, dentro de `backend/app/`:**
- `models/reference_image.py` (nuevo): documento con `workspace_id` (indexado junto con el id de la imagen, único por workspace), `ref_id`, `content_type`, `sha256`, `size_bytes`, `data` (bytes) y `updated_at`.
- `app/db/mongodb.py`: solo registrar el modelo nuevo en `DOCUMENT_MODELS`.
- `services/reference_service.py` (nuevo), `schemas/backup.py` (agregar lo que haga falta), `api/v1/endpoints/backup.py` (agregar las rutas, **declaradas antes** de cualquier ruta con parámetro que pueda chocar).
- `tests/test_references.py` (nuevo).

1. Las cuatro rutas exactamente como el contrato. `PUT` lee el cuerpo crudo; valida tamaño (≤ 2 MB → si no `BACKUP_TOO_LARGE`), `Content-Type` (`image/jpeg` o `image/heic` → si no `INVALID_BACKUP`), el `id` (1–64 caracteres `[A-Za-z0-9_-]` → si no `INVALID_BACKUP`) y que `sha256` coincida con el SHA-256 hex de los bytes (→ si no `INVALID_BACKUP`). Crea o reemplaza (un documento por `workspace_id` + `ref_id`). `GET /{id}` responde los bytes con su `media_type`. `DELETE` borra físicamente (son copias) y responde 204 aunque no exista.
2. Todo filtrado por el `workspace_id` del usuario. La lista no incluye los bytes.
3. **Pruebas:** subir y bajar devuelve los mismos bytes y tipo; reemplazar cambia `sha256`; la lista trae lo esperado sin bytes; tamaño, tipo, id y huella inválidos; borrar dos veces da 204; aislamiento entre `auth_headers` y `auth_headers_user_2` (no ve, no baja, no borra las del otro, y el mismo `id` en dos workspaces son imágenes distintas).

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 152 pruebas; ninguna existente cambia su resultado.
2. `git status` solo muestra tu alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `ios/KitchenKit/`.

### `FIN DEL PROMPT PARA GEMINI`
