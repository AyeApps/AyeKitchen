Bloque I11. **Espera a que I9 esté auditado** (los dos tocan `IngredientFormView.swift`). Puede correr en paralelo con I10 (no comparten archivos). Origen: a una usuaria no le quedó claro cómo registrar un líquido ni la mantequilla.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I11 de AyeKitchen iOS: "¿Cómo lo mides en tus recetas?" en vez de "¿Cómo lo compras?".** Relee "Reglas de iOS" en `GEMINI.md`.

**Contexto.** Al crear un ingrediente se elige su unidad base (`BaseUnit`: `.g`, `.ml`, `.pz`). Hoy la pregunta dice "¿Cómo lo compras?" con Peso, Volumen y Pieza, y abajo "Todo se lleva a gramos". Confunde: la mantequilla se compra por barra pero en las recetas se pesa, así que va por peso, y una usuaria no supo dónde poner la leche. Lo que importa es cómo se mide en las recetas. Además, cuando el ingrediente ya tiene marcas o lo usa una receta, esto ya no se puede cambiar, así que conviene acertar desde el principio. Solo cambian textos y se agrega una ayuda: ni la lógica ni lo que se manda al servidor cambian.

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/Catalog/`:**
- `IngredientFormView.swift`
- `CatalogModel.swift` (solo `buyingUnitDescription`)
- `BaseUnitHelpSheet.swift` (nuevo)

1. **La pregunta** (`buyingUnitField` en `IngredientFormView`). El título y la etiqueta del `Picker` dicen "¿Cómo lo mides en tus recetas?". Opciones del selector segmentado: "Se pesa" (`.g`), "Es líquido" (`.ml`) y "Se cuenta" (`.pz`). En el menú que se usa con letra de accesibilidad: "Se pesa (g)", "Es líquido (ml)" y "Se cuenta (piezas)".
2. **Ayuda según la opción.** `baseUnitHelpText` cambia a:
   - `.g`: "Harina, azúcar, mantequilla, queso. En tus recetas usas g, kg o tazas."
   - `.ml`: "Leche, aceite, crema, vainilla. En tus recetas usas ml, litros o cucharadas."
   - `.pz`: "Huevos, latas, tortillas: lo que cuentas uno por uno."
3. **Botón "¿Cuál elijo?".** Va en la misma fila que el título de la pregunta, alineado a la derecha, con el ícono `questionmark.circle` y el texto, en `.tint` y `.subheadline`. Con letra de accesibilidad, va debajo del título. Abre `BaseUnitHelpSheet` como `.sheet` con `.presentationDetents([.medium, .large])`.
4. **`BaseUnitHelpSheet`** (vista sin modelo; no usa red). En un `NavigationStack`, con el título inline "¿Cuál elijo?" y el botón "Listo" en la toolbar, que cierra la hoja. Contenido en una lista con estos textos:
   - Arriba: "Elige según cómo lo mides en tus recetas, no según cómo lo compras."
   - "Se pesa": "Harina, azúcar, queso, chocolate. También la mantequilla: aunque la compres por barra, si en la receta la pesas, elige Se pesa. Una barra de 90 g se registra como un paquete de 90 g."
   - "Es líquido": "Leche, aceite, crema, vainilla, agua. Lo mides en ml, litros, tazas o cucharadas."
   - "Se cuenta": "Huevos, latas, tortillas, cajas. Si tu receta dice 1 barra de mantequilla, también puedes elegir Se cuenta."
   - Abajo, en `.inkMuted`: "Cuando el ingrediente ya tenga marcas o lo use una receta, esto ya no se puede cambiar."
   - Cada opción con su nombre en `.headline` y su texto en `.body`.
5. **Catálogo** (`buyingUnitDescription` en `CatalogModel`): "Se pesa (g)", "Es líquido (ml)" y "Se cuenta (piezas)".
6. **Previews.** `BaseUnitHelpSheet` lleva un preview en tamaño normal y otro en `.accessibility3`. Los previews actuales del formulario siguen funcionando.

**Criterios de aceptación.**
1. En "Nuevo ingrediente" se ve "¿Cómo lo mides en tus recetas?" con Se pesa, Es líquido y Se cuenta. La ayuda de abajo cambia al elegir cada opción.
2. "¿Cuál elijo?" abre la hoja con el ejemplo de la mantequilla, y "Listo" la cierra.
3. Crear y editar un ingrediente mandan exactamente lo mismo que antes.
4. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los tres archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
