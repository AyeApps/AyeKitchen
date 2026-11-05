Bloque B6b.1. Correcciones de la auditoría de B6b. Corre en paralelo con I11 (no comparten archivos).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B6b.1 del backend de AyeKitchen: tres correcciones a las versiones de costeo.** Relee "Reglas que no se rompen" en `GEMINI.md`. B6b ya está hecho y commiteado; esto solo corrige detalles.

**Alcance, dentro de `backend/app/`:** `services/cost_version_service.py`, `schemas/cost_version.py` y `tests/test_cost_versions.py`.

1. **Aislamiento en las búsquedas de nombres.** En `serialize_cost_version` y en `list_cost_versions`, las búsquedas de `Ingredient` y `Presentation` por `_id` también deben filtrar por `workspace_id` (regla 3). No agregues filtro por `deleted_at`: un nombre de un ingrediente o una marca ya borrados se puede seguir mostrando.
2. **Mensaje de marca de otro ingrediente.** En `_validate_choices` quita la lógica que adivina el artículo ("el"/"la"): con "Leche" da "Esa marca no es de el leche". El detalle queda "Esa marca no es de " más el nombre del ingrediente tal cual (ej. "Esa marca no es de Harina de trigo"), y si el ingrediente no existe, "Esa marca no es de este ingrediente".
3. **Nombre vacío después de recortar.** Hoy "   " pasa `min_length=1` y se guarda una versión sin nombre. En `schemas/cost_version.py`, el `name` de crear y de editar usa `StringConstraints(strip_whitespace=True, min_length=1, max_length=60)` de Pydantic, para que un nombre de solo espacios responda el 422 estándar de FastAPI (el contrato dice que esos se quedan como están). No inventes un código nuevo.
4. **Pruebas** en `tests/test_cost_versions.py`: un nombre de solo espacios responde 422 y no crea la versión; el detalle del error de marca de otro ingrediente es exactamente "Esa marca no es de " más el nombre; y en aislamiento, que la lista de versiones de un usuario nunca traiga nombres de ingredientes o marcas del otro.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan. Hoy pasan 115 pruebas; ninguna existente cambia su resultado.
2. `git status` solo muestra los tres archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
