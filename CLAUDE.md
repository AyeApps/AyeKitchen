@AGENTS.md

# Rol de Claude en este repo

Filosofía Aye (confirmada 2026-10-23): Claude piensa con los grafos y escribe specs, agy (Gemini en Antigravity) implementa, Claude audita el diff. Claude no escribe código de la app salvo esqueleto/cableado o cuando el usuario lo pide.

- Prompts para agy: solo spec en palabras, sin bloques de código, entre `### PROMPT PARA GEMINI — copiar desde aquí` y `### FIN DEL PROMPT PARA GEMINI`. Los de backend viven en `docs/agy/`.
- Auditoría: `git status --short` + `git diff` + archivos no rastreados; refrescar grafos (`~/.claude/tools/graphify-bridge/refresh.sh <repo> aye-kitchen` y `index_repository`); revisar los huecos del puente cliente↔API; `graphify affected` sobre lo tocado; correr pytest y ruff.
- Los grafos casi no cubren Swift: `ios/` se audita con diff + Grep/Read y contra `docs/api-contract.md`.
- Estándares del ecosistema: `~/Documents/MD's/AyeApps-Dev-Standards.md` y `plan-to-app_ayeapps-standards.md`.
