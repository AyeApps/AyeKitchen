### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I4 de AyeKitchen iOS: Inicio.** Pedidos (I2) y Recetas (I3) ya están hechos y commiteados. Antes de empezar lee "Reglas de iOS" en `GEMINI.md`, en `DESIGN.md` la regla "Inicio no muestra dinero" y "Cards / Containers", y en `docs/api-contract.md` `GET /orders/`, `GET /recipes/` y `GET /presentations/stale`. La referencia visual es el artboard "Inicio — iPhone" del lienzo.

**Alcance: solo la carpeta `ios/aye-kitchen/aye-kitchen/Features/Home/`.** Hoy tiene `HomeView.swift` con el encabezado (fecha y "Hola, <nombre>"), el menú de cuenta (`AccountMenu`), el "+" y un estado vacío provisional. Conserva el encabezado y `AccountMenu` tal como están y reemplaza el resto. Reutiliza sin modificarlos, desde `Features/Orders/`: `OrderRow` (fila de pedido), `OrderDetailView(order:onOrderUpdated:onOrderDeleted:)`, `OrderFormView(order:onSave:)` y `OrderDateFormatter`; desde `Features/Recipes/`: `RecipeDetailView(recipeId:)`. Otros agentes trabajan al mismo tiempo en esas carpetas sin cambiar esos inicializadores: no toques nada fuera de `Features/Home/`.

**Regla del bloque: en Inicio no aparece ningún monto de dinero.** Nada de totales, saldos, costos ni precios, ni siquiera en las filas.

**1. `HomeModel` (`@Observable`).** Al aparecer y con `.refreshable`, carga en paralelo: `GET /orders/?status=pendiente&limit=100`, `GET /orders/?status=en_proceso&limit=100`, `GET /recipes/?limit=100` y `GET /presentations/stale?limit=5`. Si alguna falla, la pantalla muestra `ErrorStateView` con reintento debajo del encabezado. Recarga también cuando se regresa de un detalle o se guarda un pedido.

**2. Encabezado.** Debajo de "Hola, <nombre>", en `.body` `.inkMuted`: "Tienes N entregas esta semana." (pedidos pendientes o en proceso con entrega desde el inicio de hoy hasta 7 días después; "Tienes 1 entrega esta semana." en singular; "No tienes entregas esta semana." con cero).

**3. "Lo que sigue" (tarjeta crema, `.softCard()`).** El pedido pendiente o en proceso con la entrega más próxima desde el inicio de hoy. Arriba, "Lo que sigue" en `.subheadline` heavy `.accentTextDeep` y a la derecha su `StatusChip`. Luego el momento de entrega en `.title2` heavy: "Hoy, 4:00 pm", "Mañana, 4:00 pm" o "Sábado 26, 4:00 pm" (con `OrderDateFormatter`); el cliente en `.headline`; los pasteles en `.callout` `.inkOnSoft` ("Pastel de chocolate × 1 · Tres leches × 2"). Abajo, botón "Ver pedido" a todo lo ancho con fondo `.surfaceCard`, texto `.inkPrimary` heavy y radio `Radius.control`, que navega a `OrderDetailView`. Si no hay ninguno, la tarjeta dice "No tienes entregas pendientes." con un botón "Anotar un pedido" que abre el formulario de pedido.
- Si hay pedidos atrasados (pendientes o en proceso con entrega antes del inicio de hoy), arriba de la tarjeta va una fila con `Chip("N atrasados", tone: .warning)` y el texto "Revísalos en Pedidos". No navega.

**4. "Esta semana".** Título con `.sectionTitleStyle()`. Los demás pedidos de la semana (la misma ventana del punto 2, sin el de la tarjeta), en orden de entrega, dentro de `RowGroup`, cada uno con `OrderRow` envuelto en un `NavigationLink` a `OrderDetailView` (estilo `.plain`). Si no hay más: "Nada más esta semana." en `.inkMuted`.

**5. "Por revisar".** Título con `.sectionTitleStyle()`. Se oculta si no hay nada que revisar. Dentro de `RowGroup`:
- Hasta 3 recetas con `complete` falso: cuadro de 36 pt escalable con fondo `.warningSoft` y el ícono `exclamationmark.triangle` en `.warningText`, el nombre en `.headline` y "Le faltan precios" en `.subheadline` `.inkMuted`; navega a `RecipeDetailView(recipeId:)`.
- Hasta 3 marcas con precio viejo: el mismo cuadro, "<ingrediente> · <marca>" en `.headline` y "Precio de hace N días" con `price_age_days`. Por ahora no navegan (se conectarán al detalle de la marca en el bloque siguiente).
- Si hay más de 3 recetas incompletas, una fila final "Ver todas en Recetas" en `.tint` que no navega todavía.

**6. El "+".** Sigue en la barra con la etiqueta "Nuevo pedido", pero ahora abre `OrderFormView(order: nil)` en lugar de `ComingSoonSheet`; al guardar, recarga Inicio.

**7. Letra grande.** En tamaños de accesibilidad todo se apila; el momento de entrega y los nombres pueden ir en varias líneas, nada se corta.

**Criterios de aceptación.**
1. Con un pedido para mañana y otro para dentro de 3 días: la tarjeta muestra el de mañana, "Esta semana" muestra el otro y el encabezado dice "Tienes 2 entregas esta semana."
2. Marcar como entregado el pedido de la tarjeta desde su detalle y regresar hace que la tarjeta pase al siguiente.
3. Una receta con un ingrediente sin precio aparece en "Por revisar" y navega a su desglose.
4. `grep` de `Money.format` y `_cents` en `Features/Home/` no encuentra nada.
5. Previews de Inicio con datos de ejemplo (con y sin pedidos, con atrasados y con cosas por revisar), también en `.accessibility3`.
6. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra cambios dentro de `ios/aye-kitchen/aye-kitchen/Features/Home/`.

Si algo choca con el alcance (un inicializador de otra carpeta que no coincide, un modelo al que le falta un campo, un error de compilación fuera de tu carpeta), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
