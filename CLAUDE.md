@AGENTS.md

# Rol de Claude en este repo

Filosofía Aye (confirmada 2026-10-23): Claude piensa con los grafos y escribe specs, agy (Gemini en Antigravity) implementa, Claude audita el diff. Claude no escribe código de la app salvo esqueleto/cableado o cuando el usuario lo pide.

- Prompts para agy: solo spec en palabras, sin bloques de código, entre `### PROMPT PARA GEMINI — copiar desde aquí` y `### FIN DEL PROMPT PARA GEMINI`, guardados en `docs/agy/AAAA-MM-DD/<id>-<nombre>.md` (carpeta por día; reglas compartidas en `docs/agy/_*.md`). En el chat solo va un mini prompt que apunta a su archivo. Formato completo: sección "How specs and prompts are delivered" de `~/.claude/rules/gemini-workflow.md`.
- Auditoría: `git status --short` + `git diff` + archivos no rastreados; refrescar grafos (`~/.claude/tools/graphify-bridge/refresh.sh <repo> aye-kitchen` y `index_repository`); revisar los huecos del puente cliente↔API; `graphify affected` sobre lo tocado; correr pytest y ruff.
- **Integridad de los datos (usuario, 2026-11-13: "ya hay personas usando esto con datos reales").** La sección "Integridad de los datos" de `GEMINI.md` manda sobre cualquier spec. Al auditar: todo diff a `Entities.swift`, `KitchenData.swift`, `CodingKeys`, `docs/backup-format.md` o `schema_version` se revisa línea por línea (solo campos opcionales nuevos); `swift test` incluye `FrozenBackupTests` y debe pasar; ninguna prueba existente cambió; ninguna regla reescribe registros guardados por su cuenta. Cada cambio de formato agrega un respaldo congelado nuevo (`Fixtures/backup_v<schema>_<AAAA-MM-DD>.json`) y nunca se editan los anteriores. Un cambio que no sea solo agregar (renombrar, quitar, subir `schema_version`) lo diseña Claude con migración y pruebas, y se lo consulta al usuario antes.
- Los grafos casi no cubren Swift: `ios/` se audita con diff + Grep/Read y contra `docs/api-contract.md`.
- Estándares del ecosistema: `~/Documents/MD's/AyeApps-Dev-Standards.md` y `plan-to-app_ayeapps-standards.md`.
