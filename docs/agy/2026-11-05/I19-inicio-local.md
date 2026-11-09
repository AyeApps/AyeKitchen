Bloque I19. Rama `local-first`. Corre en paralelo con I20 (no comparten archivos). Es la última pantalla que todavía usa la red.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I19 de AyeKitchen iOS: Inicio con datos locales.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` y sigue **todas** las reglas de `docs/agy/_pantallas-locales.md`. Las consultas están en `ios/KitchenKit/Sources/KitchenDomain/Rules/`: `OrderRules.swift` (`listOrders`), `RecipeQueries.swift` (`listRecipes`, con costo y `complete`) y `CatalogQueries.swift` (`stalePresentations`). Catálogo, Pedidos, Clientes y Recetas ya son locales: úsalos como referencia.

**Contexto.** Inicio es la última pantalla que le pide datos al servidor. Este bloque la pasa a `LocalStore`, sin cambiar lo que la usuaria ve ni los textos.

**Alcance:** `ios/aye-kitchen/aye-kitchen/Features/Home/HomeModel.swift` y `HomeView.swift`. En `HomeView.swift` **no toques** `AccountMenu` (el menú de la cuenta con su botón DEBUG): otro bloque y Claude lo cambian.

1. **Lo mismo que hoy, desde el teléfono:** saludo y conteo de entregas de la semana; "Lo que sigue" (el próximo pedido pendiente o en proceso); "Esta semana" (pedidos por entregar de los próximos 7 días); "Por revisar" (recetas activas con precios faltantes y marcas con precio viejo que usa alguna receta, como hoy). Mismos filtros, orden y límites que las peticiones actuales de `HomeModel` (lee sus `query` para respetarlos).
2. Sin `NetworkService`, `requestCaching`, `cached` ni `ChangeTracker`; sin estado de carga ni reintento. Recalcula cuando cambie `LocalStore.shared.revision` (el costeo de "Por revisar" una vez por revisión, no en cada dibujo).
3. Las filas abren `OrderDetailView(orderId:)`, `RecipeDetailView(recipeId:)`, `BrandDetailView(presentationId:)` y `OrderFormView(.create)`, como ya están.
4. Previews con `LocalStore.preview()`.

**Criterios de aceptación.**
1. En `Features/Home/` no queda ningún `NetworkService`, `requestCaching`, `cached`, `ChangeTracker` ni tipo `Remote…`.
2. Con los datos de ejemplo, Inicio muestra el pedido de mañana en "Lo que sigue", los de esta semana, las Galletas en "Por revisar" (les falta el precio de las chispas) y Tres Estrellas con precio viejo.
3. Crear un pedido desde Inicio lo hace aparecer en "Esta semana" sin recargar nada.
4. Build sin advertencias nuevas; `git status` solo muestra los dos archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Backup/`.

### `FIN DEL PROMPT PARA GEMINI`
