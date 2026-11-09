Bloque I6. No depende de otro bloque pendiente. En producción, crear cuenta con correo va a seguir chocando con Turnstile hasta que aye-auth acepte App Attest (plan en `~/Desktop/AyeApps-movil-sin-Turnstile.md`). En local funciona porque aye-auth corre sin `TURNSTILE_SECRET_KEY`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I6 de AyeKitchen iOS: crear una cuenta Aye desde la pantalla de entrar.** Relee "Reglas de iOS" en `GEMINI.md`.

**Contexto.** `Features/Login/LoginView.swift` solo deja entrar con correo y contraseña o con Apple. Quien no tiene cuenta Aye no puede crearla desde la app. aye-auth ya tiene el endpoint: `POST <authBaseURL>/register` (la misma base que usa `NetworkService.login`, o sea `AppConfig.authBaseURL` más `/register`). Su cuerpo lleva `email` (correo válido), `password` (8 caracteres o más), `name` (de 1 a 100 caracteres) y `app_client`. Responde **201** con la misma forma que `/login` (`access_token` y `refresh_token`). Sus errores:
- **400** "Ya existe una cuenta con correo y contraseña para este email." si el correo ya tiene cuenta.
- **400** "Se requiere verificación de seguridad (Turnstile token requerido)." si el servidor pide Turnstile.
- **422** si los campos no pasan la validación.

Al entrar, `/login` responde **404** con `detail` "ACCOUNT_NOT_FOUND" si el correo no tiene cuenta, **401** "INVALID_PASSWORD" si la contraseña está mal y **423** con un texto si la cuenta está bloqueada.

**Alcance: solo estos cuatro archivos dentro de `ios/aye-kitchen/aye-kitchen/`:** `Core/Network/NetworkService.swift`, `Core/Auth/SessionStore.swift`, `Features/Login/LoginView.swift` y el archivo nuevo `Features/Login/SignUpView.swift`. No toques aye-auth ni el backend de kitchen.

1. **Red.** En `NetworkService`, en la sección "Cuenta Aye (aye-auth)", agrega `register(name:email:password:)`. Hace lo mismo que `login`: un POST sin autorización a `AppConfig.authBaseURL` con la ruta `/register` y un cuerpo privado nuevo con `name`, `email`, `password` y `appClient` (`AppConfig.appClient`), igual que `LoginBody`. Al final guarda los tokens con el mismo `store` que usa `login`. No cambies `login` ni `signInWithApple`.
2. **Sesión.** En `SessionStore`, agrega `signUp(name:email:password:)`. Llama a `register` y después a `loadMe()`, igual que `signIn`. Así `RootView` pasa solo a la app.
3. **Pantalla nueva `SignUpView`.** Es una hoja con `NavigationStack`, título "Crear cuenta" y botón "Cancelar" a la izquierda que la cierra. Usa los mismos componentes y tokens que `LoginView`: `KitchenTextField`, `.buttonStyle(.kitchenPrimary)`, `Spacing`, `.canvasBackground` y el recuadro de error con `exclamationmark.triangle.fill` sobre `.warningSoft`. Arriba lleva el texto "Es la misma cuenta Aye de las demás apps." en `.inkMuted`. Los campos van en este orden:
   - "Nombre": `contentType` `.name`, capitalización `.words`.
   - "Correo": teclado `.emailAddress`, `contentType` `.username`, sin capitalización ni autocorrección.
   - "Contraseña": segura, `contentType` `.newPassword`, sin capitalización ni autocorrección. Debajo, en `.footnote` y `.inkMuted`, va "Mínimo 8 caracteres".

   El botón "Crear cuenta" se activa solo si el nombre sin espacios tiene de 1 a 100 caracteres, el correo sin espacios contiene "@" y un "." después de la "@", la contraseña tiene 8 caracteres o más y no hay una llamada en curso. Mientras trabaja, muestra un `ProgressView` en lugar del texto, como en `LoginView`. El Enter del teclado envía si se puede. La hoja recibe un correo inicial opcional que llena el campo Correo.
4. **Errores en `SignUpView`.** Al tocar el botón, llama `session.signUp` con nombre y correo sin espacios de los lados. Los errores se traducen así:
   - 400 cuyo mensaje contiene "Turnstile": "Por ahora, desde el iPhone crea tu cuenta con Apple."
   - Cualquier otro 400: el mensaje del servidor, que es el de "Ya existe una cuenta…".
   - 422: "Revisa tu nombre, correo y contraseña."
   - Lo demás: `localizedDescription`, como hoy en `LoginView`.

   Si sale bien no hagas nada más: la sesión cambia de estado y `RootView` reemplaza el login.
5. **Cambios en `LoginView`.**
   - Debajo del botón "Entrar", dentro de `form`, agrega un botón de texto "¿No tienes cuenta? **Crear una**" con color `.accentInk` y fuente `.subheadline`. Abre `SignUpView` como hoja y le pasa el correo que ya esté escrito.
   - En `submit()` agrega dos casos al `switch` de `error.status`: 404 → "No hay una cuenta con ese correo. Toca Crear una para hacerla." y 423 → el mensaje del servidor. Deja los casos 401 y 400 como están.
   - Cambia el subtítulo inferior "Usas la misma cuenta Aye de las demás apps." a "Si ya usas otra app Aye, entra con esa misma cuenta."
6. **Previews.** `SignUpView` lleva un preview con `SessionStore()` en el entorno y `.fontDesign(.rounded)`, como el de `LoginView`.

**Criterios de aceptación** (contra aye-auth local en `localhost:8000`, sin Turnstile).
1. En el login toco "Crear una", lleno Nombre "Mamá", un correo nuevo y una contraseña de 8 caracteres, toco "Crear cuenta" y entro a la app, a Inicio.
2. Si repito con el mismo correo, la hoja muestra "Ya existe una cuenta con correo y contraseña para este email." y sigo en la hoja.
3. Con contraseña de 7 caracteres o un correo sin "@", el botón está desactivado.
4. Si escribo un correo en el login y abro "Crear una", la hoja trae ese correo.
5. En el login, un correo que no existe muestra "No hay una cuenta con ese correo. Toca Crear una para hacerla."
6. Tras cerrar sesión, entro con el correo y la contraseña que acabo de crear.
7. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los cuatro archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
