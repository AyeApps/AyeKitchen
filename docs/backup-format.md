# AyeKitchen — Formato de datos local y del respaldo (v1)

Desde 2026-11-05 la app funciona **local**: todos los datos viven en el teléfono y todo se calcula ahí. El servidor solo sirve para entrar (aye-auth) y para **guardar respaldos** (`/backup`, ver `api-contract.md`). Un dispositivo por cuenta.

El archivo local de la app y el respaldo son **el mismo documento JSON**. El código canónico es `ios/KitchenKit/Sources/KitchenDomain/` (`Entities.swift`, `KitchenData.swift`, `SystemUnits.swift`); este archivo lo describe para el backend.

## Reglas generales

- **Llaves en snake_case.** Fechas ISO 8601 en UTC con milisegundos y `Z` (`2026-11-05T16:56:13.264Z`). Al leer se aceptan también sin zona (= UTC) y con microsegundos.
- **Ids:** texto. Los que vienen del servidor conservan su ObjectId (24 hex); los nuevos los crea el teléfono (UUID). Nunca se reusan.
- **Cantidades:** texto decimal (`"1000"`, `"0.5"`), nunca número JSON. **Dinero:** enteros en centavos (`*_cents`).
- **Borrado:** nada se quita de las listas; se marca `deleted_at`. Las pantallas y el costeo ignoran lo borrado, salvo para mostrar nombres viejos.
- Todo documento de las listas tiene `id`, `created_at`, `updated_at` y `deleted_at` (nulo si no está borrado), salvo donde se indica.
- `schema_version` sube solo con cambios que una app vieja no sabría leer. Una app que recibe una versión mayor no la lee (pide actualizar).
- **Cambios que solo agregan** (un campo o una lista nueva) no suben la versión: al leer, una lista que falta es vacía y un campo opcional que falta es nulo. Campos que ya no existen se ignoran (por ejemplo `photo_id`, que hubo antes de las referencias).

## Documento

```
{
  schema_version: 1,
  exported_at, device_id,
  settings: {name, currency, timezone, default_margin_percent, price_stale_days},
  units:          [{id, name, abbreviation, base_unit: "g"|"ml"|"pz", factor_to_base, ...}],   # solo las del negocio
  ingredients:    [{id, name, base_unit, group, notes, conversions: [{unit_id, quantity_in_base}], reference_ids, ...}],
  suppliers:      [{id, name, notes, ...}],
  presentations:  [{id, ingredient_id, brand, supplier_id, package_quantity, barcode, reference_ids, ...}],
  # pack_count / pack_item_quantity (K6, opcionales): paquete grande, p. ej. una reja de 24 botes de 900 ml =
  # pack_count 24, pack_item_quantity "900" (en la base_unit del ingrediente); package_quantity sigue siendo
  # el total (24 × 900 = "21600") y es lo único que usa el costeo. Nulos = paquete simple.
  price_records:  [{id, presentation_id, price_cents, recorded_at, note, ...}],
  recipes:        [{id, name, description,
                    items: [{kind: "ingredient"|"recipe", ref_id, quantity, unit_id, pinned_presentation_id}],
                    extra_costs: [{name, cost_cents}],
                    yield_quantity, yield_unit, servings, margin_percent, reference_ids,
                    sale_price_cents, sale_price_sold_by, ...}],
  # sale_price_cents / sale_price_sold_by (K5, opcionales): "Tu precio" de la receta, por tanda ("batch")
  # o por unidad de rendimiento ("unit"); nulos = sin precio propio (se usa el sugerido).
  cost_versions:  [{id, recipe_id, name, choices: [{ingredient_id, presentation_id}], ...}],
  customers:      [{id, name, phone, notes, ...}],
  orders:         [{id, customer_id, customer_name, customer_phone, delivery_at, status, notes, reference_ids,
                    items: [{recipe_id, recipe_name, sold_by: "batch"|"unit", unit_label, quantity,
                             unit_price_cents, unit_cost_cents_snapshot}],
                    payments: [{id, amount_cents, paid_at, method}], ...}],     # items y payments sin created_at/deleted_at
  expenses:       [{id, description, amount_cents, spent_at, category, supplier_id, reference_ids, ...}],
  references:     [{id, content_type, size_bytes, width, height, sha256, ...}]      # imágenes de referencia; los bytes van aparte
}
```

`status`: `pendiente`, `en_proceso`, `entregado`, `cancelado`.

## Referencias (imágenes opcionales)

Ingredientes, marcas, recetas, pedidos y gastos pueden tener hasta 5 imágenes de referencia opcionales (`reference_ids`, ids de `references`; nulo = ninguna). No son la imagen de la cosa en la interfaz: son un apoyo (el empaque de la marca, el pastel terminado, la receta escrita, el diseño que pidió el cliente, el ticket).

- El documento solo guarda sus datos en `references`. Los **bytes** se guardan en el teléfono como archivos y en el servidor con `/backup/references` (ver `api-contract.md`), uno por id.
- El teléfono las comprime antes de guardarlas: lado mayor de 1600 px como máximo, JPEG calidad 0.7 (≈ 100–300 KB). Nunca más de 2 MB.
- `sha256` es la huella de los bytes guardados; si cambia, se vuelven a subir.
- Quitar una referencia la marca con `deleted_at` y la saca de `reference_ids`; sus bytes se pueden borrar del teléfono.

## Unidades del sistema

No van en `units`. Tienen ids fijos `sys.<abreviatura>` con los espacios cambiados por `_`: `sys.g`, `sys.kg`, `sys.lb`, `sys.oz`, `sys.ml`, `sys.l`, `sys.tz`, `sys.cda`, `sys.cdta`, `sys.fl_oz`, `sys.pz`, `sys.doc` (tabla en `api-contract.md`, "Unidades del sistema"). Recetas y equivalencias apuntan a esos ids.

## Migración desde los datos del servidor (una sola vez)

`GET /backup/export-current` arma este documento con lo que hoy hay en las colecciones del workspace:

- Todos los documentos del workspace, **incluidos los borrados**, con sus ids actuales.
- Cada referencia a una unidad del sistema del servidor (`unit_id` en líneas de receta y en equivalencias) se cambia por su `sys.*`, buscando la unidad por id y usando su abreviatura. Las unidades del negocio conservan su id y van en `units`.
- `orders[].items[].recipe_name`: el nombre actual de la receta (aunque esté borrada); `""` si ya no existe.
- `settings` sale del workspace. `device_id`: `"server-export"`. `photo_id`: nulo.
- Un `Decimal128` de Mongo se escribe como texto decimal sin exponente (`"1000"`, no `"1E+3"`).
