Bloque I22. Rama `local-first`. Va después de K3 (usa el tablero y las categorías). Corre en paralelo con I21.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I22 de AyeKitchen iOS: la pestaña Finanzas (gastos, ganancias del mes y costos de recetas).** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md`, `DESIGN.md` y todas las reglas de `docs/agy/_pantallas-locales.md`. Usa de `ios/KitchenKit/Sources/KitchenDomain/Rules/`: `SummaryQueries.swift` (`monthlySummary`), `ExpenseRules.swift` (crear, editar, borrar y listar gastos), `CostDashboardQueries.swift` (tablero y categorías) y los proveedores de `CatalogQueries.swift`.

**Contexto.** La app tiene 4 pestañas y pasa a 5 con **Finanzas**. Reúne dos cosas que hoy no tienen pantalla: los gastos del negocio con lo que se ganó en el mes, y un tablero de cuánto cuesta y cuánto deja cada receta.

**Alcance:**
- `ios/aye-kitchen/aye-kitchen/Features/Finance/` (nueva carpeta): `FinanceView.swift`, `FinanceModel.swift`, `ExpenseFormView.swift`, `RecipeCostDashboardView.swift` (y los que necesites).
- `ios/aye-kitchen/aye-kitchen/App/MainTabView.swift`: **solo** agregar la quinta pestaña `Tab("Finanzas", systemImage: "chart.bar")` con `FinanceView()`, después de Catálogo. Nada más en ese archivo.

1. **Encabezado:** título grande "Finanzas" y un selector de mes ("‹ noviembre 2026 ›"; no deja ir al futuro). Un `Picker(.segmented)` con **"Mes"** y **"Recetas"**.
2. **Mes** (con `monthlySummary` del mes elegido):
   - Tarjeta principal (`.softCard()`): "Te quedó" (neto: lo cobrado menos lo gastado) en grande, y debajo "Cobraste" y "Gastaste".
   - Fila de datos: "Vendiste" (pedidos entregados), "Ganancia estimada", "Por cobrar", y pedidos entregados y pendientes.
   - **Gastos del mes:** lista (descripción, categoría, proveedor si hay, fecha y monto), más reciente primero, con "Agregar gasto" (`AddToolbarButton` en esta vista o un botón en la sección), editar al tocar y borrar con deslizar (con confirmación).
   - Vacío: "Todavía no registras gastos este mes. Agrega lo que compras para ver cuánto te queda."
3. **ExpenseFormView** (hoja): descripción, monto (con "$", teclado decimal), fecha (por defecto hoy), categoría (texto libre con las categorías ya usadas como sugerencias tocables, de la consulta de K3), proveedor opcional (menú con los proveedores). Errores `invalidValue` bajo el campo.
4. **Recetas** (`RecipeCostDashboardView`, con la consulta del tablero de K3):
   - Arriba: cuántas recetas, cuántas "con precios faltantes" y cuántas "con precios viejos" (tocables para ordenar "por revisar").
   - Menú de orden: "Por revisar", "Mayor ganancia", "Mayor costo", "Nombre".
   - Cada receta en una fila: nombre; costo de tanda; costo por pieza (o por porción) y precio sugerido por pieza; ganancia sugerida por tanda; margen; chips "Falta precio" o "Precio viejo". Al tocarla abre `RecipeDetailView(recipeId:)`.
   - Se recalcula una vez por `LocalStore.shared.revision`, no en cada dibujo.
5. Dinero con `Money.format` y `.monospacedDigit()`, montos nunca truncados; con letra de accesibilidad, lo que va lado a lado pasa uno debajo del otro. Previews con `LocalStore.preview()` (agrega gastos de ejemplo dentro del preview si los necesitas, sin tocar `Core/`), en tamaño normal y `.accessibility3`.

**Criterios de aceptación.**
1. La barra muestra 5 pestañas y Finanzas abre en el mes actual.
2. Agregar un gasto lo muestra en la lista y baja "Te quedó" sin recargar; borrarlo lo regresa.
3. En "Recetas", las Galletas de ejemplo aparecen primero en "Por revisar" (les falta el precio de las chispas).
4. Build sin advertencias nuevas; `git status` solo muestra tu alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Settings/` y en `Features/Home/HomeView.swift`.

### `FIN DEL PROMPT PARA GEMINI`
