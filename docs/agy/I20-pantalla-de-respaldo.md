Bloque I20. Rama `local-first`. Corre en paralelo con I19 (no comparten archivos). Claude conecta después la entrada desde el menú de la cuenta.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I20 de AyeKitchen iOS: la pantalla de Respaldo.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` y los comentarios de `ios/aye-kitchen/aye-kitchen/Core/Local/BackupService.swift`, `LocalStore.swift` y `LocalBootstrap.swift` (`BackupScheduler`). La sección `/backup` de `docs/api-contract.md` explica el conflicto.

**Contexto.** Los datos viven en el teléfono y se respaldan solos en el servidor (2 minutos después del último cambio y al salir de la app). Esta pantalla deja ver cuándo fue el último respaldo, respaldar a mano, restaurar el último respaldo, y resolver un conflicto (otro teléfono subió un respaldo más nuevo). Un dispositivo por cuenta.

**Ya existe en `Core/Local/`, úsalo y no lo cambies:** `BackupService.shared` (`backupNow(force:)`, `restoreLatest()`, `latestInfo()`, `isBackingUp`, `lastBackupAt`, `lastError` con `.conflict` y `.failed`) y `LocalStore.shared.hasUnbackedChanges`.

**Alcance:** `ios/aye-kitchen/aye-kitchen/Features/Backup/BackupView.swift` y `BackupModel.swift` (nuevos). Nada más; la entrada desde el menú la agrega Claude.

1. **Estado** (arriba, en una tarjeta): "Último respaldo: hoy, 4:32 pm" (o "Todavía no has respaldado"), y debajo "Tienes cambios sin respaldar" en `.warningText` si `hasUnbackedChanges`, o "Todo está respaldado" si no. Si `lastError` es `.failed`, el texto del error y que se reintentará solo.
2. **"Respaldar ahora"** (`.kitchenPrimary`): llama `backupNow()`, con indicador mientras sube; al terminar, el estado se actualiza.
3. **"Restaurar el último respaldo"** (`.kitchenSecondary`): confirmación con el texto "Esto reemplaza lo que hay en este teléfono por tu último respaldo del <fecha>. Lo que no se haya respaldado se pierde." (la fecha de `latestInfo()`), y luego `restoreLatest()`. Si `hasUnbackedChanges`, la confirmación lo dice primero en `.warningText`.
4. **Conflicto** (`lastError == .conflict` o al recibirlo de `backupNow`): una tarjeta en `.warningSoft` que explica "Otro teléfono guardó un respaldo más nuevo" con el detalle, y dos acciones: "Usar los datos de este teléfono" (confirmación y `backupNow(force: true)`) y "Traer los datos del otro respaldo" (confirmación y `restoreLatest()`).
5. Todo lo de red y estado en `BackupModel` (`@Observable`), la vista solo lee. `NavigationStack` con título "Respaldo". Previews: estado respaldado, con cambios sin respaldar y con conflicto (con un modelo de ejemplo, sin red), en tamaño normal y en `.accessibility3`.

**Criterios de aceptación.**
1. `BackupView()` se puede abrir solo (sin parámetros) y muestra el estado real.
2. Build sin advertencias nuevas; `git status` solo muestra los dos archivos nuevos.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Home/`.

### `FIN DEL PROMPT PARA GEMINI`
