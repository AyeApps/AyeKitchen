Bloque I23. Rama `local-first`. Corre en paralelo con K3.

### `PROMPT PARA GEMINI — copiar desde aquí`

**Bloque I23 de AyeKitchen iOS: que Clientes se encuentre fácil desde Pedidos.** Trabaja en la rama `local-first`. Relee "Reglas de iOS" en `GEMINI.md` y las reglas de `docs/agy/_pantallas-locales.md`.

**Contexto.** La app tiene 4 pestañas y cada una lleva su vista secundaria en la esquina superior izquierda: Catálogo abre Proveedores, Inicio abrirá Ajustes y Pedidos abre Clientes. Hoy en Pedidos es solo un ícono de personas (`person.2`) que casi nadie descubre.

**Alcance:** solo `ios/aye-kitchen/aye-kitchen/Features/Orders/OrdersView.swift`.

1. El botón de la esquina superior izquierda de Pedidos muestra el ícono **y el texto "Clientes"** (un `Label` con estilo de título e ícono). Con letra de accesibilidad, solo el ícono con su `accessibilityLabel("Clientes")`.
2. Abre la misma vista de Clientes que hoy, del mismo modo.
3. Nada más cambia en la pantalla.

**Criterios de aceptación.**
1. En Pedidos se lee "Clientes" arriba a la izquierda y abre la lista de clientes.
2. Build sin advertencias nuevas; `git status` solo muestra `OrdersView.swift`.

Si algo choca con el alcance, detente y pregunta; no modifiques código fuera de alcance para satisfacerlo. **No reviertas cambios que veas en archivos fuera de tu alcance**: otro agente trabaja al mismo tiempo en `ios/KitchenKit/`.

### `FIN DEL PROMPT PARA GEMINI`
