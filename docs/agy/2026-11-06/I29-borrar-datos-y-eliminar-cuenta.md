Bloque I29. Rama `local-first`. Corre en paralelo con B13 (las rutas ya están en `docs/api-contract.md`, sección `/me`). Claude ya dejó en Core: `NetworkService.deleteAyeAccount()`, `LocalReset.eraseAllData(accountId:)`, `LocalReset.forgetAccountOnThisPhone(accountId:)`, `LocalStore.discardAccount()` y la cuenta de prueba `DebugAccount` (solo Debug). Decisión del usuario (2026-11-06): dos opciones; "Borrar mis datos" se queda en Desarrollo por ahora, "Eliminar mi cuenta Aye" va en producción (Apple la exige).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I29 de AyeKitchen iOS: "Borrar mis datos de AyeKitchen" y "Eliminar mi cuenta Aye".** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (regla 12: **no compiles la app**), `DESIGN.md` y `docs/agy/_pantallas-locales.md`. Lee las filas `DELETE /me/data` y `DELETE /me/` de `docs/api-contract.md`, y los comentarios de `Core/Local/LocalReset.swift`, `Core/Auth/DebugAccount.swift`, `NetworkService.deleteAyeAccount()` en `Core/Network/NetworkService.swift` y `SessionStore.signOut()` en `Core/Auth/SessionStore.swift`. Mira cómo está hoy `Features/Settings/SettingsView.swift` (secciones, `eraseDataSection`, `#if DEBUG`).

**Contexto.** Dos acciones distintas que hay que explicar con palabras claras:
- **Borrar mis datos de AyeKitchen**: vacía AyeKitchen en el servidor y en el teléfono; la cuenta Aye sigue y la persona sigue dentro, con la app como nueva (al terminar sale "Tu negocio" sola, eso ya lo hace `RootView`). Por ahora solo en Desarrollo.
- **Eliminar mi cuenta Aye**: borra todo lo de AyeKitchen **y** la cuenta Aye; ya no podrá entrar a ninguna app Aye con esa cuenta. Va en producción.

**Ya existe y NO se cambia:** todo `Core/` y `App/`. Usa las funciones que ya están; si te falta algo ahí, detente y pregunta.

**Alcance, dentro de `ios/aye-kitchen/aye-kitchen/Features/Settings/`:**
- `DataDeletionModel.swift` (nuevo): `@Observable final class` con el estado (trabajando, error) y dos métodos `async`.
- `DeleteAccountView.swift` (nuevo): la pantalla de "Eliminar mi cuenta Aye".
- `SettingsView.swift`: cambiar `eraseDataSection` (sigue dentro de `#if DEBUG`) y agregar la sección de eliminar cuenta (fuera de `#if DEBUG`).

1. **`DataDeletionModel.eraseKitchenData(accountId:)`:**
   - En builds Debug, si `DebugAccount.isActive`, no llama al servidor: solo `LocalReset.eraseAllData(accountId:)`.
   - Si no: `NetworkService.shared.requestNoContent(.delete, "/me/data")`; **solo si sale bien**, `LocalReset.eraseAllData(accountId:)`. Si falla, no borra nada en el teléfono y muestra: sin internet → "Necesitas internet para borrar tus datos. No se borró nada."; otro error → `localizedDescription`.
2. **`DataDeletionModel.deleteAyeAccount(accountId:session:)`**, en este orden:
   - En builds Debug con `DebugAccount.isActive`: solo `LocalReset.forgetAccountOnThisPhone(accountId:)` y `await session.signOut()`.
   - Si no: (a) `requestNoContent(.delete, "/me/")` (Kitchen); si falla, para, no se borró nada, mismo mensaje de internet. (b) `NetworkService.shared.deleteAyeAccount()`; si falla, para y muestra "Tus datos de AyeKitchen ya se borraron, pero no pudimos eliminar tu cuenta Aye. Intenta de nuevo." (reintentar es seguro: las dos rutas se pueden repetir). (c) `LocalReset.forgetAccountOnThisPhone(accountId:)`. (d) `await session.signOut()` (la app regresa sola a Entrar).
3. **`SettingsView`:**
   - `eraseDataSection` (sigue en `#if DEBUG`, encima de la sección de Desarrollo): el botón dice "Borrar mis datos de AyeKitchen"; la confirmación dice "¿Borrar tus datos de AyeKitchen?" con el mensaje "Se borran de este teléfono y de tus respaldos: ingredientes, recetas, pedidos, clientes, gastos y fotos de referencia. Tu cuenta Aye se queda. No se puede deshacer." y el botón "Borrar todo". Al confirmar llama al modelo; mientras trabaja, el botón muestra un indicador y queda desactivado; si sale bien cierra Ajustes (`dismiss()`), si falla muestra el error en una alerta y se queda.
   - Sección nueva **fuera de `#if DEBUG`**, después de "Cerrar sesión": una fila "Eliminar mi cuenta Aye" en color de advertencia que navega (`NavigationLink`) a `DeleteAccountView`.
4. **`DeleteAccountView`** (pantalla con desplazamiento, título "Eliminar cuenta"):
   - Un texto corto y claro: "Al eliminar tu cuenta Aye:" y una lista con: "Se borran para siempre tus datos de AyeKitchen, en este teléfono y en tus respaldos."; "Ya no podrás entrar a ninguna app Aye con esta cuenta."; "No se puede deshacer."
   - Muestra el correo de la cuenta (`session.me?.email`) para que sepa cuál elimina.
   - Botón destructivo "Eliminar mi cuenta" que abre una confirmación ("¿Eliminar tu cuenta Aye para siempre?", botón "Eliminar cuenta", "Cancelar"). Al confirmar llama `deleteAyeAccount`; mientras trabaja, indicador y todo desactivado; si falla, el mensaje en la pantalla (no la cierres). Si sale bien, no hagas nada más: la sesión se cierra y la app vuelve a Entrar.
   - Sin emojis, palabras sencillas, de tú.
5. **Accesibilidad y previews:** botones con etiquetas claras; todo legible en AX3. Previews dentro de `#if DEBUG`, sin red: `DeleteAccountView` normal, AX3 y modo oscuro (con `.environment(SessionStore())`), y los de `SettingsView` que ya existen siguen compilando.

**Criterios de aceptación** (Claude compila y prueba al auditar, con la cuenta test/test y contra el backend de B13):
1. Con test/test, "Borrar mis datos de AyeKitchen" deja la app vacía y sale "Tu negocio"; "Eliminar mi cuenta Aye" regresa a Entrar y al volver a entrar con test/test la app está como nueva.
2. Sin internet, ninguna de las dos borra nada en el teléfono.
3. En Release, "Eliminar mi cuenta Aye" está y "Borrar mis datos de AyeKitchen" no.
4. `git status` solo muestra archivos dentro de `Features/Settings/`.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `backend/`.

### `FIN DEL PROMPT PARA GEMINI`
