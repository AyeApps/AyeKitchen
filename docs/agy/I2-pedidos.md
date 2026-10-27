### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I2 de AyeKitchen iOS: Pedidos y pagos.** El backend ya está hecho y el esqueleto de la app de iPhone ya existe en `ios/aye-kitchen/aye-kitchen/`. Antes de empezar lee `GEMINI.md` completo (en especial "Reglas de iOS"), `DESIGN.md`, y en `docs/api-contract.md` la sección `/orders` y el campo `suggested_price_cents` de `GET /recipes/{id}/cost`.

**Alcance: solo la carpeta `ios/aye-kitchen/aye-kitchen/Features/Orders/`.** Hoy tiene `OrdersView.swift` con un estado vacío provisional; reemplázalo. Puedes crear los archivos que necesites dentro de esa carpeta. Usa sin modificarlos los modelos `Order`, `OrderItem`, `Payment`, `OrderStatus`, `RecipeListItem`, `RecipeCost` y `Page` de `Core/Models/`, `NetworkService.shared` y los componentes de `Design/` (en especial `StatusChip`).

**1. Lista de pedidos (`OrdersView`).**
- `NavigationStack` con título grande "Pedidos" y el "+" (`AddToolbarButton`, etiqueta "Nuevo pedido") que abre el formulario del punto 3 como hoja.
- Arriba, un `Picker` segmentado con "Por entregar" y "Entregados".
  - "Por entregar": dos peticiones en paralelo, `GET /orders/?status=pendiente&limit=100` y `GET /orders/?status=en_proceso&limit=100`, unidas y ordenadas por `delivery_at` de la más próxima a la más lejana. Los que ya pasaron su fecha salen primero, en una sección "Atrasados".
  - "Entregados": `GET /orders/?status=entregado&from=<hace 30 días>&limit=100`, del más reciente al más viejo.
- Secciones por día de entrega con encabezado "Hoy", "Mañana" o la fecha completa ("Sábado 26 de octubre"), en la zona horaria del teléfono y en es-MX.
- Cada fila como el artboard "Inicio — iPhone": a la izquierda una columna angosta con el día abreviado (SÁB, en `.tint` y peso heavy) sobre el número del día; al centro el nombre del cliente en `.headline` y debajo, en `.subheadline` `.inkMuted`, la hora y el primer pastel con su cantidad ("4:00 pm · Pastel de chocolate × 2", más "y 1 más" si hay más líneas); a la derecha el `StatusChip`. En tamaños de accesibilidad la columna del día y el chip pasan arriba y abajo del texto en vez de a los lados.
- `.refreshable`. Sin pedidos: "Todavía no hay pedidos" / "Toca + para anotar el primero." Error: `ErrorStateView`.

**2. Detalle del pedido (`OrderDetailView`).**
- Título inline con el nombre del cliente. En la barra, un menú "…" con "Editar pedido" (abre el formulario con los datos) y "Borrar pedido" (confirmación, `DELETE /orders/{id}`, regresa a la lista).
- Arriba: fecha y hora de entrega en `.title2` heavy, el teléfono como enlace que llama (`tel:`) si existe, y el estado. El estado se cambia con un `Menu` que lista los cuatro estados con su etiqueta y manda `PATCH /orders/{id}` solo con `status`.
- "Pasteles": una fila por línea con nombre de la receta, cantidad y el precio acordado por unidad; a la derecha el subtotal (cantidad × precio, calculado en centavos enteros).
- Tarjeta crema (`.softCard()`) con "Total", "Ya te pagaron" y "Te falta cobrar" (`balance_cents`, en `.tint` si es mayor que cero). Debajo, en `.subheadline` `.inkMuted`: "Te cuesta $X · Ganas $Y" con `cost_cents` y `profit_cents`.
- "Pagos": una fila por pago (monto, fecha, método si existe), deslizar para borrar con confirmación (`DELETE /orders/{id}/payments/{payment_id}`; la respuesta es el pedido actualizado: reemplaza el que tienes). Si `balance_cents` es mayor que cero, botón principal abajo "Registrar pago".
- "Notas" solo si tiene.
- Registrar pago (hoja): campo de monto con teclado decimal, ya escrito con el saldo pendiente; método con `Picker` segmentado "Efectivo", "Transferencia", "Tarjeta" (se manda "efectivo", "transferencia" o "tarjeta"); botón "Guardar pago". Convierte el monto escrito a centavos enteros con `Decimal` (nunca `Double`). `POST /orders/{id}/payments`; la respuesta es el pedido actualizado. `PAYMENT_EXCEEDS_BALANCE` → "Eso es más de lo que te falta cobrar."

**3. Formulario de pedido (`OrderFormView`, hoja), para crear y editar.** Su inicializador recibe el pedido a editar (o nulo para uno nuevo) y una función que se llama con el `Order` guardado; otra pantalla (Inicio) lo abrirá igual en el bloque siguiente.
- Barra: "Cancelar" a la izquierda; título "Nuevo pedido" o "Editar pedido". Acción principal abajo: "Guardar pedido".
- Campos: "Cliente" (obligatorio); "Teléfono" opcional con teclado de teléfono; "Entrega" con `DatePicker` de fecha y hora (para uno nuevo: mañana a las 4:00 pm); "Notas" opcional.
- "Pasteles": una fila por línea con el nombre de la receta, la cantidad con `Stepper` (de 1 en 1, mínimo 1) y el precio por unidad en un campo con teclado decimal. Botón de texto "Agregar pastel" abre una lista con búsqueda de `GET /recipes/?q=…&limit=50` (nombre de la receta; si `complete` es falso, `Chip` de advertencia "Falta precio"). Al agregar una receta, pide `GET /recipes/{id}/cost` y escribe en el campo de precio el `suggested_price_cents` con la etiqueta "Te sugerimos cobrar $X"; la usuaria puede cambiarlo. Deslizar para quitar una línea.
- Al editar, cada línea existente muestra su precio acordado (`unit_price_cents`) y no pide el costo de nuevo.
- Guardar: crear manda `POST /orders/` con `customer_name`, `customer_phone`, `delivery_at`, `notes` e `items` (`recipe_id`, `quantity` como string decimal, `unit_price_cents` en centavos enteros); editar manda `PATCH /orders/{id}` con los mismos campos y la lista completa de `items`. Deshabilitado sin cliente o sin al menos una línea.
- Errores dentro de la hoja: `PAYMENT_EXCEEDS_BALANCE` → "Con este cambio el total quedaría por debajo de lo que ya te pagaron."; `INVALID_REFERENCE` → "Una de las recetas ya no existe."; cualquier otro, `localizedDescription`.

**Criterios de aceptación.**
1. Crear un pedido con una receta toma el precio sugerido, aparece en "Por entregar" en el día correcto y su detalle muestra total, saldo y ganancia iguales a los que devuelve el backend.
2. Registrar un pago parcial baja "Te falta cobrar"; intentar pagar más del saldo muestra el mensaje del contrato y no cierra la hoja.
3. Cambiar el estado a "Entregado" lo saca de "Por entregar" y lo muestra en "Entregados".
4. Editar un pedido sin tocar el precio de una línea existente conserva su precio acordado.
5. Todo el dinero se calcula en centavos `Int` o `Decimal`, nunca `Double`.
6. Previews de la lista, el detalle y el formulario con datos de ejemplo, también en `.accessibility3`, sin montos cortados.
7. El build de la regla 12 de iOS termina en `BUILD SUCCEEDED`, y `git status` solo muestra cambios dentro de `ios/aye-kitchen/aye-kitchen/Features/Orders/`.

Si algo choca con el alcance (un modelo al que le falta un campo, un componente que no alcanza, un error de compilación fuera de tu carpeta), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
