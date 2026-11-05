Bloque K2c. Corre en paralelo con K2a y K2b (cada uno en sus propios archivos). Claude ya dejó en `ios/KitchenKit/Sources/KitchenDomain/`: `DomainError` con todos los códigos del contrato, `Rules/MutationContext.swift` (la convención de las reglas está en su comentario) y `Rules/SoftDelete.swift`. El costeo ya está en `Costing/` (K1).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque K2c de AyeKitchen: las reglas de clientes, pedidos, pagos, gastos y resumen en Swift.** Lee el comentario de `Rules/MutationContext.swift`, `Rules/SoftDelete.swift`, `Costing/DomainError.swift`, y en `docs/api-contract.md` las secciones `/customers`, `/orders` (incluidos "Cliente del pedido (B5)" y "Por tanda o por pieza (B7)"), `/expenses` y `/summary`. La referencia exacta del comportamiento es el backend: `backend/app/services/customer_service.py`, `order_service.py`, `expense_service.py`, `summary_service.py` y sus pruebas `backend/app/tests/test_customers.py`, `test_orders.py`, `test_expenses.py`, `test_summary.py`. Léelos, no los modifiques.

**Contexto.** La app pasa a guardar y calcular todo en el teléfono, sobre `KitchenData`. Este bloque traduce a Swift lo que hoy hace el servidor con clientes, pedidos, pagos, gastos y el resumen: mismas validaciones, mismos códigos, mismos textos de `detail` y los mismos centavos. Una diferencia con el backend: cada línea de pedido guarda `recipeName` (copia del nombre de la receta al crear la línea), que ya existe en `OrderItem`.

**Ya existe, no lo cambies:** todo lo que hay en `Sources/KitchenDomain/`. Para el precio sugerido y el costo de una receta usa `CostingIndex` / `KitchenData.calculateRecipeCost` de `Costing/` (con `suggestedPriceCents`, `suggestedPricePerYieldUnitCents`, `batchCostCents` y `costPerYieldUnit`); no lo dupliques.

**Alcance, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Rules/CustomerRules.swift` (nuevo)
- `Sources/KitchenDomain/Rules/OrderRules.swift` (nuevo)
- `Sources/KitchenDomain/Rules/ExpenseRules.swift` (nuevo)
- `Sources/KitchenDomain/Rules/SummaryQueries.swift` (nuevo)
- `Tests/KitchenDomainTests/OrderRulesTests.swift` (nuevo)

1. **Clientes:** crear, editar, borrar y listar con búsqueda por nombre o teléfono, como B5. Renombrar o cambiar el teléfono actualiza `customerName`/`customerPhone` (y su `updatedAt`) en los pedidos activos con ese cliente; borrar deja `customerId` nulo en ellos sin tocar el nombre.
2. **Pedidos:** crear, editar y borrar como B4, B4.1, B5 y B7: `customerRequired`, cliente que no existe (`invalidReference`), cantidad > 0, receta que no existe; por tanda o por pieza con su precio sugerido y snapshot de costo (`round_to_cents` del costo por unidad), `unitLabel` y `recipeName`; al editar, las líneas se conservan por la pareja (receta, modo) con su snapshot, `unitLabel`, `recipeName` y precio; `paymentExceedsBalance` si el total queda por debajo de lo pagado. Totales (`total`, `paid`, `balance`, `cost`, `profit`) en `Decimal` con un solo redondeo por total, como `compute_order_totals`. Listado con los filtros de hoy (estado, rango de `deliveryAt`, cliente) en el orden del contrato.
3. **Pagos:** agregar y quitar, con `paymentExceedsBalance` como el backend.
4. **Gastos:** crear, editar, borrar y listar con filtros, como B4.
5. **Resumen del mes** como `summary_service.py`, con los límites de mes en `settings.timezone`.
6. Define las estructuras de resultado con nombres que empiecen por `Order`, `Customer`, `Expense` o `Summary` para no chocar con otros bloques.
7. **Pruebas** en `OrderRulesTests.swift` (Swift Testing, con `MutationContext` de hora e ids fijos): traduce los casos de `test_customers.py`, `test_orders.py`, `test_expenses.py` y `test_summary.py` que apliquen (aislamiento entre usuarios no aplica), incluido el ejemplo de B7 (receta de 12 pz, tanda de $120 de costo, margen 30: por tanda 15600, por pieza 1300; 4 pz → total 5200, costo 4000), y además: una operación que lanza deja `KitchenData` igual que antes; un pedido conserva `recipeName` aunque la receta se borre.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las de hoy y las tuyas) sin advertencias nuevas.
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. Las ayudas privadas que necesites van como `private`/`fileprivate` dentro de tus archivos (otros bloques trabajan al mismo tiempo en el mismo paquete). No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: pueden ser de otra persona trabajando al mismo tiempo; solo no los incluyas en lo tuyo.

### `FIN DEL PROMPT PARA GEMINI`
