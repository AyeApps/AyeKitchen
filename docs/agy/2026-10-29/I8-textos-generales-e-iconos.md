Bloque I8. Puede correr en paralelo con B5 e I7a (no comparten archivos). Claude ya agregó el logo de la app: `AppIcon` (claro y oscuro) y la imagen `AppLogo` en `Assets.xcassets`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I8 de AyeKitchen iOS: textos generales en lugar de "pastel" y el logo nuevo.** La app ya no es solo para pasteles; sirve para cualquier receta que se vende. Relee "Reglas de iOS" en `GEMINI.md`.

**Alcance: solo estos archivos dentro de `ios/aye-kitchen/aye-kitchen/`:**
- `Features/Login/LoginView.swift`
- `Features/Orders/OrderFormView.swift`
- `Features/Orders/OrderFormModel.swift` (solo comentarios)
- `Features/Orders/OrderDetailView.swift`
- `Features/Recipes/RecipeItemPicker.swift`
- `Features/Recipes/RecipeEditorView.swift`
- `Features/Recipes/RecipeDetailView.swift`

No toques los datos de ejemplo de los previews (`*MockData.swift`, ni los mocks dentro de los previews).

1. **Textos de los pedidos.** Las líneas de un pedido ahora se llaman "productos".
   - En `OrderFormView`: el título de sección "Pasteles" (línea 120) pasa a "Productos". "Agrega al menos un pastel al pedido." (línea 124) pasa a "Agrega al menos un producto al pedido.". "Agregar pastel" (línea 141) pasa a "Agregar producto". El título "Pasteles" de `RecipePickerSheet` (línea 237) pasa a "Productos".
   - En `OrderDetailView`: el título de sección "Pasteles" (línea 209) pasa a "Productos".
   - Renombra a `productsSection` las propiedades `cakesSection` de ambos archivos, y a `productItemRow` la función `cakeItemRow`. Cambia el comentario `// MARK: - Pasteles` a `// MARK: - Productos`.
   - En `OrderFormModel`, cambia "Línea de pastel" y "línea de pastel" de los comentarios (líneas 57 y 180) por "Línea de producto" y "línea de producto". En ese archivo no cambies nada más.
2. **Login.**
   - El subtítulo "Entra para ver tus pedidos y lo que cuesta cada pastel." (línea 58) pasa a "Entra para ver tus pedidos y lo que cuesta cada receta.".
   - En `header`, el `Image(systemName: "birthday.cake")` pasa a ser el logo de la app: la imagen del catálogo `AppLogo`, con el símbolo generado `.appLogo`. Va redimensionable y `scaledToFit`, dentro del mismo cuadro de `logoSize` con fondo `.accentFill` y esquinas de 28. Deja un margen interior de más o menos el 14% de `logoSize` para que la olla no toque los bordes. Sigue con `accessibilityHidden(true)`.
3. **Iconos de receta.** Cambia el SF Symbol de pastel por uno general de cocina:
   - `"birthday.cake"` por `"fork.knife"` en `RecipeItemPicker.swift` (líneas 153 y 187) y en `RecipeEditorView.swift` (línea 297).
   - `"birthday.cake.fill"` por `"fork.knife"` en `RecipeDetailView.swift` (línea 435).
   - No cambies colores ni tamaños.

**Criterios de aceptación.**
1. `grep -rniE "pastel|birthday" ios/aye-kitchen/aye-kitchen --include="*.swift"` solo encuentra resultados en datos de ejemplo de previews y en `Design/DesignGallery.swift`.
2. El login muestra la olla naranja de la app en lugar del pastel.
3. El formulario y el detalle de un pedido dicen "Productos" y "Agregar producto".
4. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
