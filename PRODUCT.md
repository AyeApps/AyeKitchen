# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

App nativa de iPhone (SwiftUI) y panel web (Next.js) sobre la misma API. Android (Kotlin + Compose) queda para después.

## Stack

- `backend/`: FastAPI + Beanie (MongoDB), SSO con `aye-auth` (JWT compartido, `app_client: "kitchen"`).
- `web/`: Next.js 16 + React 19 + Tailwind v4.
- `ios/`: SwiftUI (Swift 6), MVVM con `actor NetworkService`. El proyecto de Xcode lo crea el usuario.
- Contrato entre las tres capas: `docs/api-contract.md`.

## Users

- **Usuaria principal:** una repostera que hace pasteles por pedido desde su casa. Empieza a tener más clientes y hoy lleva las cuentas a mano. Usa iPhone.
- **Después:** otras reposteras o negocios de comida pequeños (cada uno con su propio espacio de trabajo), y ayudantes dentro del mismo negocio. El modelo de datos ya lo soporta (`workspace_id`); la interfaz para varios miembros todavía no existe.

## Product Purpose

Que sepa cuánto le cuesta de verdad cada pastel y cuánto cobrar para que le quede ganancia, sin hacer cuentas a mano. Éxito: arma una receta con los precios reales de sus tiendas, ve el costo y el precio sugerido, y lleva sus pedidos de la semana en el mismo lugar.

## Positioning

El costo sale de la compra real: cada ingrediente guarda las marcas y tiendas donde se compra, con su precio y su tamaño de paquete, y todo se lleva a una unidad atómica (gramo, mililitro o pieza). Las recetas usan las medidas de la cocina (tazas, cucharadas) y se convierten solas. Una receta puede ser ingrediente de otra (betún, relleno, bizcocho base).

## Operating Context

- Compra en supermercados y tiendas (Walmart, Costco, el mercado); los precios cambian y hay que mantenerlos al día.
- Las recetas vienen en tazas y cucharadas; los insumos se compran por peso o pieza.
- Los pedidos llegan por mensaje o en persona, con fecha y hora de entrega, a veces con anticipo.
- En la cocina, con el celular a la mano y a veces las manos ocupadas.

## Capabilities and Constraints

Confirmado y construido en el backend:
- Catálogo: ingredientes (unidad base g/ml/pz), sus marcas por proveedor con historial de precios, y proveedores.
- Tabla general de conversiones (taza, cucharada, kg, lb…) más equivalencias propias por ingrediente (1 taza de harina = 125 g). Si falta una equivalencia, la app la pregunta en el momento.
- Recetas con cantidades guardadas, subrecetas (sin ciclos, máximo 10 niveles), costos fijos (caja, gas) y margen.
- Costo: usa la marca con el precio más reciente; se puede fijar otra marca por línea. Una marca fijada sin precio se marca como "falta precio".
- Dinero en centavos enteros; cálculo exacto y un solo redondeo por total mostrado.
- Pedidos con líneas, precio acordado, foto del costo al crear el pedido, estado (pendiente, en proceso, entregado, cancelado) y pagos.
- Aviso de precios viejos: un precio con más de `price_stale_days` días (90 por defecto) se marca para actualizar.

Decidido para después:
- **Finanzas** como sección propia: lo cobrado, lo que le deben, gastos y resumen del mes. El backend ya lo tiene (pagos, `/expenses`, `/summary/monthly`); la interfaz se diseña aparte. Inicio no muestra dinero.
- Escáner de código de barras para capturar marcas (`barcode` ya existe en el modelo).
- Catálogo de equivalencias comunes sugeridas (pendiente de confirmar).

Terminología de la interfaz: **Catálogo** (no "Despensa"), Recetas, Pedidos, Inicio. "Marca" en la interfaz es una presentación en el código.

## Brand Commitments

- Parte del ecosistema Aye (`ayeapps.com`): cuenta Aye, mismo SSO.
- Colores de Aye: blanco y naranja (`#FE9D01`), con una filosofía distinta a la de las demás apps Aye: amable y fácil, no técnica ni brutalista.
- Voz: español de México, de tú, palabras de la cocina y no de contabilidad ("Te cuesta", "Te sugerimos cobrar").

## Evidence on Hand

- Exploración de diseño aprobada: https://claude.ai/artifact/4Vuy4h8YH51rTsEiiVhwia
- No hay clientes, testimonios, métricas ni fotos reales. Los nombres y montos de los mockups son de ejemplo y no se presentan como reales.

## Product Principles

1. El número que ve tiene que ser exacto y explicable: siempre se puede ver de dónde sale cada peso.
2. Preguntar en el momento en vez de pedir configuración previa (la equivalencia que falta, el precio que falta).
3. El precio acordado con un cliente nunca cambia solo.
4. Pocas pantallas y palabras de la vida diaria; lo avanzado, un nivel más abajo.
5. Lo que hoy es para una persona tiene que poder crecer a un negocio con varias personas sin rehacer los datos.

## Accessibility & Inclusion

- **La usuaria principal usa letra grande en su iPhone** (confirmado 2026-10-24). Toda pantalla de iOS tiene que funcionar completa con tamaños grandes de Dynamic Type, incluidos los de accesibilidad, sin cortar montos, nombres ni botones.
- En web el tamaño base de texto es 18 px, y todo escala con el zoom del navegador.
- Mínimo: texto con contraste 4.5:1, áreas táctiles de 44 pt y respeto a "Reducir movimiento".
