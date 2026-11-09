Bloque K1. Corre en paralelo con B11. Claude ya dejó el paquete `ios/KitchenKit` (librería `KitchenDomain`) con las entidades, `KitchenData`, `KitchenCoding`, `Qty` y `SystemUnits`, y sus pruebas (`swift test`, 5 pasan). El archivo de casos `Fixtures/costing_cases.json` lo genera B11; si todavía no está, la prueba que lo usa se salta.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque K1 de AyeKitchen: el costeo de recetas en Swift, idéntico al del backend.** Lee `docs/backup-format.md`, en `docs/api-contract.md` las secciones "Regla de conversión", "`GET /recipes/{id}/cost`" (algoritmo incluido), "Versiones de costeo (B6b)" y "Por tanda o por pieza (B7)", y todo `ios/KitchenKit/Sources/KitchenDomain/`. La referencia exacta es el backend: `backend/app/services/costing_service.py`, `costing_snapshot.py`, `conversion_service.py` y `compute_price_staleness` en `presentation_service.py`. Léelos, no los modifiques.

**Contexto.** La app pasa a calcular todo en el teléfono. Este bloque traduce a Swift el costeo de recetas: debe dar **exactamente** los mismos centavos, banderas y textos que el backend, porque lo vamos a comparar contra casos generados por el backend.

**Ya existe, no lo cambies:** `Entities.swift`, `KitchenData.swift`, `SystemUnits.swift`, `Package.swift` y `BackupFormatTests.swift`.

**Alcance, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Costing/` (carpeta nueva, los archivos que necesites)
- `Tests/KitchenDomainTests/CostingTests.swift` (nuevo)
- `Tests/KitchenDomainTests/CostingFixtureTests.swift` (nuevo)

1. **Errores del dominio.** Un `enum DomainError: Error, Equatable` con un caso por código del contrato que el costeo puede producir (por ahora `unitNotConvertible(detail:)` con el mismo texto que el backend, por ejemplo "Define cuántos g pesa 1 taza de Harina de trigo").
2. **Índice de costeo** (el equivalente a la foto de B9): una estructura que se construye una vez desde `KitchenData` (sin lo borrado: `deletedAt` nulo) con unidades (sistema + negocio) por id, ingredientes, recetas, marcas por id y por ingrediente, el último precio de cada marca (por `recordedAt` y luego `createdAt`, el más reciente; precios borrados no cuentan) y la marca vigente de cada ingrediente (misma regla y mismo desempate que `get_current_presentation`).
3. **Conversión** como `convert_to_base` y `convert_between_base_units`: mismo orden de reglas y mismos errores.
4. **Costeo de una receta**, opcionalmente con una versión, con un `now: Date` explícito (para los precios viejos) y la zona horaria de `settings.timezone`. Devuelve una estructura `RecipeCost` con los mismos campos que la respuesta de `GET /recipes/{id}/cost` (incluidos `brand_source`, `version_id`, `version_name`, `suggested_price_per_yield_unit_cents`) y líneas con los mismos campos y el mismo orden. Todo con `Decimal`, sin `Double`; redondeo a centavos half-up **una vez por total** desde el valor sin redondear, como `round_to_cents`; `cost_per_yield_unit` con 6 decimales. Subrecetas recursivas con caché por llamada y la defensa de 10 niveles. `presentation_label` y `unit_name` con el mismo texto que el backend.
5. **Comparación de versiones**: base primero y luego cada versión por `createdAt`, con los campos de `GET /recipes/{id}/versions/compare`.
6. **Pruebas.**
   - `CostingTests.swift`: los ejemplos del contrato a mano (705 centavos; tres líneas de 0.4 → 1; taza de harina con equivalencia; taza de harina sin equivalencia → error con el texto exacto; versión con otra marca; marca fijada sin precio; subreceta).
   - `CostingFixtureTests.swift`: carga `Fixtures/costing_cases.json` con `Bundle.module` (si no existe, la prueba se marca como saltada con un mensaje, no falla). Por cada caso decodifica `data` con `KitchenCoding.decode`, y por cada `recipe_costs` calcula con el `now` del caso y compara contra `expected`: enteros y booleanos iguales; textos iguales; los campos decimales en texto (`quantity`, `quantity_in_base`, `cost_per_yield_unit`) se comparan **por valor** (`Qty.decimal`), no como texto. Al fallar, el mensaje dice el caso, la receta, la versión y el campo.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa sin advertencias nuevas (con el archivo de casos si ya existe; si no, la prueba de casos aparece como saltada).
2. Nada fuera de `ios/KitchenKit/Sources/KitchenDomain/Costing/` y los dos archivos de prueba cambia; `git status` solo muestra eso.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
