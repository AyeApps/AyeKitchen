Bloque I14a. Corre en paralelo con B10 e I14b (no comparten archivos).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I14a de AyeKitchen iOS: scroll sin tirones en Pedidos e Inicio, y el nombre de la receta sin duplicarse.** Relee "Reglas de iOS" en `GEMINI.md`.

**Contexto.** Dos cosas hacen que la app se sienta torpe:
- `OrderDateFormatter` (en `Features/Orders/CurrencyMath.swift`) y una función de fecha de `Features/Home/HomeView.swift` crean un `DateFormatter` nuevo cada vez que se dibuja una fila. Crear un `DateFormatter` es caro: con varias filas por pantalla, el scroll da tirones.
- En el detalle de la receta, el nombre está dos veces: como título chico en la barra (`.navigationTitle` con `.inline`) y como encabezado grande dentro del contenido. Con la barra translúcida de iOS 26, al hacer scroll se ven los dos nombres encimados y borrosos.

**Alcance:**
- `ios/aye-kitchen/aye-kitchen/Features/Orders/CurrencyMath.swift` (solo `OrderDateFormatter`)
- `ios/aye-kitchen/aye-kitchen/Features/Home/HomeView.swift` (solo la función de fecha que hoy crea un `DateFormatter`; no toques `AccountMenu`)
- `ios/aye-kitchen/aye-kitchen/Features/Recipes/RecipeDetailView.swift` (solo título y encabezado)

1. **Formateadores creados una vez.** Cada formato distinto (encabezado de día, día abreviado, número de día, hora, fecha y hora completa, fecha de pago, y el de `HomeView`) pasa a ser un `static let` con su configuración actual exacta (mismo `locale`, mismo `dateFormat` o estilos, misma zona horaria). Las funciones solo lo usan. El texto que sale debe ser idéntico al de hoy, incluidos mayúsculas, puntos quitados y "Mañana"/"Hoy". Como el proyecto usa MainActor por defecto y `DateFormatter` no es `Sendable`, decláralos de forma que compile sin advertencias (por ejemplo `nonisolated(unsafe) static let`, solo se usan para formatear) o usa `Date.FormatStyle`, que sí es `Sendable`, si da exactamente el mismo texto.
2. **Título de la receta.** En `RecipeDetailView`, usa el título grande nativo: `.navigationTitle` con el nombre de la receta y `.navigationBarTitleDisplayMode(.large)`, que se encoge solo al hacer scroll. Quita el nombre del encabezado del contenido (`headerSection`); lo demás de ese encabezado (lo que rinde, las porciones, la descripción si la hay) se queda. Mientras la receta carga, el título queda vacío como hoy.
3. Los previews siguen funcionando.

**Criterios de aceptación.**
1. Pedidos, Inicio y el detalle de un pedido muestran exactamente las mismas fechas y horas que antes.
2. Al hacer scroll en el detalle de una receta, el nombre aparece una sola vez: grande arriba y luego chico en la barra.
3. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los tres archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
