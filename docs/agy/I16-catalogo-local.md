Bloque I16. Rama `local-first`. Corre en paralelo con I18 (no comparten archivos). Después van I17 (Recetas) y luego I19 (Inicio).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I16 de AyeKitchen iOS: el Catálogo con datos locales.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` y sigue **todas** las reglas de `docs/agy/_pantallas-locales.md`. Las reglas y consultas del catálogo están en `ios/KitchenKit/Sources/KitchenDomain/Rules/CatalogRules.swift` y `CatalogQueries.swift` (y la marca vigente, precios viejos y `cost_per_base_unit` en `Costing/`).

**Contexto.** La app ya no le pide el catálogo al servidor: lo lee y lo guarda en el teléfono con `LocalStore`. Este bloque cambia todas las pantallas del Catálogo para que funcionen así, sin cambiar lo que la usuaria ve ni los textos.

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/Catalog/`:** todos sus archivos (`CatalogView`, `CatalogModel`, `IngredientDetailView`, `IngredientFormView`, `IngredientBrandsSection`, `BrandDetailView`, `BrandDetailModel`, `BrandFormView`, `RecordPriceModel`, `SuppliersView`, `BaseUnitHelpSheet` y los que haya). Y, por la regla 4 de `_pantallas-locales.md`, las llamadas de una línea a tus vistas desde `Features/Recipes/` y `Features/Home/`.

1. **Lista del catálogo:** ingredientes por grupo con búsqueda, su resumen de marcas ("3 marcas · Usamos Selecta · $23.50 el kg", "Sin marcas todavía"), borrar con deslizar (con el aviso de `IN_USE` de hoy), y el acceso a Proveedores. Sin paginación (todo está en memoria).
2. **Ingrediente:** detalle (marcas y precios primero, "Cómo lo mides", equivalencias, notas) y formulario de crear/editar, incluida la sección "Primera marca" al crear (crea el ingrediente y su primera marca con precio en una sola escritura, o en dos `mutate` seguidos; si la segunda falla, el mensaje de hoy) y el `initialName` que usa el selector de recetas.
3. **Marcas:** la sección de marcas del ingrediente, el detalle de una marca (con historial de precios y "Registrar precio") y el formulario de crear/editar marca con su unidad de paquete.
4. **Proveedores:** lista, crear, editar y borrar.
5. **Unidades:** donde hoy se piden `/units/` (menús de unidad, equivalencias), usa las unidades de KitchenKit (sistema + negocio).
6. **Navegación por id:** `IngredientDetailView(ingredientId:)`, `IngredientFormView(mode:)` con `.create` / `.edit(ingredientId:)`, `BrandDetailView(presentationId:)`, `BrandFormView` con el ingrediente por id. Ajusta las llamadas de `Features/Recipes/` (detalle de receta, selector de ingrediente, hoja de marcas) y `Features/Home/` a estas firmas, una línea cada una, sin cambiar más de esos archivos.

**Criterios de aceptación.**
1. En `Features/Catalog/` no queda ningún `NetworkService`, `requestCaching`, `cached`, `ChangeTracker` ni tipo `Remote…`.
2. Con `LocalStore.preview()`, los previews muestran el catálogo de ejemplo (incluida "Sin marcas todavía" en Chispas y "Precio viejo" en Tres Estrellas).
3. Crear un ingrediente con primera marca, agregarle otra marca, registrar un precio y borrar una marca fijada en una receta (aviso `IN_USE`) funcionan en el simulador sin red.
4. Build sin advertencias nuevas; `git status` solo muestra tu alcance (y las líneas de llamada ajustadas).

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Orders/` y `Features/Customers/`.

### `FIN DEL PROMPT PARA GEMINI`
