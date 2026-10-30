Bloques I7a e I7b.
- **I7a** puede correr en paralelo con B5 e I8. Se escribe contra el contrato, y para probarlo con datos reales espera a que B5 esté auditado.
- **I7b** va después de I7a y de I8, porque toca `OrderFormView.swift`, igual que I8, y usa `CustomerFormView`, que crea I7a.

Claude ya dejó en `Core/Models/` el modelo `Customer` (`Customers.swift`) y `Order.customerId`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I7a de AyeKitchen iOS: pantalla de Clientes.** Relee "Reglas de iOS" en `GEMINI.md` y la sección `/customers` de `docs/api-contract.md`. La respuesta usa el modelo `Customer` de `Core/Models/Customers.swift`, que ya existe; no declares otro.

**Alcance, dentro de `ios/aye-kitchen/aye-kitchen/`:** los archivos nuevos de `Features/Customers/`: `CustomersModel.swift`, `CustomersView.swift`, `CustomerFormView.swift`, `CustomerDetailModel.swift` y `CustomerDetailView.swift`. Además, `Features/Orders/OrdersView.swift`, solo para el botón del punto 1.

1. **Entrada.** En la barra de `OrdersView` (línea 13) agrega un `ToolbarItem(placement: .topBarLeading)` con `Image(systemName: "person.2")` y `accessibilityLabel("Clientes")`. Abre `CustomersView` como hoja. Copia cómo `CatalogView` abre Tiendas (líneas 34 a 41 y 49).
2. **`CustomersView` + `CustomersModel`.** Copia el estilo de `Features/Catalog/SuppliersView.swift`:
   - `NavigationStack` con el título "Clientes", "Listo" a la izquierda para cerrar y `AddToolbarButton(label: "Nuevo cliente")` a la derecha.
   - `.searchable` con el texto "Buscar cliente". La búsqueda llama `GET /customers/?q=` con una espera de unos 300 ms, como la búsqueda del Catálogo, y la lista vacía llama `GET /customers/`.
   - `.refreshable`, y `ErrorStateView` si la carga falla.
   - Cada fila muestra el nombre en `.body.weight(.semibold)` y, debajo, el teléfono en `.inkMuted` si existe. Al tocarla, navega a `CustomerDetailView`.
   - Al deslizar se puede borrar, con confirmación: "¿Borrar a <nombre>?" y el texto "Sus pedidos se conservan.".
   - Sin clientes, `ContentUnavailableView` con `person.2`, "Todavía no tienes clientes" y "Agrégalos aquí o al crear un pedido.".
   - Expón en el modelo un método para agregar o reemplazar un cliente por id, ordenado por nombre. Lo usa I7b.
3. **`CustomerFormView`.** Es una hoja para crear o editar, con el inicializador `CustomerFormView(customer: Customer? = nil, initialName: String = "", onSave: @escaping (Customer) -> Void)`.
   - Título "Nuevo cliente" o "Editar cliente", y "Cancelar" a la izquierda.
   - Campos `KitchenTextField`: "Nombre" (capitalización `.words`, `contentType` `.name`), "Teléfono" (teclado `.phonePad`, `contentType` `.telephoneNumber`) y "Notas", con el ejemplo "Ej. Le gusta poco dulce, recoge en la tarde".
   - Botón principal abajo, "Guardar cliente", con `.kitchenPrimary`. Solo se activa si el nombre sin espacios tiene de 1 a 120 caracteres.
   - Crear es `POST /customers/`; editar es `PATCH /customers/{id}`. En PATCH manda solo nombre, teléfono y notas, con nulo si quedan vacíos.
   - `DUPLICATE_NAME` muestra "Ya tienes un cliente con ese nombre." en el recuadro de error de `LoginView` (líneas 77 a 84). Con éxito, llama `onSave` con el cliente que devolvió el servidor y cierra la hoja.
   - En modo mock no hay red: devuelve un `Customer` armado con los datos.
4. **`CustomerDetailView` + `CustomerDetailModel`.**
   - Título inline con el nombre.
   - Arriba, el teléfono como enlace `tel:`, igual que `OrderDetailView` (líneas 151 a 163), y las notas en `.softCard()` si existen.
   - En la barra, "Editar" abre `CustomerFormView` con el cliente. Al guardar, la vista se actualiza y avisa a la lista con un closure `onCustomerUpdated`.
   - Sección "Pedidos" con `GET /orders/?customer_id=<id>&limit=100`; el modelo `Page<Order>` ya existe. Cada fila muestra:
     - la fecha de entrega con `OrderDateFormatter`;
     - el `StatusChip` del estado;
     - el total con `Money.format(cents:)` y `.monospacedDigit()`;
     - el saldo en `.warningText` si es mayor que cero.

     Sin pedidos: "Todavía no tiene pedidos.".
   - Tocar un pedido navega a `OrderDetailView(order:onOrderUpdated:onOrderDeleted:)`. Registra `navigationDestination(for: Order.self)` dentro del `NavigationStack` de `CustomersView`, porque es otra pila que la de Pedidos. Al actualizar o borrar, recarga la sección.
5. **Previews** de las tres vistas, con clientes de ejemplo de distintos negocios de comida (no solo pasteles), más una con `.dynamicTypeSize(.accessibility3)`.

**Criterios de aceptación** (con B5 ya en el backend local).
1. En Pedidos, el botón de personas abre Clientes. Creo "Ana Ruiz" con su teléfono, aparece en la lista, y buscar "ana" o parte del teléfono la encuentra.
2. Crear otro "ana ruiz" muestra "Ya tienes un cliente con ese nombre.".
3. Edito su nombre y el cambio se ve en la lista y en el detalle.
4. Al borrarla con confirmación, desaparece.
5. El detalle lista los pedidos del cliente y abre el detalle del pedido.
6. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`

---

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I7b de AyeKitchen iOS: elegir o crear el cliente al hacer un pedido.** I7a ya está hecho (`Features/Customers/`, con `CustomerFormView(customer:initialName:onSave:)` y `CustomersModel`). I8 también: la sección se llama "Productos". Relee "Reglas de iOS" en `GEMINI.md` y el párrafo "Cliente del pedido (B5)" de `/orders` en `docs/api-contract.md`. `Order.customerId` ya existe en `Core/Models/Orders.swift`.

**Alcance, dentro de `ios/aye-kitchen/aye-kitchen/`:** `Features/Orders/OrderFormView.swift`, `Features/Orders/OrderFormModel.swift` y el archivo nuevo `Features/Orders/CustomerPickerSheet.swift`. Usa `CustomerFormView` y `CustomersModel` sin modificarlos.

1. **Modelo del formulario.**
   - `OrderFormModel` gana `customerId: String?`. Al editar, se llena con `order.customerId`.
   - Agrega un método `selectCustomer(_:)` que pone `customerId`, `customerName` y `customerPhone` desde el `Customer`, con el teléfono vacío si es nulo.
   - `OrderCreateBody` y `OrderUpdateBody` ganan `customerId: String?`. En `OrderUpdateBody`, el `encode(to:)` propio lo manda con `encodeIfPresent`; nunca manda nulo en este bloque.
   - Al guardar se envía `customerId` y se siguen enviando `customerName` y `customerPhone`. Con `customerId`, el backend los ignora y copia los del cliente.
   - La validación para guardar cambia la regla del nombre: se puede guardar si hay `customerId`, o si se está editando un pedido viejo sin cliente y su nombre no está vacío. Las demás reglas no cambian.
2. **Formulario.** En `inputFields`, quita los `KitchenTextField` "Cliente" y "Teléfono" (líneas 72 a 81). En su lugar va una fila tocable con el título "Cliente" en el mismo estilo de "Entrega":
   - Con cliente: el nombre en `.body.weight(.semibold)`, el teléfono debajo en `.inkMuted` si existe y un `chevron.right`.
   - Sin cliente en un pedido nuevo: "Elige un cliente" en `.inkMuted`.
   - Pedido viejo con nombre pero sin `customerId`: el nombre y, debajo, "Sin guardar en Clientes" en `.inkMuted`.
   - Al tocar la fila se abre `CustomerPickerSheet`. Usa el fondo y el radio de `KitchenTextField` para que se vea como un campo.
3. **`CustomerPickerSheet`.**
   - `NavigationStack` con el título "Cliente", "Cancelar" a la izquierda y `.searchable` "Buscar cliente". Carga y busca con `CustomersModel`.
   - Primera fila siempre visible: un botón con `plus.circle.fill`, "Nuevo cliente", o "Crear “<búsqueda>”" si hay texto. Usa el mismo estilo del botón "Nuevo ingrediente" de `Features/Recipes/RecipeItemPicker.swift` (líneas 103 a 114).
   - Debajo, los clientes, con su nombre y teléfono. Tocar uno llama `onSelect(customer)` y cierra la hoja.
   - El botón de crear abre `CustomerFormView(initialName: <búsqueda sin espacios>)` como hoja. Copia el patrón de I5b en `RecipeItemPicker` (líneas 72 a 86): guarda el cliente en un estado pendiente en `onSave`. En el `onDismiss` de esa hoja, si hay pendiente, llama `onSelect` con él y cierra el selector. No presentes dos hojas a la vez.
   - Con la lista vacía y sin búsqueda: "Todavía no tienes clientes." debajo del botón.

**Criterios de aceptación** (con B5 en el backend local).
1. Al hacer un pedido nuevo, el botón "Guardar pedido" está desactivado hasta elegir un cliente.
2. Toco "Cliente", busco "Luis", toco "Crear “Luis”" y guardo con teléfono. La fila del formulario muestra Luis y su teléfono. Guardo el pedido y el detalle muestra a Luis con su teléfono. En Clientes, el detalle de Luis lista ese pedido.
3. Elijo un cliente existente y el pedido se guarda ligado: en la red, el body lleva `customer_id`.
4. Un pedido viejo sin cliente abre con su nombre y "Sin guardar en Clientes". Lo puedo guardar sin cambiar el cliente, o elegir uno para ligarlo.
5. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED` sin advertencias nuevas, y `git status` solo muestra los tres archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
