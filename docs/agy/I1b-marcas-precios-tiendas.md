### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I1b de AyeKitchen iOS: marcas, precios y tiendas.** El bloque I1 (ingredientes) ya está hecho y commiteado. Antes de empezar lee "Reglas de iOS" en `GEMINI.md`, `DESIGN.md` (chips de advertencia, botones, hojas) y en `docs/api-contract.md` las secciones `/suppliers` y `/presentations` completas. En la interfaz una presentación se llama "marca" y un proveedor se llama "tienda".

**Alcance: solo la carpeta `ios/aye-kitchen/aye-kitchen/Features/Catalog/`.** Puedes crear archivos ahí y modificar `IngredientBrandsSection.swift` y `CatalogView.swift` (solo para lo que dice el punto 5). Usa sin modificarlos los modelos `Presentation`, `PriceRecord`, `Supplier`, `MeasureUnit`, `Ingredient` y `Page` de `Core/Models/`, `NetworkService.shared` y los componentes de `Design/`. Otro agente trabaja al mismo tiempo en otras carpetas: no toques nada fuera de la tuya.

**1. Marcas del ingrediente (`IngredientBrandsSection`).** Hoy solo muestra un texto provisional. Se dibuja dentro de un `Section` de la `List` de `IngredientDetailView` (línea 29), así que lo que devuelva son filas de lista. Conserva su inicializador `IngredientBrandsSection(ingredient:)`.
- Tiene su propio `@Observable` model que carga `GET /presentations/?ingredient_id=<id>&limit=100` al aparecer.
- Una fila por marca: arriba la marca y la tienda ("Selecta · Walmart"; sin tienda, solo la marca) en `.headline`; abajo, en `.subheadline` `.inkMuted`, el precio y el paquete ("$23.50 por 1,000 g", con `Money.format` y `Quantity.format` del `package_quantity` y la abreviatura de `base_unit`) y la antigüedad ("hoy", "hace 1 día", "hace 12 días" con `price_age_days`). Chips a la derecha o debajo en tamaños de accesibilidad: `price_is_stale` → `Chip("Precio viejo", tone: .warning)`; sin precio → `Chip("Falta precio", tone: .warning)`; `is_current` → `Chip("La que usamos", tone: .inProgress)`.
- Tocar una fila navega al detalle de la marca (punto 3). Deslizar para borrar con confirmación (`DELETE /presentations/{id}`); `IN_USE` → "Una receta usa esta marca. Cámbiala en la receta antes de borrarla."
- Última fila: botón de texto "Agregar marca" con ícono `plus.circle.fill` que abre el formulario del punto 2. Sin marcas, antes del botón: "Agrega dónde compras este ingrediente y cuánto cuesta." en `.inkMuted`.
- Mientras carga, una fila con `ProgressView`; si falla, una fila con el mensaje y un botón "Intentar de nuevo".

**2. Formulario de marca (`BrandFormView`, hoja), para crear y editar.**
- Barra: "Cancelar" a la izquierda; título "Nueva marca" o "Editar marca"; acción principal abajo "Guardar marca" (`.kitchenPrimary`).
- Campos: "Marca" (obligatorio, ej. "Selecta"); "Tienda" con un `Picker` de menú con las tiendas de `GET /suppliers/`, la opción "Sin tienda" y la opción "Nueva tienda…" que abre una alerta con un campo de texto, crea la tienda con `POST /suppliers/` y la deja elegida; "Tamaño del paquete": campo con teclado decimal y un `Picker` de unidad con las unidades de `GET /units/` cuya `baseUnit` es la del ingrediente (para la harina: g, kg, lb, oz); se manda `package_quantity` como cadena y `package_unit_id` de la unidad elegida, y el backend convierte. Solo al crear: "Precio" con teclado decimal, opcional, que se manda como `price_cents` en centavos enteros (convierte con `Decimal`, nunca `Double`).
- Crear: `POST /presentations/`. Editar: `PATCH /presentations/{id}` con marca, tienda (`null` para "Sin tienda") y paquete; el precio no se edita aquí.
- Errores dentro de la hoja: `INVALID_REFERENCE` → "Esa tienda o unidad ya no existe. Vuelve a abrir el formulario."; `UNIT_NOT_CONVERTIBLE` → el `detail` del backend; los demás, `localizedDescription`.

**3. Detalle de la marca (`BrandDetailView`).** Su inicializador recibe la `Presentation` y una función que avisa cuando cambió o se borró, para que la sección del punto 1 se recargue.
- Título inline con la marca. En la barra, "Editar" abre el formulario del punto 2.
- Arriba, tarjeta crema (`.softCard()`): el precio actual en `.title` heavy con cifras tabulares, debajo "por 1,000 g · Walmart" y la antigüedad; si `price_is_stale`, el chip "Precio viejo". Sin precio: "Todavía no tiene precio."
- Botón principal "Registrar precio" que abre una hoja con "Precio" (teclado decimal, obligatorio), "¿Cuándo lo pagaste?" (`DatePicker` de fecha, hoy por defecto, no permite fechas futuras) y "Nota" opcional; manda `POST /presentations/{id}/prices` con `price_cents`, `recorded_at` y `note`, y después recarga la marca con `GET /presentations/{id}` y el historial.
- "Historial de precios" (`.sectionTitleStyle()`): `GET /presentations/{id}/prices`, una fila por precio con el monto, la fecha en es-MX y la nota si existe; desde el segundo precio, en `.subheadline`, cuánto cambió respecto al anterior ("Subió $2.00", "Bajó $1.50", "Igual"), calculado en centavos enteros.

**4. Tiendas (`SuppliersView`).** Lista de `GET /suppliers/` (sin paginar) con `.searchable` local por nombre. Agregar con el "+" de la barra y renombrar tocando una fila, los dos con una alerta de un campo de texto (`POST /suppliers/` y `PATCH /suppliers/{id}`). Deslizar para borrar con la confirmación "Las marcas de esta tienda se quedan sin tienda." (`DELETE /suppliers/{id}`). Vacía: "Todavía no tienes tiendas" / "Agrega dónde compras: Walmart, Costco, el mercado…".

**5. Entrada a Tiendas.** En `CatalogView.swift` agrega solo un `ToolbarItem` en `.topBarLeading` con un botón de ícono `storefront` y etiqueta de accesibilidad "Tiendas" que abre `SuppliersView` en una hoja con "Listo" para cerrar. No cambies nada más de ese archivo.

**Criterios de aceptación.**
1. Crear la marca "Selecta" de la harina en la tienda nueva "Walmart", paquete 1 kg y precio 23.50 la muestra en el detalle del ingrediente como "Selecta · Walmart", "$23.50 por 1,000 g", con el chip "La que usamos".
2. Registrar un precio de 25.00 en esa marca actualiza la tarjeta, el historial muestra los dos precios con "Subió $1.50", y la fila del ingrediente se actualiza al regresar.
3. Una marca con precio de hace más de `price_stale_days` días muestra "Precio viejo" en la fila y en el detalle.
4. Borrar una tienda deja sus marcas sin tienda; borrar una marca fijada en una receta muestra el mensaje de `IN_USE`.
5. Ningún monto pasa por `Double`. Previews de la sección, el formulario, el detalle y las tiendas con datos de ejemplo, también en `.accessibility3`, sin montos cortados.
6. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra cambios dentro de `ios/aye-kitchen/aye-kitchen/Features/Catalog/`.

Si algo choca con el alcance (un modelo al que le falta un campo, un componente que no alcanza, un error de compilación fuera de tu carpeta), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
