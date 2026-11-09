Bloque I18. Rama `local-first`. Corre en paralelo con I16 (no comparten archivos). Después van I17 (Recetas) y luego I19 (Inicio).

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I18 de AyeKitchen iOS: Pedidos y Clientes con datos locales.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` y sigue **todas** las reglas de `docs/agy/_pantallas-locales.md`. Las reglas y consultas están en `ios/KitchenKit/Sources/KitchenDomain/Rules/OrderRules.swift`, `CustomerRules.swift` y, para el precio sugerido y el costo de una receta al agregarla, `Costing/` y `RecipeQueries.swift` (la lista de recetas con su costo).

**Contexto.** La app ya no le pide pedidos ni clientes al servidor: los lee y los guarda en el teléfono con `LocalStore`. Este bloque cambia esas pantallas, sin cambiar lo que la usuaria ve ni los textos.

**Alcance, solo en `ios/aye-kitchen/aye-kitchen/Features/Orders/` y `Features/Customers/`:** todos sus archivos (`OrdersView`, `OrdersModel`, `OrderDetailView`, `OrderDetailModel`, `OrderFormView`, `OrderFormModel`, `RecipePickerModel` y su hoja, `CustomerPickerSheet`, `RecordPaymentSheet`, `RecordPaymentModel`, `CurrencyMath`, `OrderMockData`, `CustomersView`, `CustomersModel`, `CustomerDetailView`, `CustomerDetailModel`, `CustomerFormView` y los que haya). Y, por la regla 4 de `_pantallas-locales.md`, las llamadas de una línea a tus vistas desde `Features/Home/`.

1. **Pedidos:** la lista con "Por entregar" / "Entregados" (entregados de los últimos 30 días, como hoy) agrupada por día, el detalle (líneas con "4 pz × $13.00" / "2 tandas × …", totales, pagos, estado, borrar), el formulario de crear/editar (cliente, entrega, notas, líneas por tanda o por pieza con su precio sugerido de KitchenKit, cantidad libre con stepper) y registrar/quitar pagos. Los errores `CUSTOMER_REQUIRED` y `PAYMENT_EXCEEDS_BALANCE` con los textos de hoy.
2. **Clientes:** lista con búsqueda, crear, editar, borrar, detalle con sus pedidos, y el selector de cliente del pedido (con "Crear …").
3. **Recetas en el pedido:** el selector de recetas y el precio sugerido salen de KitchenKit (lista de recetas activas con su costo; `suggestedPriceCents` y `suggestedPricePerYieldUnitCents` del costeo).
4. **Navegación por id:** `OrderDetailView(orderId:)`, `OrderFormView` con `.create` / `.edit(orderId:)`, `CustomerDetailView(customerId:)`. Ajusta las llamadas de `Features/Home/` a estas firmas, una línea cada una.

**Criterios de aceptación.**
1. En `Features/Orders/` y `Features/Customers/` no queda ningún `NetworkService`, `requestCaching`, `cached`, `ChangeTracker` ni tipo `Remote…`.
2. Con `LocalStore.preview()`, los previews muestran los pedidos de ejemplo (uno con pago parcial, uno por pieza, uno entregado).
3. En el simulador sin red: crear un pedido de 4 galletas por pieza para un cliente nuevo, registrar un pago, cambiarlo a "En proceso", editar la cantidad y borrarlo funcionan.
4. Build sin advertencias nuevas; `git status` solo muestra tu alcance (y las líneas de llamada ajustadas).

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. No dejes scripts auxiliares en el repo; si usas uno, bórralo al terminar. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `Features/Catalog/`.

### `FIN DEL PROMPT PARA GEMINI`
