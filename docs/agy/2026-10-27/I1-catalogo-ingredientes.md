### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I1 de AyeKitchen iOS: Catálogo, ingredientes y sus equivalencias.** El backend ya está hecho y el esqueleto de la app de iPhone ya existe en `ios/aye-kitchen/aye-kitchen/`. Antes de empezar lee `GEMINI.md` completo (en especial "Reglas de iOS"), `DESIGN.md`, y en `docs/api-contract.md` las secciones `/units` e `/ingredients`, incluida la "Regla de conversión".

**Alcance: solo la carpeta `ios/aye-kitchen/aye-kitchen/Features/Catalog/`.** Hoy tiene `CatalogView.swift` con un estado vacío provisional; reemplázalo. Puedes crear los archivos que necesites dentro de esa carpeta. Usa sin modificarlos los modelos `Ingredient`, `IngredientConversion`, `MeasureUnit`, `BaseUnit` y `Page` de `Core/Models/`, `NetworkService.shared` y los componentes de `Design/`.

**1. Lista de ingredientes (`CatalogView`).**
- `NavigationStack` con título grande "Catálogo" y el "+" (`AddToolbarButton`, etiqueta "Agregar ingrediente") que abre el formulario del punto 3 como hoja.
- Carga `GET /ingredients/` con `limit=50`; al llegar al final de la lista carga la siguiente página mientras `Page.hasMore`. `.refreshable` vuelve a cargar desde la página 1.
- `.searchable` con el texto "Buscar ingrediente" que manda `q`; espera unos 300 ms después de la última tecla antes de buscar y cancela la búsqueda anterior.
- Lista nativa estilo `insetGrouped` sobre el fondo `.canvasBackground` (oculta el fondo propio de la lista). Agrupa por `group` en secciones ordenadas por nombre; los que no tienen grupo van al final en la sección "Otros".
- Cada fila: el nombre en `.headline` y debajo, en `.subheadline` `.inkMuted`, cómo se compra: "Por peso (g)", "Por volumen (ml)" o "Por pieza". Toda la fila navega al detalle.
- Deslizar para borrar pide confirmación ("¿Borrar Harina? También se borran sus marcas.") y llama `DELETE /ingredients/{id}`. Con `IN_USE` muestra "No se puede borrar: una receta lo usa." y la fila se queda.
- Sin ingredientes: `ContentUnavailableView` "Tu catálogo está vacío" con "Agrega los ingredientes que compras y dónde los compras." Búsqueda sin resultados: el estado de búsqueda vacía del sistema. Error al cargar: `ErrorStateView`.

**2. Detalle del ingrediente (`IngredientDetailView`).**
- Título inline con el nombre; botón "Editar" en la barra que abre el mismo formulario con los datos cargados. Al guardar, el detalle y la lista se actualizan.
- Secciones, en este orden: "Cómo lo compras" (la frase del punto 1); "Marcas y precios" con la vista `IngredientBrandsSection(ingredient:)`; "Equivalencias" con una fila por conversión en la forma "1 taza = 125 g" (nombre de la unidad, cantidad con `Quantity.format`, abreviatura de la unidad base), o el texto "Aún no tiene. Te las preguntamos cuando las necesites." si no hay; "Notas" solo si tiene.
- `IngredientBrandsSection` va en su propio archivo `IngredientBrandsSection.swift` y por ahora solo muestra el texto "Pronto podrás agregar marcas y precios aquí." en `.inkMuted`. El bloque siguiente reemplazará solo ese archivo, así que su inicializador recibe únicamente el `Ingredient`.

**3. Formulario de ingrediente (`IngredientFormView`, hoja), para crear y para editar.**
- Barra: "Cancelar" a la izquierda (cierra sin guardar); título "Nuevo ingrediente" o "Editar ingrediente". La acción principal "Guardar" va abajo con `.kitchenPrimary`, deshabilitada mientras el nombre esté vacío o se esté guardando.
- Campos: "Nombre" (`KitchenTextField`); "¿Cómo lo compras?" con `Picker` segmentado de tres opciones "Peso", "Volumen", "Pieza" (g, ml, pz); debajo una línea de ayuda que dice en qué unidad se guardará todo ("Todo se lleva a gramos"); "Grupo" opcional (texto, ejemplo de ayuda "Lácteos, Harinas…"); "Notas" opcional, de varias líneas.
- En tamaños de accesibilidad el selector de tres opciones pasa a ser un `Picker` de menú.
- "Equivalencias": una fila por equivalencia con el nombre de la unidad, un campo numérico con teclado decimal y la abreviatura de la unidad base ("1 taza = [125] g"), y deslizar para quitarla. Un botón de texto "Agregar equivalencia" abre la lista de unidades de `GET /units/` (cárgala una vez al abrir el formulario) mostrando solo las que tienen una `baseUnit` distinta a la del ingrediente y que aún no están en la lista. Ejemplo: para la harina (peso) se ofrecen taza, cucharada, cucharadita, mililitro, pieza…
- Al guardar: valida cada cantidad con `Quantity.parse` (si alguna no es válida, marca ese campo y no envía). Crear manda `POST /ingredients/`; editar manda `PATCH /ingredients/{id}` con todos los campos y la lista completa de `conversions` (el contrato dice que la reemplaza). Grupo y notas vacíos se mandan como nulos.
- Errores con su mensaje debajo de los campos, dentro de la hoja: `DUPLICATE_NAME` → "Ya tienes un ingrediente con ese nombre."; `IN_USE` → "No se puede: ya tiene marcas o una receta lo usa con esa medida."; `INVALID_REFERENCE` → "Una de las unidades ya no existe. Vuelve a abrir el formulario."; cualquier otro, `localizedDescription`.

**Criterios de aceptación.**
1. Crear "Harina de trigo" por peso con "1 taza = 125 g" la muestra en la lista y en su detalle con esa equivalencia; editarla y cambiar la equivalencia a 120 se refleja sin salir de la pantalla.
2. Crear un segundo ingrediente con el mismo nombre muestra el mensaje de nombre repetido y la hoja sigue abierta con lo escrito.
3. Buscar "har" filtra en el servidor; borrar el texto regresa la lista completa.
4. Los previews de `CatalogView`, `IngredientDetailView` e `IngredientFormView` existen con datos de ejemplo, también en `.accessibility3`, y en ese tamaño ningún texto se corta.
5. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED`.
6. `git status` solo muestra cambios dentro de `ios/aye-kitchen/aye-kitchen/Features/Catalog/`.

Si algo choca con el alcance (un modelo al que le falta un campo, un componente que no alcanza, un error de compilación fuera de tu carpeta), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
