Bloque I24. Rama `local-first`. Corre en paralelo con I25 (no comparten archivos).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I24 de AyeKitchen iOS: la tarjeta "Primeros pasos" en Inicio.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (incluida la regla 12: **no compiles la app**) y las reglas de `docs/agy/_pantallas-locales.md`. Lee `ios/aye-kitchen/aye-kitchen/Core/Tips/FirstSteps.swift` y `AppRouter` en `App/MainTabView.swift`.

**Contexto.** Para que la app no abrume, en lugar de un tutorial se enseña haciendo: una tarjeta en Inicio con 4 pasos que se palomean solos con los datos. Quien ya tiene datos (todos los pasos hechos) no la ve.

**Ya existe, úsalo y no lo cambies:** `FirstSteps.steps(for:)`, `FirstSteps.shouldShow(for:)`, `FirstSteps.dismiss()` (textos ya aprobados) y `AppRouter.shared.selectedTab`.

**Alcance:** solo `ios/aye-kitchen/aye-kitchen/Features/Home/HomeView.swift` (y `HomeModel.swift` si te sirve para exponer los pasos). No toques `AccountMenu`.

1. **Tarjeta** arriba de "Lo que sigue", solo si `FirstSteps.shouldShow(for: store.data)`: título "Primeros pasos", "2 de 4" a la derecha, una barra de progreso con los tokens del diseño, y los 4 pasos en filas: palomita en `.tint` si está hecho (texto en `.inkMuted`), círculo vacío si no. Un paso sin hacer se puede tocar y cambia de pestaña con `AppRouter.shared.selectedTab = step.tab`. Botón "Cerrar" (texto, arriba a la derecha) que llama `FirstSteps.dismiss()` y oculta la tarjeta.
2. Se actualiza sola cuando cambian los datos (`LocalStore.shared.revision`): al registrar el primer pedido, su paso se palomea al volver a Inicio; al completar los 4, la tarjeta desaparece.
3. `.softCard()`, `Spacing`, Dynamic Type; con letra de accesibilidad todo en columna. Preview con un `LocalStore.preview(...)` de un negocio vacío (pasos sin hacer) y uno con los datos de ejemplo (no aparece la tarjeta).

**Criterios de aceptación** (Claude compila al auditar):
1. Con un negocio vacío, Inicio muestra la tarjeta con 0 de 4; tocar "Arma tu primera receta" lleva a Recetas.
2. Con los datos de ejemplo, la tarjeta no aparece (excepto si falta el paso de Finanzas: en ese caso muestra 3 de 4).
3. `git status` solo muestra tu alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en Catálogo, Recetas, Pedidos, Finanzas y Ajustes.

### `FIN DEL PROMPT PARA GEMINI`
