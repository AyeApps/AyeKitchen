Bloque B5. Puede correr en paralelo con I7a e I8 (no comparten archivos). Claude ya dejó el esqueleto: modelo `Customer`, `Order.customer_id` con índice, el modelo registrado en `DOCUMENT_MODELS` y el router `/customers` montado y vacío.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque B5 del backend de AyeKitchen: clientes y su liga con los pedidos.** Relee "Reglas que no se rompen" en `GEMINI.md`, la sección `/customers` de `docs/api-contract.md`, el párrafo "Cliente del pedido (B5)" de `/orders` y el código `CUSTOMER_REQUIRED` en la tabla de errores.

**Ya existe, no lo cambies:** el modelo `Customer` en `backend/app/models/customer.py`, con `name`, `phone` y `notes`; el campo `customer_id` de `Order` en `backend/app/models/order.py`; el registro en `app/db/mongodb.py`; y el router vacío en `app/api/v1/endpoints/customers.py`, montado en `/customers`.

**Alcance, dentro de `backend/app/`:**
- `api/v1/endpoints/customers.py` (llenar)
- `schemas/customer.py` (nuevo)
- `services/customer_service.py` (nuevo)
- `tests/test_customers.py` (nuevo)
- `schemas/order.py`
- `services/order_service.py`
- `api/v1/endpoints/orders.py`
- `tests/test_orders.py`

Para clientes, copia la estructura de proveedores: `schemas/supplier.py`, `services/supplier_service.py` y `api/v1/endpoints/suppliers.py`.

1. **CRUD de clientes**, como lo dice el contrato:
   - **Lista** sin paginar, ordenada por nombre. El parámetro opcional `q` filtra los clientes cuyo nombre o teléfono contengan el texto, sin distinguir mayúsculas. Escapa el texto con `re.escape`, como `supplier_service`.
   - **Crear** responde 201. Recorta los espacios de nombre y teléfono. Un teléfono vacío se guarda como nulo. Un nombre repetido (sin distinguir mayúsculas, en el mismo workspace, entre clientes no borrados) responde 409 `DUPLICATE_NAME` con el texto "Ya existe un cliente con ese nombre".
   - **Ver uno.**
   - **Editar** es parcial, con el mismo chequeo de nombre repetido que excluye al propio cliente. Si cambian el nombre o el teléfono, actualiza de una vez (`update_many` o equivalente) `customer_name` y `customer_phone` de todos los pedidos no borrados del mismo workspace con ese `customer_id`. También actualiza su `updated_at`.
   - **Borrar** es soft delete y responde 204. Después, a los pedidos del workspace con ese `customer_id` les pone `customer_id` en nulo, sin tocar su nombre ni su teléfono.
   - Un id inválido, borrado o de otro workspace responde 404 `NOT_FOUND` con "Cliente no encontrado".
2. **Pedidos.**
   - **Schemas.** `OrderCreate` gana `customer_id` opcional, y su `customer_name` pasa a opcional con los mismos límites (de 1 a 120). `OrderUpdate` gana `customer_id` opcional. `OrderResponse` gana `customer_id: str | None`, y `serialize_order` lo llena.
   - **`create_order`.** Si viene `customer_id`, busca al cliente con el servicio de clientes (mismo workspace, no borrado). Si no existe, responde 422 `INVALID_REFERENCE`. Si existe, guarda `customer_id` y copia el nombre y el teléfono del cliente a `customer_name` y `customer_phone`, ignorando los que vengan en el cuerpo. Si no viene `customer_id` y tampoco `customer_name` (o viene vacío), responde 422 `CUSTOMER_REQUIRED` con "Elige un cliente o escribe su nombre". Si no viene `customer_id` pero sí nombre, todo funciona como hoy.
   - **`update_order`.**
     - Si `customer_id` está en `model_fields_set` y no es nulo: valida igual que al crear y copia el nombre y el teléfono del cliente.
     - Si está en el set y es nulo: desliga el pedido. Conserva el nombre y el teléfono actuales, salvo que el mismo cuerpo traiga otros.
     - Si el pedido queda ligado a un cliente, ignora `customer_name` y `customer_phone` del cuerpo.
     - Si no queda ligado, aplícalos como hoy.
   - **`list_orders`** gana el filtro opcional `customer_id`, y el endpoint lo recibe como query `customer_id`.
3. **Pruebas.**
   - En `test_customers.py`:
     - CRUD completo.
     - Nombre repetido sin distinguir mayúsculas, al crear y al renombrar.
     - Búsqueda `q` por nombre y por teléfono.
     - Editar el nombre de un cliente cambia `customer_name` en sus pedidos.
     - Borrar un cliente deja sus pedidos con `customer_id` nulo y con el nombre intacto.
     - Aislamiento entre `auth_headers` y `auth_headers_user_2`: no ve, no edita, no borra, y no puede usar el `customer_id` del otro en un pedido.
   - En `test_orders.py`:
     - Crear con `customer_id` copia el nombre y el teléfono.
     - `customer_id` inexistente → `INVALID_REFERENCE`.
     - Sin cliente ni nombre → `CUSTOMER_REQUIRED`.
     - El filtro `?customer_id=` funciona.
     - PATCH con `customer_id: null` desliga y conserva el nombre.
     - Los pedidos sin cliente siguen funcionando como antes.

**Criterios de aceptación.**
1. Las tres verificaciones de la regla 9 de `GEMINI.md` pasan: pytest con mongomock, pytest contra Mongo real en el puerto 27018 y ruff. Hoy pasan 88 pruebas; ninguna de las existentes debe cambiar su resultado.
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance (un test, el linter, un tipo), detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar.

### `FIN DEL PROMPT PARA GEMINI`
