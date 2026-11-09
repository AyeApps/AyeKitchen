Bloque K5. Rama `local-first`. Puede correr en paralelo con I30 (I30 solo toca `Features/`). Después va I31 (pantallas). Pedido del usuario (2026-11-06): "Tu precio" en cada receta además del sugerido, ver el porcentaje de ganancia, y que un pedido diga cuántas tandas hay que hacer (1.5, o 2 y lo que sobra para vender). Claude ya dejó los campos nuevos en `docs/backup-format.md`.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque K5 de AyeKitchen: precio propio de una receta, porcentaje de ganancia y tandas por pedido, en KitchenKit.** Trabaja en la rama `local-first`. Lee `docs/backup-format.md` (receta: `sale_price_cents`, `sale_price_sold_by`), `ios/KitchenKit/Sources/KitchenDomain/Entities.swift` (`Recipe`, `OrderItem`, `OrderSoldBy`), `Rules/RecipeRules.swift` (`updateRecipe`), `Rules/OrderRules.swift` (`OrderTotals`, `createOrder`/`updateOrder` y cómo eligen el precio de cada línea), `Costing/CostingModels.swift` (`RecipeCost`), `Costing/CostingMath.swift` y `Qty` en `KitchenData.swift`. Dinero siempre en centavos enteros, cálculo con `Decimal` y **un solo redondeo** por número mostrado (`CostingMath.roundToCents`), como el resto del paquete.

**Alcance, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Entities.swift`: solo agregar los dos campos de `Recipe` (y su `init` con valores por defecto `nil`).
- `Sources/KitchenDomain/Rules/RecipeRules.swift`: solo agregar los dos parámetros a `updateRecipe`.
- `Sources/KitchenDomain/Rules/OrderRules.swift`: solo el precio por defecto de una línea y `profitPercent` en `OrderTotals`.
- `Sources/KitchenDomain/Rules/SalesQueries.swift` (nuevo): todo lo demás.
- `Tests/KitchenDomainTests/SalesQueriesTests.swift` (nuevo).

1. **Campos de `Recipe`:** `salePriceCents: Int?` y `salePriceSoldBy: OrderSoldBy?` (JSON `sale_price_cents`, `sale_price_sold_by`). Opcionales: un archivo o respaldo viejo sin ellos se lee igual (no subas `schema_version`). Nulos = sin precio propio.
2. **`updateRecipe(... salePriceCents: Int?? = nil, salePriceSoldBy: OrderSoldBy?? = nil ...)`** con el mismo estilo de doble opcional que `marginPercent` (no mandarlo = no cambia; `.some(nil)` = quitar). Valida: precio > 0 y ≤ 100 000 000 centavos (`invalidValue` "El precio debe ser mayor a $0"); si se quita el precio, `salePriceSoldBy` también queda nulo; si se pone precio sin forma de venta, queda `.batch`.
3. **Porcentaje de ganancia** (en `SalesQueries.swift`): `public struct Profit: Sendable, Hashable` con `priceCents`, `costCents`, `profitCents` (precio − costo, puede ser negativo) y `percent: Int?` = ganancia ÷ costo × 100, redondeado a entero, **sobre el costo** (igual que el margen de la app: con margen 40 % el sugerido da 40 %). `nil` si el costo es 0. Un `static func make(priceCents:costCents:)`.
   - `OrderTotals`: agrega `public var profitPercent: Int?` calculado (ganancia ÷ costo) **sin cambiar su `init`**.
4. **Precio propio de una receta:** `public struct RecipeSalePrice: Sendable, Hashable` con `soldBy`, `batch: Profit` y `perUnit: Profit` (por unidad de rendimiento). `public func salePrice(of recipe: Recipe, cost: RecipeCost) -> RecipeSalePrice?` (nulo si no tiene precio propio). Si está por tanda: precio por unidad = precio ÷ rendimiento; si está por unidad: precio por tanda = precio × rendimiento. Costo por tanda `cost.batchCostCents`; por unidad, `cost.costPerYieldUnit` redondeado una vez.
   - También `public func suggestedProfit(cost: RecipeCost) -> Profit` (precio sugerido por tanda contra su costo) para que la pantalla muestre el % junto al sugerido.
5. **Precio por defecto de una línea de pedido:** `public func defaultLinePriceCents(recipeId: String, soldBy: OrderSoldBy, cost: RecipeCost) -> Int`: si la receta tiene precio propio, ese precio en la forma de la línea (convertido como en 4); si no, el sugerido (`suggestedPriceCents` o `suggestedPricePerYieldUnitCents`). Úsalo en `createOrder`/`updateOrder` donde hoy se toma el sugerido cuando la línea no trae precio (`it.unitPriceCents ?? …`); nada más cambia ahí.
6. **Tandas de un pedido:** `public struct BatchNeed: Sendable, Hashable, Identifiable` (id = recipeId) con `recipeId`, `recipeName`, `yieldQuantity: String`, `yieldUnit: BaseUnit`, `neededUnits: String` (decimal), `exactBatches: String` (decimal, hasta 2 decimales), `wholeBatches: Int` (redondeo hacia arriba), `leftoverUnits: String` (decimal, `wholeBatches` × rendimiento − necesario) y `leftoverValueCents: Int?` (lo que sobra × precio por unidad: el propio si tiene, si no el sugerido; nulo si no sobra nada).
   - `public func batchNeeds(for order: Order) -> [BatchNeed]`: junta las líneas de la misma receta; una línea por tanda suma cantidad × rendimiento, una por unidad suma su cantidad. Usa la receta activa actual para el rendimiento; si la receta ya no existe, sáltala. Orden: el de las líneas del pedido.
   - `public func batchNeeds(for orders: [Order]) -> [BatchNeed]`: lo mismo sumando varios pedidos (para una vista de la semana más adelante).
   - Para el costo y el sugerido usa el motor de costeo que ya existe (como lo hace `createOrder`); no dupliques fórmulas.
7. **Pruebas** (`MutationContext` con hora e ids fijos): leer un respaldo/JSON sin los campos nuevos; poner, cambiar y quitar el precio propio (y los errores); `Profit` con ganancia, pérdida y costo 0; el sugerido con margen 40 % da 40 %; `RecipeSalePrice` por tanda y por unidad (con rendimiento 12 y 1); el precio por defecto de una línea con y sin precio propio, por tanda y por unidad; `batchNeeds` con: 18 tandas (18 exactas, nada sobra), 15 piezas de una receta que rinde 10 (1.5 exactas, 2 enteras, sobran 5 con su valor), dos líneas de la misma receta (una por tanda y otra por pieza) que se suman, receta borrada que se salta, y varios pedidos; ida y vuelta por `KitchenCoding`.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las 99 de hoy y las tuyas) sin advertencias nuevas; ninguna prueba existente cambia.
2. `git status` solo muestra los archivos del alcance.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No compiles la app de iOS. No dejes scripts auxiliares en el repo. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente puede estar trabajando en `ios/aye-kitchen/`.

### `FIN DEL PROMPT PARA GEMINI`
