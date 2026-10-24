---
name: AyeKitchen
description: Cocina tranquila y cálida — blanco y naranja Aye, redondo, claro y fácil de usar.
colors:
  accent: "#FE9D01"
  accent-ink: "#2A1700"
  accent-text: "#A35200"
  accent-text-deep: "#7A3D00"
  accent-soft: "#FFF4E3"
  accent-soft-strong: "#FFE3B8"
  accent-soft-track: "#F3E2C8"
  warning-soft: "#FFF0DC"
  warning-text: "#8A4500"
  success-soft: "#E6F4EA"
  success-text: "#21633B"
  neutral-soft: "#F2ECE5"
  bg: "#FFFFFF"
  bg-web: "#FBF8F4"
  surface-input: "#FFFCF8"
  text: "#24201B"
  text-secondary: "#4A433C"
  text-muted: "#6B6259"
  text-on-soft: "#5C4A36"
  border: "#EEE7DF"
  border-input: "#E8DFD5"
  divider: "#F2ECE5"
  dark-bg: "#17130F"
  dark-surface: "#221C16"
  dark-surface-raised: "#2B241D"
  dark-text: "#F5EFE8"
  dark-text-muted: "#B3A698"
  dark-accent-text: "#FFB547"
  dark-accent-soft: "#33261A"
  dark-border: "#3A3129"
typography:
  display:
    fontFamily: "Nunito, ui-rounded, system-ui, sans-serif"
    fontSize: "34px"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Nunito, ui-rounded, system-ui, sans-serif"
    fontSize: "21px"
    fontWeight: 800
    lineHeight: 1.25
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Nunito, ui-rounded, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.5
  body-strong:
    fontFamily: "Nunito, ui-rounded, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.4
  secondary:
    fontFamily: "Nunito, ui-rounded, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Nunito, ui-rounded, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 800
    lineHeight: 1.2
  amount:
    fontFamily: "Nunito, ui-rounded, system-ui, sans-serif"
    fontSize: "30px"
    fontWeight: 800
    lineHeight: 1.1
rounded:
  segment-inner: "9px"
  segment: "11px"
  control: "12px"
  card: "16px"
  button-ios: "18px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "28px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    rounded: "{rounded.control}"
    height: "46px"
  button-primary-ios:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    rounded: "{rounded.button-ios}"
    height: "56px"
  button-secondary:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
    height: "46px"
  input:
    backgroundColor: "{colors.surface-input}"
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
    height: "52px"
  card-soft:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.text}"
    rounded: "{rounded.card}"
    padding: "18px"
  chip-in-progress:
    backgroundColor: "{colors.accent-soft-strong}"
    textColor: "{colors.accent-text-deep}"
    rounded: "{rounded.pill}"
    padding: "5px 10px"
  chip-pending:
    backgroundColor: "{colors.neutral-soft}"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.pill}"
    padding: "5px 10px"
  chip-done:
    backgroundColor: "{colors.success-soft}"
    textColor: "{colors.success-text}"
    rounded: "{rounded.pill}"
    padding: "5px 10px"
  chip-warning:
    backgroundColor: "{colors.warning-soft}"
    textColor: "{colors.warning-text}"
    rounded: "{rounded.pill}"
    padding: "5px 10px"
---

# Design System: AyeKitchen

## Overview

Una cocina tranquila y cálida. Conserva el blanco y el naranja de Aye, pero deja la filosofía técnica y brutalista de las demás apps Aye (obsidiana, sombras duras, monoespaciada) por una amable: esquinas redondas, fondos crema suaves, letra redondeada, botones grandes y palabras de la cocina. Es una herramienta (modo *Operate*): lo primero es que se entienda y se use rápido; la marca vive en el tono naranja, la letra y el lenguaje.

Referencia visual aprobada: https://claude.ai/artifact/4Vuy4h8YH51rTsEiiVhwia

En iOS manda la plataforma: navegación, hojas, controles y tipografía del sistema. La marca entra por el color de acento (tint), la versión redondeada de SF y el contenido.

## Colors

### Primary

- **Naranja Aye `accent` (#FE9D01):** solo como **relleno** de lo que se toca o se elige: botón principal, "+", ícono de marca. El texto encima siempre es `accent-ink` (#2A1700, 8:1). **Nunca texto blanco sobre naranja**: no pasa contraste.
- **`accent-text` (#A35200):** el naranja que se lee. Enlaces, números importantes (precio sugerido), pestaña activa, botones de texto como "Cancelar". 5.5:1 sobre blanco. `accent-text-deep` (#7A3D00) para texto sobre fondos crema fuertes.

### Secondary

- **Cremas de acento:** `accent-soft` (#FFF4E3) para tarjetas destacadas (lo que sigue, el costo de una receta, la pregunta de equivalencia); `accent-soft-strong` (#FFE3B8) para seleccionado y la píldora "En proceso"; `accent-soft-track` (#F3E2C8) para el riel del control segmentado sobre crema.

### Tertiary

- **Estados:** advertencia (`warning-soft` + `warning-text`) para "falta precio" y "precio viejo"; éxito (`success-soft` + `success-text`) solo para "Entregado". Se distinguen también por ícono y texto, no solo por color.

### Neutral

- Fondo `bg` (#FFFFFF) en iOS y tarjetas; `bg-web` (#FBF8F4) como lienzo del panel web.
- Texto `text` (#24201B), `text-secondary` (#4A433C), `text-muted` (#6B6259, 5.8:1, el gris más claro permitido para texto). `text-on-soft` (#5C4A36) para texto secundario sobre crema.
- Bordes `border` (#EEE7DF), `border-input` (#E8DFD5), divisores `divider` (#F2ECE5).

### Modo oscuro (propuesto, falta validarlo en pantalla)

`dark-bg` (#17130F), `dark-surface` (#221C16), `dark-surface-raised` (#2B241D), texto `dark-text` (#F5EFE8) y `dark-text-muted` (#B3A698), naranja legible `dark-accent-text` (#FFB547), crema oscura `dark-accent-soft` (#33261A), bordes `dark-border` (#3A3129). El relleno `accent` no cambia y sigue con texto `accent-ink`. En iOS se definen como colores de Asset Catalog con variante Any/Dark; en web, como variables CSS bajo `.dark`.

### Named Rules

- **El naranja se rellena, el naranja oscuro se lee.** `accent` nunca como color de texto; `accent-text` nunca como relleno de botón.
- **Un solo acento.** Nada de un segundo color de marca; los estados son los únicos otros colores.
- **Inicio no muestra dinero.** Lo cobrado, lo que deben y la ganancia del mes pertenecen a la futura sección Finanzas. Los precios de recetas y pedidos sí se muestran donde corresponden.

## Typography

- **iOS:** SF Pro Rounded del sistema (`.fontDesign(.rounded)`) con los estilos de Dynamic Type: Large Title en pantallas principales, Title 2/3 para secciones, Headline para títulos de filas, Body 17 para texto, Subheadline 15 para detalle, Footnote/Caption para etiquetas. Nada de tamaños fijos.
- **Web:** Nunito (Google Fonts, 400/600/700/800), la más cercana a SF Rounded. Escala en el frontmatter: display 34, title 21, body 18, secondary 16, label 14, amount 30, todo en `rem` para que escale con el zoom del navegador.
- **Números de dinero y cantidades:** cifras tabulares (`font-variant-numeric: tabular-nums` / `.monospacedDigit()`), peso 800 para totales.

### Hierarchy

Display/Large Title (34, 800, -0.02em) → título de sección (21, 800) → cuerpo (18 web / Body iOS, 400–700) → secundario (16 web / Subheadline iOS, `text-muted`) → etiqueta (14 web / Footnote iOS, 800). La jerarquía sale de peso y tamaño juntos; el interlineado se cierra en títulos (1.1) y se abre en cuerpo (1.5).

### Letra grande (la usuaria principal la usa)

- **iOS se diseña primero en tamaño grande.** Cada pantalla se revisa en Large (el de fábrica), xxxLarge y los de accesibilidad AX1–AX3, en el simulador.
- **Reacomodar, nunca cortar.** Con `dynamicTypeSize.isAccessibilitySize` (o `ViewThatFits`), lo que va lado a lado pasa a ir uno debajo del otro: las dos columnas "Te cuesta / Te sugerimos cobrar", la fila de entrega (fecha · cliente · estado) y los botones de una misma fila.
- **Los montos nunca se truncan ni se encogen** (`lineLimit(nil)`, sin `minimumScaleFactor` en dinero); los nombres de cliente o receta pueden ir en dos líneas.
- **El control segmentado de 5 unidades no cabe en tamaños de accesibilidad:** ahí se convierte en un `Picker` de menú ("Unidad: taza ▾"). El de margen (4 opciones) se queda segmentado hasta AX1 y luego también pasa a menú.
- **Barra de pestañas:** usa la del sistema, que ya agranda sus etiquetas con el gesto de mantener presionado; no se hace una propia.
- **Espacios con `@ScaledMetric`** para que crezcan junto con el texto, no solo el texto.

### Named Rules

- **Nada de monoespaciada ni mayúsculas con tracking amplio.** Eso es la filosofía Aye técnica que aquí no aplica. La única excepción son los días abreviados en la fecha de entrega (SÁB, DOM), en peso 800 y tracking normal.
- **Tracking:** -0.02em en display, -0.01em en títulos, 0 en cuerpo.

## Layout

- **iOS:** dentro de la safe area; márgenes laterales de 20 pt; separación entre secciones de 26–28 pt y dentro de un grupo de 10–14 pt. Barra de pestañas con 4 secciones: Inicio, Pedidos, Recetas, Catálogo (Finanzas entrará como quinta). Acciones globales ("Nuevo pedido") como botón "+" en la barra de navegación, nunca un botón flotante.
- **Web:** menú lateral de 220–260 px + contenido fluido (`flex: 999 1 560px`); en pantallas angostas el menú se apila arriba. Contenido en dos columnas (3:2) que se apilan por debajo de ~900 px. Tablas anchas dentro de una caja con scroll horizontal. Márgenes `clamp(16px, 3vw, 44px)`.
- Espaciado en la escala del frontmatter (4/8/12/16/20/28).

## Elevation & Depth

- Plana por defecto: la profundidad se marca con fondo crema o con un borde de 1 px, **nunca los dos con sombra** a la vez.
- Única sombra: la del segmento seleccionado (`0 1px 3px rgba(60,40,10,0.18)`) y, en iOS, la que da el sistema a hojas y menús.
- Barra de pestañas de iOS y barras fijas: material del sistema (`.bar` / `ultraThinMaterial`); en web, `rgba(255,255,255,0.82)` + `backdrop-filter: blur(20px) saturate(180%)` solo donde el contenido pasa por debajo.

### Named Rules

- **Prohibidas las sombras duras desplazadas** (`4px 4px 0`) del estilo Aye técnico.

## Shapes

- Tarjetas y contenedores: 16 px. Controles (inputs, botones web, filas tocables): 12 px. Botón principal de iOS: 18 px. Control segmentado: riel 11 px, segmento 9 px. Píldoras de estado: 999 px.
- Íconos de trazo redondeado y peso uniforme; en iOS, SF Symbols. En web, `lucide-react` (estándar Aye), trazo 2.

## Components

### Buttons

- **Principal:** relleno `accent`, texto `accent-ink` 800. iOS 56 pt de alto (una sola acción principal por pantalla, al final de la hoja o del formulario); web 46 px.
- **Secundario:** blanco con borde `border-input` 1.5 px, texto `text` 700.
- **De texto:** `accent-text` 600–700, sin fondo, 44 pt de área táctil ("Cancelar", "Ver todas", "Editar").
- Presión: `scale(0.97)` inmediato en web; en iOS el estilo del sistema.

### Chips

Estado de pedido con píldora: Pendiente (`chip-pending`), En proceso (`chip-in-progress`), Entregado (`chip-done`), Cancelado (`chip-pending` con texto tachado o etiqueta "Cancelado"). Advertencias de datos ("Falta precio", "Precio viejo") con `chip-warning` + ícono de triángulo.

### Cards / Containers

- **Tarjeta crema** (`card-soft`) solo para lo más importante de la pantalla: lo que sigue, el costo de la receta, la pregunta de equivalencia, "Por revisar". Una por pantalla, máximo dos.
- **Listas:** filas en un contenedor con borde de 1 px y radio 16, divisores `divider` entre filas (estilo lista agrupada de iOS). Nunca tarjetas dentro de tarjetas.

### Inputs / Fields

Etiqueta visible arriba (15, 700), campo de 52–56 px, fondo `surface-input`, borde `border-input` 1.5 px; foco con borde `accent-text` 2 px. Cantidades con teclado decimal (`inputmode="decimal"` / `.decimalPad`) y botones − / + de 56 pt.

### Navigation

- **iOS:** `TabView` con las 4 secciones; navegación en pila con título grande en pantallas principales e inline en detalle; atrás con el gesto del borde. Tareas cortas (agregar ingrediente, registrar precio, nuevo pedido) en hoja (`.sheet`) con "Cancelar" a la izquierda y la acción principal abajo.
- **Web:** menú lateral con ítem activo en `accent-soft-strong`; foco visible `outline 2.5px accent-text, offset 2px`; selección de texto en `accent-soft-strong`.

### Control segmentado

Margen de ganancia (20/30/40/60 %) y unidades (g, kg, taza, cda, cdta). En iOS es el `Picker(.segmented)` del sistema con tint naranja; en web, riel `neutral-soft` (o `accent-soft-track` sobre crema) con el segmento elegido en blanco y sombra mínima, como `role="radiogroup"`.

### Desglose de costo (componente firma)

Tarjeta crema con dos columnas, "Te cuesta" y "Te sugerimos cobrar" (este en `accent-text`), por porción debajo, el control de margen y luego la lista "De dónde sale el costo", cada línea con ícono (ingrediente, subreceta, costo fijo), nombre, detalle (cantidad · marca · tienda) y monto. Una línea sin precio o con precio viejo lleva su chip de advertencia y abre el registro de precio.

### Pregunta de equivalencia (componente firma)

Cuando la unidad elegida no se puede convertir, aparece en línea, sin bloquear: "La harina la compras por gramos. ¿Cuánto pesa 1 taza de harina?", un campo con la sugerencia ya escrita (125 g) y el rango normal ("suele pesar entre 120 y 130 g"). Se guarda en el ingrediente y no se vuelve a preguntar.

## Do's and Don'ts

### Do:

- Hablar como en la cocina: "Te cuesta", "Te sugerimos cobrar", "Lo que sigue", "Falta el precio de la nuez".
- Mostrar siempre de dónde sale un número.
- Preguntar lo que falta en el momento, con una sugerencia ya escrita.
- Usar controles nativos en iOS (TabView, NavigationStack, sheet, Picker segmentado, Stepper cuando quepa, swipe actions).
- Dinero en formato es-MX (`$1,234.56`), cifras tabulares.
- Validar contraste 4.5:1 en texto, también en los grises sobre crema.

### Don't:

- No texto blanco sobre naranja.
- No mostrar dinero en Inicio (es de Finanzas).
- No botón flotante en iOS; la acción global va como "+" en la barra.
- No sombras duras, monoespaciada, mayúsculas espaciadas ni la estética brutalista de las otras apps Aye.
- No tarjetas dentro de tarjetas ni filas de cuatro números grandes como plantilla de tablero.
- No emojis como íconos.
- No colores sueltos en componentes: todo sale de estos tokens.
