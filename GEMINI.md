# Reglas del proyecto AyeKitchen

Costeo de recetas, ingredientes, clientes y pedidos para negocios de comida de cualquier tipo (no solo repostería: los textos hablan de recetas y productos, nunca de pasteles). Parte del ecosistema Aye.

## Estructura

| Carpeta | Stack | Estado |
|---|---|---|
| `backend/` | FastAPI + Beanie (MongoDB), Python 3.12 | B1–B4.1 hechos |
| `web/` | Next.js 16 + React 19 + Tailwind v4 | Carpeta vacía |
| `ios/aye-kitchen/` | SwiftUI (Swift 6), iOS 18+, MVVM + `actor NetworkService` | Esqueleto listo; las pantallas se implementan por prompt (bloques I…) |
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

## Reglas de iOS (`ios/aye-kitchen/`)

Las reglas 1, 10 y 11 de arriba también aplican aquí. Antes de tocar una pantalla lee `DESIGN.md` y `PRODUCT.md`; la referencia visual es el lienzo aprobado (https://claude.ai/artifact/4Vuy4h8YH51rTsEiiVhwia).

1. **El esqueleto ya existe y no se reescribe.** `Core/` (red, sesión, modelos, formatos), `Design/` (tokens y componentes) y `App/` los mantiene Claude. Si necesitas cambiar algo ahí (un campo nuevo en un modelo, un componente distinto), detente y pregunta. Tu trabajo vive en `Features/<Sección>/`.
2. **Red solo por `NetworkService.shared`** (`request` para respuestas con cuerpo, `requestNoContent` para 204). Nunca `URLSession` directo, nunca tokens a mano. Las rutas se copian del contrato tal cual (colecciones con `/` final). El JSON va en snake_case y el servicio ya convierte desde y hacia camelCase: los cuerpos de petición son structs `Encodable` con nombres en camelCase.
3. **Modelos de respuesta:** usa los de `Core/Models/` (`Ingredient`, `Presentation`, `Recipe`, `RecipeCost`, `Order`, `Page<T>`…). No declares otro modelo para una respuesta que ya tiene uno. Los structs nuevos de petición van en el archivo de la pantalla que los usa y se marcan `nonisolated` y `Sendable` (el proyecto usa MainActor por defecto).
4. **Errores:** `APIError`. Decide por `error.code` (los `code` del contrato: `IN_USE`, `DUPLICATE_NAME`, `UNIT_NOT_CONVERTIBLE`…) y muestra un mensaje en palabras de la cocina; si no hay un caso propio, `error.localizedDescription`. Una carga que falla muestra `ErrorStateView` con reintento. `APIError.unauthorized` no se maneja: la sesión ya regresa sola a la pantalla de entrar.
5. **MVVM:** cada pantalla con datos tiene su `@Observable final class <Pantalla>Model` en el mismo folder, con su estado de carga (cargando, cargado, error) y métodos `async`. La vista no llama a la red.
6. **Solo componentes y tokens del diseño.** Colores con los símbolos de Assets (`.accentFill`, `.accentInk`, `.inkPrimary`, `.inkMuted`, `.accentSoft`, `.warningText`…) y `.tint` para el naranja que se lee; nunca `Color(red:…)`, hex, `.orange` ni `.white`/`.black` sueltos. Espacios y radios con `Spacing` y `Radius`. Usa `PrimaryButtonStyle` (`.kitchenPrimary`), `.kitchenSecondary`, `AddToolbarButton`, `Chip`, `StatusChip`, `.softCard()`, `.sectionTitleStyle()`, `RowGroup`, `KitchenTextField`, `ErrorStateView`. Dinero siempre con `Money.format(cents:)` y `.monospacedDigit()`; cantidades con `Quantity.format` y `Quantity.parse`.
7. **Controles nativos** (DESIGN.md › Navigation): `NavigationStack` con título grande en pantallas principales e inline en detalle, `.sheet` para tareas cortas con "Cancelar" a la izquierda y la acción principal abajo, `Picker(.segmented)`, swipe actions, `.searchable`, `.refreshable`. Nada de botones flotantes.
8. **Letra grande obligatoria.** Solo estilos de Dynamic Type (`.font(.headline)`, `.body`…), nunca `.font(.system(size:))`. Medidas que deban crecer con el texto, con `@ScaledMetric`. Con `dynamicTypeSize.isAccessibilitySize`, lo que va lado a lado pasa a ir uno debajo del otro. Los montos nunca se truncan ni se encogen (sin `lineLimit(1)` ni `minimumScaleFactor` en dinero).
9. **iOS 18 es el mínimo.** Cualquier API de iOS 26 o posterior va dentro de `if #available`; si no hace falta, no la uses.
10. **Textos en español de México, de tú, palabras de la cocina** ("Te cuesta", "Te sugerimos cobrar", "Falta el precio de la nuez"). Sin emojis.
11. **Previews:** cada pantalla nueva tiene un `#Preview` con datos de ejemplo construidos en el mismo archivo (sin red), y uno con `.dynamicTypeSize(.accessibility3)`.
12. **Verificación antes de terminar**, desde `ios/aye-kitchen/`: `xcodebuild -project aye-kitchen.xcodeproj -scheme aye-kitchen -destination 'generic/platform=iOS Simulator' build` termina en `BUILD SUCCEEDED` sin advertencias nuevas en tus archivos. No toques `project.pbxproj`: los archivos nuevos dentro de `aye-kitchen/` entran solos al target.
