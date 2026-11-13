Bloque I33. Rama `main`. Corre en paralelo con K7 (K7 solo toca `ios/KitchenKit/`). Pedido del usuario (2026-11-13): en el catálogo poder buscar y filtrar, ver lo de una tienda, filtrar por precio y ordenar por ingrediente. Claude ya dejó en KitchenKit (`Rules/CatalogListQueries.swift`) los tipos `CatalogFilter`, `CatalogSort`, `CatalogStoreFilter`, `CatalogPriceFilter`, `CatalogListItem` y las funciones `catalogList(_:now:)` y `catalogGroups()`; K7 llena su lógica.

### PROMPT PARA GEMINI — copiar desde aquí

**Bloque I33 de AyeKitchen: búsqueda, filtros y orden en la pantalla Catálogo.** Trabaja en la rama `main`. Sigue `GEMINI.md`, `DESIGN.md` y `docs/agy/_pantallas-locales.md` (sobre todo sus reglas 1, 6 y 8). Antes de escribir, lee completo `ios/KitchenKit/Sources/KitchenDomain/Rules/CatalogListQueries.swift` (los comentarios explican qué hace cada filtro; la lógica la implementa K7 en paralelo y tú solo la llamas; si todavía ves el cuerpo provisional, escribe contra esas firmas, que no cambian). En la app lee `Features/Catalog/CatalogModel.swift`, `Features/Catalog/CatalogView.swift`, `Features/Catalog/PackageText.swift` (función `packageText(for:)`), `Features/Catalog/RecordPriceModel.swift` (`parsePriceCents`) y `Core/Format/Money.swift`. Las tiendas salen de `store.data.activeSuppliers()`.

**Alcance cerrado (solo estos archivos, en `ios/aye-kitchen/aye-kitchen/Features/Catalog/`):**
- `CatalogModel.swift`: el estado del filtro y las secciones.
- `CatalogView.swift`: la búsqueda, el botón de filtros, los filtros activos, el renglón y el estado vacío.
- `CatalogFilterSheet.swift` (nuevo): la hoja de filtros.
- No toques `Core/`, `App/`, `Design/`, `ios/KitchenKit/` ni `project.pbxproj`. No compiles la app ni abras el simulador (Claude compila al auditar).

**Lo que ya existe y no cambia:** el botón de Tiendas (con su consejo `CatalogStoresTip`), el botón de agregar ingrediente, `CatalogBrandsTip`, el borrado deslizando con su confirmación y su alerta, la navegación a `IngredientDetailView`, el estado vacío de "Tu catálogo está vacío" cuando no hay ningún ingrediente, y el subtítulo de hoy del renglón cuando no aplica el punto 5.

**Requisitos.**
1. **Modelo.** `CatalogModel` guarda un `CatalogFilter` (en lugar de `searchText` suelto; la búsqueda escribe en `filter.query`). Expone `items` = `store.data.catalogList(filter)`, `groups` = `store.data.catalogGroups()`, `suppliers` = tiendas activas, `hasAnyIngredient` (si hay al menos un ingrediente activo, para distinguir "catálogo vacío" de "nada coincide") y `clearFilters()` (tienda, grupo y precio a sus valores por defecto; no toca la búsqueda ni el orden). `sections`: si el orden es `.group`, agrupa como hoy (grupos por nombre, "Otros" al final) respetando el orden de `items`; con cualquier otro orden, una sola sección sin título con todos los `items` en el orden que vienen. `deleteIngredient` sin cambios. La lista se recalcula sola cuando cambian los datos (lee del almacén como hoy).
2. **Búsqueda.** El `.searchable` queda con el texto "Buscar ingrediente, marca o tienda". Se escribe directo en el filtro del modelo (quita el `@State searchText` duplicado y su `onChange`).
3. **Botón de filtros** en la barra, a la derecha junto al de agregar: símbolo `line.3.horizontal.decrease.circle` (su versión `.fill` cuando `filter.hasFilters` o el orden no es `.group`), etiqueta de accesibilidad "Filtrar y ordenar". Abre `CatalogFilterSheet` como hoja con detentes mediano y grande.
4. **`CatalogFilterSheet`** (recibe el modelo): un `Form` con estas secciones, cada cambio se aplica al momento (sin botón Guardar), y en la barra "Listo" para cerrar y "Quitar filtros" (deshabilitado si no hay filtros).
   - "Ordenar": selector con "Por grupo", "Por nombre (A–Z)", "Precio más bajo", "Precio más alto", "Precio más viejo primero".
   - "Tienda": "Todas", cada tienda activa por nombre, y "Sin tienda".
   - "Grupo": "Todos" y cada grupo de `catalogGroups()`; si no hay grupos, la sección no aparece.
   - "Precio del paquete": "Todos", "Sin precio", "Precio viejo" y "Entre…". Con "Entre…" aparecen dos campos de dinero "Desde" y "Hasta" (teclado decimal, se leen con `RecordPriceModel.parsePriceCents`; vacío = sin límite) y debajo el texto pequeño `inkMuted` "Es el precio de todo el paquete de la marca que se muestra."
5. **Renglón.** Si el item tiene `highlightsBrand` y `shownBrand`, el subtítulo es "Marca · Tienda · $389.00 por 24 × 900 ml" (sin la tienda si no tiene; precio con `Money.format`; tamaño con `packageText(for:)`; si no tiene precio: "Marca · Tienda · Sin precio"). Si el precio está viejo, añade " · precio viejo" en `warningText`. Si no, el subtítulo de hoy (`ingredientSubtitle`). Mantén el arreglo en dos líneas con letra de accesibilidad como hoy.
6. **Filtros activos.** Cuando `filter.hasFilters`, arriba de la lista una fila que se desplaza en horizontal con una cápsula por filtro activo ("Costco", "Sin tienda", "Lácteos", "Sin precio", "Precio viejo", "$100 a $500", "Desde $100", "Hasta $500"), cada una con una x que quita solo ese filtro, y al final "Quitar todo". Usa los colores y radios de `DESIGN.md` para cápsulas o etiquetas; si no define una, `surfaceCard` con borde `borderInput`. Cada cápsula con etiqueta de accesibilidad "Quitar filtro <nombre>".
7. **Vacío.** Si hay ingredientes pero nada coincide: con búsqueda y sin filtros, `ContentUnavailableView.search(text:)` como hoy; con filtros, `ContentUnavailableView` con título "Nada coincide con tus filtros", símbolo `line.3.horizontal.decrease.circle` y un botón "Quitar filtros" con `.kitchenPrimary`.
8. **Previews:** los de `CatalogView` siguen con `LocalStore.preview()`; agrega uno de `CatalogFilterSheet`.

**Pruebas a mano (descríbelas en tu resumen, no las corras):** filtrar Costco muestra solo lo que tiene marca de Costco con su precio; buscar "kirkland" encuentra la leche; "Precio más alto" ordena sin grupos y deja al final lo que no tiene precio; "Entre…" $100 y $500 filtra; quitar una cápsula quita solo ese filtro; con filtros sin resultados aparece "Nada coincide con tus filtros".

**Criterios de aceptación.**
1. El catálogo se puede buscar por ingrediente, marca, tienda o grupo; filtrar por tienda, grupo y precio; y ordenar por grupo, nombre o precio.
2. Ninguna regla de filtrado u orden vive en la pantalla: todo sale de `catalogList` y `catalogGroups` (la pantalla solo agrupa en secciones cuando el orden es `.group`).
3. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un tipo, una consulta que no existe, un archivo fuera de la lista), detente y pregunta en vez de cambiar código fuera del alcance. No dejes scripts de ayuda: bórralos. No reviertas cambios que veas en archivos fuera de tu alcance (otro agente trabaja en `ios/KitchenKit/`).

### FIN DEL PROMPT PARA GEMINI
