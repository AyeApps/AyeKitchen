from fastapi import APIRouter

router = APIRouter()

# Bloque B11: GET /, GET /latest, PUT /, GET /export-current (docs/api-contract.md, "/backup").
# Declara /latest y /export-current antes de cualquier ruta con parámetro.
