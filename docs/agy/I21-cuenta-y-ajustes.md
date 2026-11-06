Bloque I21. Rama `local-first`. Va después de K3 (usa `updateSettings`). Corre en paralelo con I22.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I21 de AyeKitchen iOS: la pantalla de Cuenta y ajustes.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` y todas las reglas de `docs/agy/_pantallas-locales.md`. Usa `updateSettings` de `ios/KitchenKit/Sources/KitchenDomain/Rules/SettingsRules.swift` y las reglas de unidades de `CatalogRules.swift` / `CatalogQueries.swift`.

**Contexto.** Cada pestaña lleva su vista secundaria arriba a la izquierda. En Inicio, el botón de la cuenta (hoy un menú chico, `AccountMenu` en `Features/Home/HomeView.swift`) pasa a abrir una pantalla completa de Cuenta y ajustes, como en las apps de Apple.

**Ya existe, úsalo:** `BackupView()` (`Features/Backup/`), `BackupService.shared.lastBackupAt`, `LocalStore.shared.hasUnbackedChanges`, `SessionStore` (`me`, `signOut()`).

**Alcance:**
- `ios/aye-kitchen/aye-kitchen/Features/Settings/` (nueva carpeta): `SettingsView.swift`, `SettingsModel.swift`, `BusinessSettingsView.swift`, `CustomUnitsView.swift` (y su formulario si lo separas).
- `ios/aye-kitchen/aye-kitchen/Features/Home/HomeView.swift`: **solo** `AccountMenu`, que deja de ser un `Menu` y pasa a ser un botón con el mismo ícono que abre `SettingsView` en una hoja (`.sheet` con `NavigationStack`). Su función DEBUG `copySessionForScripts` se mueve a `SettingsView`.

1. **SettingsView** (`List` agrupada, título "Ajustes", botón "Listo" que cierra):
   - **Tu cuenta:** nombre y correo de `session.me`.
   - **Respaldo:** una fila que navega a `BackupView()` con el resumen a la derecha ("Respaldado hace 5 min", "Cambios sin respaldar" en `.warningText`, o "Sin respaldo").
   - **Tu negocio:** una fila que navega a `BusinessSettingsView`.
   - **Unidades propias:** una fila que navega a `CustomUnitsView`, con cuántas hay.
   - **Cerrar sesión** (rol destructivo, con confirmación): igual que hoy, sube lo pendiente antes de salir (`backupNow()` si hay cambios) y luego `signOut()`.
   - En DEBUG, una sección "Desarrollo" con "Copiar sesión (DEBUG)", con la misma función de hoy.
2. **BusinessSettingsView:** nombre del negocio, margen por defecto (campo numérico con "%"; abajo: "Se usa en las recetas que no tienen su propio margen"), días para que un precio sea viejo (stepper o campo; abajo: "Después de estos días te avisamos que conviene actualizar el precio"), moneda (por ahora solo muestra "MXN" sin editar). Botón "Guardar" que llama `updateSettings`; los errores `invalidValue` se muestran bajo el campo.
3. **CustomUnitsView:** lista de las unidades del negocio (nombre, abreviatura, "1 bolsa = 500 g"), crear (nombre, abreviatura, tipo: se pesa / es líquido / se cuenta, y equivalencia), editar, borrar con deslizar (con el aviso de `IN_USE` y `DUPLICATE_NAME` en palabras de la cocina). Las del sistema no se muestran aquí.
4. Previews con `LocalStore.preview()` (los que necesiten sesión, con un `SessionStore` de ejemplo si existe la forma; si no, solo las subpantallas), en tamaño normal y `.accessibility3`.

**Criterios de aceptación.**
1. Tocar el botón de la cuenta en Inicio abre Ajustes; desde ahí se llega a Respaldo, Tu negocio y Unidades propias, y Cerrar sesión funciona.
2. Cambiar el margen por defecto cambia el precio sugerido de una receta sin margen propio (se ve en Recetas sin recargar).
3. Build sin advertencias nuevas; `git status` solo muestra tu alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Finance/` y en `App/MainTabView.swift`.

### `FIN DEL PROMPT PARA GEMINI`
