# Reglas del proyecto AyeKitchen

Costeo de recetas, ingredientes y pedidos para negocios de repostería. Parte del ecosistema Aye.

## Estructura

| Carpeta | Stack | Estado |
|---|---|---|
| `backend/` | FastAPI + Beanie (MongoDB), Python 3.12 | Esqueleto listo; los bloques B1–B4 se implementan por prompt |
| `web/` | Next.js 16 + React 19 + Tailwind v4 | Pendiente de diseño |
| `ios/` | SwiftUI (Swift 6), MVVM + `actor NetworkService` | Pendiente de diseño |
| `docs/api-contract.md` | — | **Contrato de la API. Fuente de verdad entre las tres capas** |

## Reglas que no se rompen

1. **El contrato manda.** Rutas, nombres de campos, códigos de error y formas de respuesta salen de `docs/api-contract.md`. Si algo del prompt choca con el contrato, detente y pregunta; no cambies el contrato por tu cuenta.
2. **Los modelos ya existen** en `backend/app/models/`. No renombres ni quites campos. Si necesitas un campo nuevo, detente y pregunta.
3. **Aislamiento por workspace.** Cada endpoint de negocio recibe `CurrentWorkspace` (`app/core/deps.py`) y cada query filtra por `workspace_id == str(workspace.id)` y `deleted_at == None`. Nunca filtres solo por id. Un recurso de otro workspace responde 404 `NOT_FOUND`.
4. **Dinero en centavos enteros** (`Cents`). Cantidades en `AyeDecimal`. Nunca `float`. Redondeo solo con `round_to_cents` (`app/models/base.py`), una vez por total mostrado, desde el valor sin redondear.
5. **Errores de negocio** con `AppError(status, detail, code)` (`app/core/errors.py`) y los `code` de la tabla del contrato. No inventes códigos nuevos sin preguntar.
6. **Capas como en aye-finance:** `api/v1/endpoints/<recurso>.py` (solo HTTP y serialización) → `services/<recurso>_service.py` (lógica y queries) → `models/`. Schemas Pydantic de entrada/salida en `schemas/<recurso>.py`. Los routers ya están montados en `app/api/v1/router.py`; no agregues ni quites prefijos.
7. **Soft delete** con `soft_delete()`. Nada se borra físicamente.
8. **Tests obligatorios** por bloque en `backend/app/tests/test_<recurso>.py`, usando los fixtures de `conftest.py` (`client`, `auth_headers`, `auth_headers_user_2`). Cada bloque incluye al menos un test de aislamiento entre los dos usuarios.
9. **Verificación antes de terminar**, desde `backend/`: `./venv/bin/python -m pytest -q` (todo pasa), la misma suite contra MongoDB real con `TEST_MONGODB_URL=mongodb://localhost:27018 ./venv/bin/python -m pytest -q` (contenedor `aye-kitchen-mongo-test`; si no responde, dilo en vez de saltarte el paso) y `./venv/bin/ruff check . --exclude venv` (sin errores).
10. **No dejes scripts auxiliares** (`fix_*.py`, `update_*.sh`…) en el repo; si usas uno, bórralo al terminar.
11. **Alcance cerrado.** Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera del alcance del prompt para satisfacerlo.
