Bloque K7. Rama `main`. Corre en paralelo con I33 (I33 solo toca `Features/Catalog/`). Pedido del usuario (2026-11-13): en el catálogo poder buscar y filtrar, ver lo de una tienda, filtrar por precio y ordenar por ingrediente. Claude ya dejó el esqueleto en `ios/KitchenKit/Sources/KitchenDomain/Rules/CatalogListQueries.swift`: los tipos `CatalogSort`, `CatalogStoreFilter`, `CatalogPriceFilter`, `CatalogFilter`, `CatalogListItem` y las funciones `catalogList(_:now:)` y `catalogGroups()` con cuerpo provisional (marcado "ESQUELETO K7").

### PROMPT PARA GEMINI — copiar desde aquí

**Bloque K7 de AyeKitchen: búsqueda, filtros y orden del catálogo (KitchenKit).** Trabaja en la rama `main`. Antes de escribir, lee completo `ios/KitchenKit/Sources/KitchenDomain/Rules/CatalogListQueries.swift` (los comentarios de cada tipo y caso son parte del spec), y en `Rules/CatalogQueries.swift` las funciones `activeIngredients(q:group:now:)` y `presentations(forIngredient:now:)` y los tipos `CatalogIngredient` y `CatalogPresentation`. También `Costing/CostingIndex.swift` (`latestPrice(for:)`, `currentPresentation(for:)`, `computePriceStaleness`).

**Alcance cerrado, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Rules/CatalogListQueries.swift`: solo los cuerpos de `catalogList` y `catalogGroups` y funciones privadas de apoyo en ese mismo archivo; quita los comentarios "ESQUELETO K7". No cambies los tipos públicos ni las firmas (I33 ya los usa).
- `Tests/KitchenDomainTests/CatalogListTests.swift` (nuevo).
- Nada más. No toques `CatalogQueries.swift` ni ningún otro archivo: si te falta algo de ahí, reúsalo llamando a sus funciones públicas.

**Lo que ya existe y no cambia:** `activeIngredients`, `presentations(forIngredient:)`, el costeo y todas las pruebas existentes.

**Requisitos de `catalogList`.**
1. **Base.** Parte de los ingredientes activos con su resumen, igual que `activeIngredients(now:)` sin búsqueda (llámala). Para cada ingrediente usa sus marcas de `presentations(forIngredient:now:)` (ya traen tienda, precio más reciente, antigüedad y si es la vigente). Calcula el índice de costeo una sola vez por llamada si lo necesitas, no una vez por ingrediente.
2. **Marcas candidatas** de cada ingrediente según la tienda: `.all` = todas sus marcas; `.store(id)` = solo las de esa tienda; `.noStore` = solo las que no tienen tienda. Si el filtro es de tienda y no hay candidatas, el ingrediente no sale.
3. **Búsqueda** (`query` sin espacios a los lados; vacía = no filtra). Compara sin importar mayúsculas ni acentos (por ejemplo `localizedStandardContains`). El ingrediente sale si coincide su nombre o su grupo, o el nombre de marca o de tienda de alguna marca candidata. Si coincidió solo por marca o tienda, las candidatas se reducen a las que coinciden.
4. **Marca mostrada** (`shownBrand`): entre las candidatas, la vigente si está entre ellas; si no, la de precio más reciente; si ninguna tiene precio, la primera en el orden de `presentations(forIngredient:)`; nula si no hay candidatas.
5. **Grupo:** si `group` no es nulo, solo ingredientes con ese grupo exacto (sin espacios a los lados).
6. **Precio** (sobre la marca mostrada): `.withoutPrice` = sin marca mostrada o sin precio; `.stale` = con precio y `priceIsStale`; `.range` = con precio y dentro del rango (extremos incluidos; un extremo nulo no limita; si el mínimo es mayor que el máximo, trátalos al revés).
7. **`highlightsBrand`:** verdadero si hay marca mostrada y además se cumple al menos uno: filtro de tienda distinto de `.all`, filtro de precio distinto de `.all`, orden por precio (`priceLowToHigh`, `priceHighToLow`, `oldestPrice`), o la búsqueda coincidió solo por marca o tienda.
8. **Orden:** `.group` y `.name` = por nombre del ingrediente (`localizedStandardCompare`); la pantalla arma los grupos. `.priceLowToHigh` / `.priceHighToLow` = por `latestPriceCents` de la marca mostrada; `.oldestPrice` = por `latestPriceAt` ascendente. En los tres de precio, los que no tienen precio van al final por nombre, y los empates se rompen por nombre.

**`catalogGroups`:** los `group` de los ingredientes activos, sin espacios a los lados, sin vacíos ni repetidos, ordenados con `localizedStandardCompare`.

**Pruebas** en `CatalogListTests.swift` (datos armados en la prueba con hora fija, como las demás): leche con marca Kirkland en Costco ($389, reciente) y Lala en Walmart ($28, vieja); harina con una marca sin tienda y sin precio; huevo sin marcas; grupos "Lácteos" y "Secos". Casos: sin filtros (todos, A–Z, `highlightsBrand` falso); tienda Costco (solo leche, marca mostrada Kirkland, `highlightsBrand` verdadero); `.noStore` (solo harina); buscar "costco" y "kirkland" (leche con Kirkland); buscar "lacteos" sin acento (por grupo); buscar "LECHE"; `.withoutPrice` (harina y huevo); `.stale` con tienda Walmart (leche/Lala); rango 100–500 pesos y rango con un extremo nulo; los tres órdenes por precio con los sin precio al final; `catalogGroups`; ingrediente borrado que no sale.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las 116 de hoy y las tuyas) sin advertencias nuevas.
2. `git status` solo muestra los dos archivos del alcance.
3. Tipos públicos y firmas idénticos a los del esqueleto.

Si algo choca con el alcance (una prueba, un tipo, el linter), detente y pregunta en vez de cambiar código fuera del alcance. No dejes scripts de ayuda: bórralos. No reviertas cambios que veas en archivos fuera de tu alcance (otro agente trabaja en `Features/Catalog/`).

### FIN DEL PROMPT PARA GEMINI
