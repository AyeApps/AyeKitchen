Bloque I27. Rama `local-first`. Va después de I26.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I27 de AyeKitchen iOS: las imágenes de referencia en las pantallas.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` (regla 12: **no compiles la app**), `DESIGN.md` y las reglas de `docs/agy/_pantallas-locales.md`. Usa `ReferenceStore.shared` (`Core/Local/ReferenceStore.swift`, I26) y las consultas de `ios/KitchenKit/Sources/KitchenDomain/Rules/ReferenceRules.swift` (K4).

**Contexto.** Las referencias son **opcionales y de apoyo**: la foto del empaque de una marca, cómo queda una receta, la receta escrita a mano, el diseño que pidió el cliente o el ticket de un gasto. **No son la imagen de la cosa en la app**: no aparecen en las listas ni reemplazan íconos; la estética la dan nuestros íconos. Hasta 5 por cosa.

**Alcance:**
- `ios/aye-kitchen/aye-kitchen/Features/Shared/References/` (nueva carpeta): `ReferencesSection.swift`, `ReferenceViewer.swift`, `CameraPicker.swift` (y su Model si hace falta).
- Una línea (o pocas) para colocar `ReferencesSection(owner:)` en: el detalle de ingrediente y el de marca (`Features/Catalog/`), el detalle de receta (`Features/Recipes/`), el detalle de pedido (`Features/Orders/`) y el formulario de gasto (`Features/Finance/ExpenseFormView.swift`, solo al editar un gasto que ya existe).

1. **`ReferencesSection(owner: ReferenceOwner)`**: una sección discreta "Referencias", al final del detalle.
   - Sin referencias: una sola fila "Agregar referencia" con ícono, en `.tint`; nada más (no un estado vacío grande).
   - Con referencias: una fila horizontal de miniaturas cuadradas pequeñas (tamaño con `@ScaledMetric`, esquinas con `Radius`), y al final el botón "+" mientras haya menos de 5.
   - "Agregar referencia" abre un menú: "Tomar foto" (cámara, solo si `UIImagePickerController.isSourceTypeAvailable(.camera)`) y "Elegir de tus fotos" (`PhotosPicker`, una o varias hasta completar 5). Cada imagen elegida pasa por `ReferenceStore.shared.add(imageData:to:)`; mientras se comprime, una miniatura con indicador.
   - Error `invalidValue` (más de 5) o de lectura: un mensaje en palabras de la cocina.
2. **`ReferenceViewer`**: al tocar una miniatura, pantalla completa con las referencias de ese dueño en un carrusel (`TabView` paginado), zoom con pellizco y doble toque, botón "Listo", y un menú con "Quitar referencia" (con confirmación: "¿Quitar esta referencia? No cambia nada más.") que llama `ReferenceStore.shared.remove`.
3. **`CameraPicker`**: envoltura mínima de `UIImagePickerController` para la cámara (el permiso de cámara ya está en el proyecto).
4. Accesibilidad: cada miniatura con `accessibilityLabel("Referencia 1 de 3")`; el botón con "Agregar referencia". Previews con `LocalStore.preview()` (sin referencias y con imágenes de ejemplo generadas en el preview).

**Criterios de aceptación** (Claude compila al auditar):
1. Las listas (Catálogo, Recetas, Pedidos, Finanzas) no cambian: las referencias solo aparecen en los detalles.
2. Se puede agregar desde la cámara y desde las fotos, ver a pantalla completa con zoom, y quitar.
3. Con 5 referencias desaparece el "+".
4. `git status` solo muestra tu alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. **No reviertas cambios que veas en archivos fuera de tu alcance.**

### `FIN DEL PROMPT PARA GEMINI`
