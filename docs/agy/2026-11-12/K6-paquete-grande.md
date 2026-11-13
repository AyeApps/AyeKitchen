Bloque K6. Rama `main`. Corre en paralelo con I32 (I32 solo toca `Features/`). Pedido del usuario (2026-11-12): poder registrar paquetes grandes, por ejemplo una reja de Costco de 24 botes de leche de 900 ml, y que la app sepa cuántas piezas trae y cuánto trae cada una. Claude ya dejó el esqueleto: los campos `packCount` y `packItemQuantity` en `Presentation` (con su `init`), sus atajos en `CatalogPresentation`, y los parámetros nuevos en `createPresentation` / `updatePresentation` (hoy se ignoran, marcados con "ESQUELETO K6"). También `docs/backup-format.md` ya describe `pack_count` y `pack_item_quantity`.

### PROMPT PARA GEMINI — copiar desde aquí

**Bloque K6 de AyeKitchen: paquete grande en las marcas (KitchenKit).** Trabaja en la rama `main`. Antes de escribir, lee: `docs/backup-format.md` (presentaciones: `pack_count`, `pack_item_quantity`), `ios/KitchenKit/Sources/KitchenDomain/Entities.swift` (`Presentation`), `Rules/CatalogRules.swift` (`createPresentation` y `updatePresentation`, busca los comentarios "ESQUELETO K6"), `Rules/CatalogQueries.swift` (`CatalogPresentation`), `Costing/CostingIndex.swift` (`convertToBase` y donde se arma `presentationLabel`), `Costing/CostingMath.swift` (`roundToCents`) y `Qty` en `KitchenData.swift`.

**Idea.** Una marca puede ser un paquete grande: trae `packCount` piezas (24 botes) y cada pieza trae `packItemQuantity` en la unidad base del ingrediente ("900" ml). `packageQuantity` sigue siendo el total (24 × 900 = "21600") y es lo único que usa el costeo: el costeo NO cambia. El precio registrado es el de todo el paquete. Si `packCount` es nulo, la marca es un paquete simple como hoy, y `packItemQuantity` también es nulo (nunca uno sin el otro).

**Alcance cerrado, solo dentro de `ios/KitchenKit/`:**
- `Sources/KitchenDomain/Rules/CatalogRules.swift`: solo el cuerpo de `createPresentation` y `updatePresentation` (las firmas ya están; no las cambies) y quitar los comentarios "ESQUELETO K6".
- `Sources/KitchenDomain/Rules/CatalogQueries.swift`: solo agregar `pricePerPackItemCents` a `CatalogPresentation`.
- `Sources/KitchenDomain/Costing/CostingIndex.swift`: solo el texto de `presentationLabel`.
- `Tests/KitchenDomainTests/PackRulesTests.swift` (nuevo).
- No toques `Entities.swift` (ya tiene los campos), ni otros archivos, ni nada fuera de `ios/KitchenKit/`.

**Lo que ya existe y no cambia:** el formato de `packageQuantity` (texto decimal con `Qty.text`, en unidad base), el cálculo de costos, el resto de validaciones de las dos reglas (marca, tienda, código de barras, precio) y sus mensajes, y todas las pruebas existentes.

**Requisitos.**
1. **`createPresentation` con paquete grande.** Si `packCount` llega no nulo:
   - Debe estar entre 1 y 10 000; si no, `DomainError.invalidValue` con "Las piezas del paquete deben ser entre 1 y 10,000".
   - `packItemQuantity` es obligatorio y debe ser un número mayor que cero (`Qty.decimal`); si falta o no lo es, `invalidValue` con "Indica cuánto trae cada pieza".
   - Convierte `packItemQuantity` a la unidad base con `convertToBase` usando `packItemUnitId` (nulo o vacío = ya está en la unidad base), igual que hoy se convierte `packageQuantity` con `packageUnitId`; si no se puede convertir, deja pasar el error de `convertToBase` tal cual.
   - Guarda `packCount`, `packItemQuantity` = la cantidad por pieza ya convertida (`Qty.text`) y `packageQuantity` = `packCount` × esa cantidad (`Qty.text`). En este caso se ignoran `packageQuantity` y `packageUnitId` que lleguen como parámetro (la pantalla manda ahí el número de piezas; no lo valides contra nada más que lo que ya se valida hoy).
   - Si `packCount` es nulo, todo funciona como hoy y los campos del paquete quedan nulos (aunque llegue `packItemQuantity`).
2. **`updatePresentation`.** El parámetro `packCount` es doble opcional, como `supplierId`:
   - No mandado (`nil`): si llega `packageQuantity`, se actualiza el total como hoy y además se borran `packCount` y `packItemQuantity` (el total ya no corresponde al paquete). Si tampoco llega `packageQuantity`, el paquete queda como estaba.
   - `.some(nil)`: se borran los dos campos del paquete; si llega `packageQuantity` se usa como hoy, si no, el total se queda igual.
   - `.some(n)`: mismas validaciones y cálculo que en el punto 1 (con `packItemQuantity` y `packItemUnitId`, usando el ingrediente de la marca); se ignora `packageQuantity`.
3. **Precio por pieza.** En `CatalogPresentation` agrega `public var pricePerPackItemCents: Int?`, calculado: `latestPriceCents` ÷ `packCount` con un solo redondeo (`CostingMath.roundToCents`); nulo si no hay paquete o no hay precio.
4. **Etiqueta en el costeo.** Donde `CostingIndex` arma `presentationLabel`, si la marca tiene paquete la parte de la cantidad dice "24 × 900 ml" (`packCount` × `packItemQuantity` y la unidad base) en vez de "21600 ml"; el resto de la etiqueta (marca, tienda, separador " · ") igual. Sin paquete, exactamente como hoy (los casos de `Fixtures/costing_cases.json` no deben cambiar).
5. **Pruebas** en `PackRulesTests.swift`, con `MutationContext` de hora e ids fijos, como las demás pruebas de reglas:
   - Leche (base ml): crear marca con 24 piezas de 900 ml → total "21600", `packCount` 24, `packItemQuantity` "900"; con 24 piezas de 0.9 l (`sys.l`) da lo mismo.
   - Crear con `packCount` 0, 10 001, y sin `packItemQuantity` → los errores del punto 1.
   - Pieza en una unidad que no se convierte (por ejemplo `sys.kg` para leche) → el error de `convertToBase`.
   - Crear sin paquete → campos nulos, como hoy.
   - Update: cambiar a 12 piezas de 1 l; quitar el paquete con `.some(nil)` (con y sin `packageQuantity`); mandar solo `packageQuantity` borra el paquete; editar solo la marca no lo toca.
   - `pricePerPackItemCents`: reja de 24 a $389.00 → 1621 centavos; sin precio → nulo; sin paquete → nulo.
   - La receta que usa esa leche cuesta lo mismo que con una marca simple de 21600 ml al mismo precio.
   - Ida y vuelta por `KitchenCoding` con paquete (JSON con `pack_count` y `pack_item_quantity`) y lectura de un JSON viejo sin esos campos (quedan nulos).
   - La etiqueta del punto 4 con y sin paquete.

**Criterios de aceptación.**
1. Desde `ios/KitchenKit/`, `swift test` pasa (las 107 de hoy y las tuyas) sin advertencias nuevas; ninguna prueba existente cambia.
2. `git status` solo muestra los archivos del alcance.
3. Las firmas públicas de `createPresentation` y `updatePresentation` quedan idénticas a las del esqueleto (I32 ya las usa).

Si algo choca con el alcance (una prueba, un tipo, el linter), detente y pregunta en vez de cambiar código fuera del alcance. No dejes scripts de ayuda: bórralos. No reviertas cambios que veas en archivos fuera de tu alcance (otro agente puede estar trabajando en `Features/`).

### FIN DEL PROMPT PARA GEMINI
