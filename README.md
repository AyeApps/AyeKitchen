# AyeKitchen

Costeo de recetas para negocios de repostería: ingredientes con sus marcas, proveedores y precios, conversiones de medidas (tazas, cucharadas), recetas con subrecetas, costo y precio sugerido por pastel, pedidos con anticipos y un resumen mensual.

| Capa | Stack | Local |
|---|---|---|
| API | FastAPI + Beanie (MongoDB) | `http://localhost:8006` |
| Web | Next.js 16 + Tailwind v4 | `http://localhost:3006` |
| iOS | SwiftUI | — |

Login con la cuenta Aye (SSO de `aye-auth`, `app_client: "kitchen"`).

## Backend local

```bash
cd backend
python3.12 -m venv venv && ./venv/bin/pip install -r requirements.txt
cp .env.example .env
./venv/bin/uvicorn main:app --reload --port 8006
./venv/bin/python -m pytest -q

# Misma suite contra un MongoDB real (solo usa y borra aye_kitchen_test_db)
docker run -d --name aye-kitchen-mongo-test --restart unless-stopped -p 27018:27017 mongo:7.0
TEST_MONGODB_URL=mongodb://localhost:27018 ./venv/bin/python -m pytest -q
```

Contrato de la API: [docs/api-contract.md](docs/api-contract.md).
