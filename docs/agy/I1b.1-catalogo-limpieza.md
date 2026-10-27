### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I1b.1 de AyeKitchen iOS: dos ajustes en Catálogo.** I1 e I1b ya están hechos. Relee las reglas 3 y 5 de "Reglas de iOS" en `GEMINI.md`.

**Alcance: solo la carpeta `ios/aye-kitchen/aye-kitchen/Features/Catalog/`.** No cambies el inicializador de `BrandDetailView(presentation:mockPrices:onBrandChangedOrDeleted:)` ni el de `IngredientDetailView`: otros agentes los usan al mismo tiempo desde `Features/Recipes/` y `Features/Home/`.

1. **Registrar precio llama a la red desde la vista.** `RecordPriceSheet`, en `BrandDetailView.swift` (desde la línea 328; el envío está cerca de la línea 440), manda `POST /presentations/{id}/prices` desde la vista. Mueve el envío, su estado y su error a un `@Observable final class RecordPriceModel` en su propio archivo. La hoja se ve y se comporta igual.
2. **`@unchecked Sendable` sobra.** Las clases `@Observable` de esta carpeta están declaradas `@unchecked Sendable` (`BrandDetailModel`, `BrandFormModel`, `SuppliersModel`, `IngredientBrandsSectionModel`, y las de `CatalogModel.swift` e `IngredientFormView.swift`). El proyecto usa MainActor por defecto, así que ya son seguras sin eso, y `@unchecked` apaga las revisiones del compilador. Quita `@unchecked Sendable` de todas. Si el compilador marca algo al quitarlo, detente y pregunta en vez de volver a ponerlo.

**Criterios de aceptación.**
1. `grep` de `@unchecked` en `Features/Catalog/` no encuentra nada, y `BrandDetailView.swift` ya no contiene `NetworkService`.
2. Registrar un precio sigue actualizando la tarjeta y el historial.
3. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra cambios dentro de `ios/aye-kitchen/aye-kitchen/Features/Catalog/`.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
