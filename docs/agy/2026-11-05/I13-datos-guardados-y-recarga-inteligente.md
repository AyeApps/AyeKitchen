Bloque I13. Corre en paralelo con B8 (no comparten archivos). Claude ya dejó en `Core/`: `Core/Sync/ResponseCache.swift`, `Core/Sync/ChangeTracker.swift`, `NetworkService.requestCaching` / `cached`, y en `SessionStore` la cuenta activa de la caché, entrar sin red con la copia guardada y borrar todo al cerrar sesión. Para probar la recarga inteligente contra producción, B8 tiene que estar desplegado; sin B8, `/me/changes` falla y la app se queda con los datos que tiene (y la red de seguridad de 30 min recarga).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I13 de AyeKitchen iOS: datos guardados en el teléfono y recarga solo cuando algo cambió.** Relee "Reglas de iOS" en `GEMINI.md`, la sección "`GET /me/changes`" de `docs/api-contract.md` y los comentarios de `Core/Sync/ChangeTracker.swift`, `Core/Sync/ResponseCache.swift` y de `requestCaching` y `cached` en `Core/Network/NetworkService.swift`.

**Contexto.** Hoy cada pestaña pide sus datos una sola vez al abrirse, no los guarda, y la de Recetas vacía no deja jalar para refrescar: una usuaria no vio recetas que ya existían. Queremos:
- Al abrir la app, ver al instante lo último que se vio, aunque no haya red.
- Al volver a una pestaña que ya tiene datos, no recargar si nada cambió (para no gastar datos).
- Jalar para refrescar siempre recarga.

**Ya existe en `Core/`, úsalo y no lo cambies:** `ChangeTracker.shared` con `reloadIfStale(_:reload:)` y `forceReload(_:reload:)` y sus secciones `.home`, `.orders`, `.recipes`, `.catalog`, `.customers`; `NetworkService.shared.requestCaching(_:query:)` (GET que guarda en disco) y `NetworkService.shared.cached(_:query:)` (lee lo guardado, sin red). La caché ya es por cuenta y se borra al cerrar sesión: no hagas nada de eso.

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/`:** los Model y View de las cinco listas: `Home/HomeModel.swift`, `Home/HomeView.swift`, `Orders/OrdersModel.swift`, `Orders/OrdersView.swift`, `Recipes/RecipesModel.swift`, `Recipes/RecipesView.swift`, `Catalog/CatalogModel.swift`, `Catalog/CatalogView.swift`, `Customers/CustomersModel.swift`, `Customers/CustomersView.swift`. En `HomeView.swift` no toques el menú de la cuenta (`AccountMenu`, con su botón DEBUG).

1. **Qué se guarda.** Solo las peticiones que arman la primera pantalla de cada lista, sin búsqueda: en cada Model, esas llamadas pasan de `request` a `requestCaching` con exactamente la misma ruta y query. Búsquedas, páginas siguientes, detalles y escrituras siguen con `request`. En Inicio y Pedidos son varias peticiones en paralelo: todas las de la primera pantalla se guardan.
2. **Al abrir la pestaña sin datos en memoria.**
   - Primero intenta `cached` con esas mismas rutas. Si están todas, muéstralas de inmediato con el estado cargado (sin indicador de carga) y luego llama `reloadIfStale` de su sección para actualizar en silencio si hace falta.
   - Si no hay copia guardada, carga como hoy (con indicador) dentro de `forceReload` de su sección.
3. **Al volver a una pestaña que ya tiene datos** (`.task` u `.onAppear` de la vista) y **al regresar la app a primer plano** (`scenePhase` pasa a `.active`, solo la pestaña visible): `reloadIfStale` de su sección. Nunca muestres el indicador de carga ni borres lo que ya se ve por esto.
4. **Jalar para refrescar**, en la lista con datos **y también en la pantalla vacía** (hoy Recetas vacía no lo tiene): `forceReload` de su sección.
5. **Recargar en silencio.** Cada Model tiene un método que vuelve a pedir la primera pantalla sin pasar por el estado de carga, reemplaza los datos solo si la respuesta llegó bien y devuelve `true`/`false`. Es el que se le pasa a `reloadIfStale` y `forceReload`. Si falla y ya había datos, se quedan los datos (sin pantalla de error). Si falla y no había nada, la pantalla de error con reintento de hoy.
6. **Búsqueda activa.** Si hay texto de búsqueda, la pestaña se comporta como hoy y no usa la caché ni el `ChangeTracker`. Al borrar la búsqueda, vuelve a la primera pantalla (de la caché si está).
7. **Lo que ya recarga después de guardar** (crear o borrar desde la misma pantalla) se queda igual.
8. Los previews existentes siguen funcionando con sus datos de ejemplo (no usan red ni caché).

**Criterios de aceptación.**
1. Con datos ya vistos, cerrar la app por completo, quitar la red y abrirla: Inicio, Pedidos, Recetas y Catálogo muestran lo último que se vio.
2. Con red, cambiar entre pestañas no vuelve a pedir las listas si nada cambió (solo `/me/changes`).
3. Crear una receta desde otro dispositivo o desde la API y volver a la pestaña Recetas: aparece sin cerrar la app.
4. Recetas vacía deja jalar para refrescar.
5. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
