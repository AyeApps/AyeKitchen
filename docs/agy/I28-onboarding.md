Bloque I28. Rama `local-first`. Onboarding: bienvenida antes de Entrar y "Tu negocio" la primera vez que entra una cuenta nueva. Claude ya dejó el esqueleto conectado: `Core/Onboarding/OnboardingFlags.swift` (cuándo sale cada pantalla), `App/RootView.swift` (las muestra) y las dos vistas vacías en `Features/Onboarding/`. Decisiones del usuario (2026-11-06): las dos partes; dibujos con íconos del sistema, sin imágenes.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I28 de AyeKitchen iOS: las pantallas de onboarding.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (regla 12: **no compiles la app**), `DESIGN.md`, `PRODUCT.md` (usuaria, voz) y `docs/agy/_pantallas-locales.md`. Como referencia de estilo: `Features/Login/LoginView.swift` (logo, márgenes, botones) y `Features/Settings/BusinessSettingsView.swift` (cómo se guardan los ajustes del negocio).

**Contexto.** Hoy la app abre directo en Entrar. Queremos dos momentos: (1) una bienvenida corta, una sola vez por instalación, que diga para qué sirve la app; (2) la primera vez que entra una cuenta **nueva y vacía**, una pantalla para ponerle nombre al negocio y escoger su margen. Después llega a Inicio, donde ya está la tarjeta "Primeros pasos" (no la repitas aquí).

**Ya existe y NO se cambia** (lo mantiene Claude): `App/RootView.swift`, `Core/Onboarding/OnboardingFlags.swift`, y las **firmas** de las dos vistas: `WelcomeView(onFinish:)` y `BusinessSetupView(store:onFinish:)`. `RootView` decide cuándo salen y guarda las marcas; tus vistas **no** leen ni escriben `UserDefaults`/`@AppStorage` ni `OnboardingFlags`: solo llaman `onFinish()`.

**Alcance:**
- `ios/aye-kitchen/aye-kitchen/Features/Onboarding/WelcomeView.swift` (reemplaza el cuerpo y el preview del esqueleto)
- `ios/aye-kitchen/aye-kitchen/Features/Onboarding/BusinessSetupView.swift` (igual)
- Si te ayuda, un archivo nuevo en esa misma carpeta para piezas compartidas (por ejemplo la página con su ícono). Nada fuera de `Features/Onboarding/`.

1. **`WelcomeView`: tres páginas deslizables** (`TabView` con estilo de páginas y los puntos de página visibles), fondo `canvasBackground`.
   - Cada página: un ícono grande de SF Symbols dentro de un círculo suave (naranja de la marca muy claro o crema, con el ícono en `.tint`), un título corto y una frase. Tamaño del círculo con `@ScaledMetric`. Texto centrado.
   - Página 1 (arriba, el logo `Image(.appLogo)` pequeño como en Entrar): ícono `birthday.cake`. Título "Sabe cuánto te cuesta cada pastel". Frase: "Arma tus recetas con los precios de tus tiendas y te decimos cuánto te cuesta y cuánto cobrar."
   - Página 2: ícono `list.clipboard`. Título "Tus pedidos, en orden". Frase: "Anota la fecha de entrega, el anticipo y lo que te falta cobrar. Todo en un solo lugar."
   - Página 3: ícono `iphone`. Título "Todo vive en tu teléfono". Frase: "Funciona sin internet. Tu información se respalda sola en tu cuenta Aye."
   - Abajo, fijo: en las páginas 1 y 2 un botón principal "Siguiente" (`.kitchenPrimary`) que avanza con animación; en la página 3 el mismo botón dice "Empezar" y llama `onFinish()`.
   - Arriba a la derecha, en las páginas 1 y 2, un botón de texto "Saltar" (`.tint`) que llama `onFinish()`. En la página 3 no aparece.
   - Con `accessibilityReduceMotion`, el cambio de página sin animación.
2. **`BusinessSetupView`: "Tu negocio"**, una sola pantalla con desplazamiento, fondo `canvasBackground`.
   - Arriba: título "Cuéntanos de tu negocio" y la frase "Lo puedes cambiar cuando quieras en Cuenta y ajustes."
   - Campo "¿Cómo se llama tu negocio?" con `KitchenTextField` (`Design/KitchenTextField.swift`), vacío al empezar, con el ejemplo "Pasteles de Ana" como pista visible debajo o como placeholder si el componente lo permite (léelo; no lo modifiques). Capitalización de palabras.
   - "¿Cuánto quieres ganar?": cuatro opciones tipo chip o segmento con 30 %, 40 %, 50 % y 60 %, con 40 % escogido de entrada (es el de fábrica de `KitchenSettings`). Debajo, una frase que cambia con la opción: "Si una receta te cuesta $100, te sugerimos cobrar $140." (precio = costo × (1 + margen/100); calcúlalo con enteros, no a mano en el texto).
   - Botón principal "Continuar": si el nombre (sin espacios a los lados) está vacío, guarda solo el margen; si no, nombre y margen. Guarda **en una sola llamada**, igual que `BusinessSettingsView`: `store.mutate { data, ctx in try data.updateSettings(name: ..., defaultMarginPercent: ..., ctx: ctx) }` (con `name: nil` si lo dejó vacío). Si lanza `DomainError.invalidValue`, muestra su `detail` debajo del campo correspondiente y no avances. Si sale bien, llama `onFinish()`.
   - Botón de texto "Ahora no" debajo: llama `onFinish()` sin guardar nada.
   - El teclado no tapa el botón: se puede desplazar, y al tocar "Continuar" se cierra el teclado.
3. **Accesibilidad:** los íconos decorativos ocultos para VoiceOver; cada página de bienvenida se lee como un solo elemento (título y frase); las opciones de margen se leen como "40 por ciento, seleccionado". Todo se ve bien en AX3 (el texto crece, nada se corta, los botones siguen al alcance con desplazamiento).
4. **Previews** (dentro de `#if DEBUG`, sin red): `WelcomeView` normal y en `.dynamicTypeSize(.accessibility3)`; `BusinessSetupView` con `LocalStore.preview(KitchenData.empty(deviceId: "preview"))`, normal y en AX3; y uno en modo oscuro de cada una.

**Criterios de aceptación** (Claude compila y prueba en el simulador al auditar):
1. Instalación nueva: sale la bienvenida; "Saltar" o "Empezar" lleva a Entrar; al cerrar y abrir la app ya no sale.
2. Cuenta nueva y vacía: tras entrar sale "Tu negocio"; "Continuar" guarda nombre y margen (se ven en Cuenta y ajustes > Tu negocio) y abre Inicio; "Ahora no" abre Inicio sin cambiar nada. No vuelve a salir.
3. Cuenta con datos (restaurada o migrada): nunca ve "Tu negocio".
4. `git status` solo muestra archivos dentro de `Features/Onboarding/`.

Si algo choca con el alcance (un componente que no sirve, una firma que no cuadra), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
