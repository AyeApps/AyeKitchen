import pytest
from httpx import AsyncClient


async def _create_test_recipe(client: AsyncClient, auth_headers: dict) -> str:
    # 1. Ingrediente
    ing = (
        await client.post(
            "/api/v1/ingredients/",
            headers=auth_headers,
            json={"name": "Harina Resumen", "base_unit": "g"},
        )
    ).json()

    # 2. Presentación con precio
    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing["id"],
            "brand": "Selecta",
            "package_quantity": "1000",
            "price_cents": 20000,  # $200.00 / kg -> 20c por g
        },
    )
    assert pres_resp.status_code == 201

    # 3. Receta: 1000 g -> costo tanda 20000 centavos ($200.00)
    # Margen 50% -> sugerido 30000 centavos ($300.00)
    rec = (
        await client.post(
            "/api/v1/recipes/",
            headers=auth_headers,
            json={
                "name": "Pastel Resumen",
                "yield_quantity": "1",
                "yield_unit": "pz",
                "margin_percent": 50,
                "items": [
                    {
                        "kind": "ingredient",
                        "ref_id": ing["id"],
                        "quantity": "1000",
                    }
                ],
            },
        )
    ).json()
    return rec["id"]


@pytest.mark.asyncio
async def test_summary_validation(client: AsyncClient, auth_headers):
    # Sin parámetros
    r = await client.get("/api/v1/summary/monthly", headers=auth_headers)
    assert r.status_code == 422

    # Year fuera de rango
    r = await client.get("/api/v1/summary/monthly?year=1999&month=10", headers=auth_headers)
    assert r.status_code == 422

    r = await client.get("/api/v1/summary/monthly?year=2101&month=10", headers=auth_headers)
    assert r.status_code == 422

    # Month fuera de rango
    r = await client.get("/api/v1/summary/monthly?year=2026&month=0", headers=auth_headers)
    assert r.status_code == 422

    r = await client.get("/api/v1/summary/monthly?year=2026&month=13", headers=auth_headers)
    assert r.status_code == 422

    # Consulta válida en mes vacío
    r = await client.get("/api/v1/summary/monthly?year=2026&month=10", headers=auth_headers)
    assert r.status_code == 200
    data = r.json()
    assert data["year"] == 2026
    assert data["month"] == 10
    assert data["income_cents"] == 0
    assert data["expenses_cents"] == 0
    assert data["net_cents"] == 0
    assert data["orders_delivered"] == 0
    assert data["orders_pending"] == 0
    assert data["sales_cents"] == 0
    assert data["estimated_profit_cents"] == 0
    assert data["receivable_cents"] == 0


@pytest.mark.asyncio
async def test_summary_income_and_sales_timing(client: AsyncClient, auth_headers):
    rec_id = await _create_test_recipe(client, auth_headers)

    # Crear pedido con entrega en Noviembre
    # Precio unitario 30000, costo snapshot 20000
    order = (
        await client.post(
            "/api/v1/orders/",
            headers=auth_headers,
            json={
                "customer_name": "Ana Noviembre",
                "delivery_at": "2026-11-15T16:00:00Z",
                "items": [{"recipe_id": rec_id, "quantity": "1"}],
            },
        )
    ).json()
    order_id = order["id"]
    assert order["total_cents"] == 30000
    assert order["cost_cents"] == 20000

    # Pago anticipado recibido en Octubre ($100.00 = 10000 centavos)
    pay_resp = await client.post(
        f"/api/v1/orders/{order_id}/payments",
        headers=auth_headers,
        json={
            "amount_cents": 10000,
            "paid_at": "2026-10-25T14:00:00Z",
            "method": "transferencia",
        },
    )
    assert pay_resp.status_code == 201

    # Gasto en Octubre ($20.00 = 2000 centavos)
    await client.post(
        "/api/v1/expenses/",
        headers=auth_headers,
        json={
            "description": "Capacillos",
            "amount_cents": 2000,
            "spent_at": "2026-10-20T10:00:00Z",
        },
    )

    # 1. Resumen de Octubre:
    # - income_cents cuenta el pago de 10000
    # - expenses_cents cuenta los 2000
    # - net_cents = 10000 - 2000 = 8000
    # - sales_cents = 0 (se entrega en noviembre)
    # - orders_delivered = 0, orders_pending = 0, receivable_cents = 0 (todo es de nov)
    oct_summary = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=10",
            headers=auth_headers,
        )
    ).json()

    assert oct_summary["income_cents"] == 10000
    assert oct_summary["expenses_cents"] == 2000
    assert oct_summary["net_cents"] == 8000
    assert oct_summary["orders_delivered"] == 0
    assert oct_summary["orders_pending"] == 0
    assert oct_summary["sales_cents"] == 0
    assert oct_summary["estimated_profit_cents"] == 0
    assert oct_summary["receivable_cents"] == 0

    # 2. Resumen de Noviembre ANTES de entregar:
    # - delivery_at está en nov, status = pendiente
    # - orders_pending = 1
    # - receivable_cents = balance_cents = 30000 - 10000 = 20000
    # - sales_cents = 0 (aún no entregado)
    nov_pre = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=11",
            headers=auth_headers,
        )
    ).json()

    assert nov_pre["income_cents"] == 0
    assert nov_pre["orders_pending"] == 1
    assert nov_pre["orders_delivered"] == 0
    assert nov_pre["sales_cents"] == 0
    assert nov_pre["receivable_cents"] == 20000

    # 3. Entregar el pedido en Noviembre
    patch_resp = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={"status": "entregado"},
    )
    assert patch_resp.status_code == 200

    # Resumen de Noviembre DESPUÉS de entregar:
    # - orders_delivered = 1, orders_pending = 0
    # - sales_cents = 30000
    # - estimated_profit_cents = 30000 - 20000 = 10000
    # - receivable_cents = 20000 (sigue debiendo 20000)
    nov_post = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=11",
            headers=auth_headers,
        )
    ).json()

    assert nov_post["orders_delivered"] == 1
    assert nov_post["orders_pending"] == 0
    assert nov_post["sales_cents"] == 30000
    assert nov_post["estimated_profit_cents"] == 10000
    assert nov_post["receivable_cents"] == 20000


@pytest.mark.asyncio
async def test_summary_timezone_boundary(client: AsyncClient, auth_headers):
    # La timezone por defecto del workspace es America/Mexico_City (UTC-6)
    # 23:30 del 31 de octubre de 2026 en Mexico City = 05:30 del 1 de noviembre de 2026 UTC
    rec_id = await _create_test_recipe(client, auth_headers)

    order = (
        await client.post(
            "/api/v1/orders/",
            headers=auth_headers,
            json={
                "customer_name": "Carlos Noche",
                "delivery_at": "2026-11-05T12:00:00Z",
                "items": [{"recipe_id": rec_id, "quantity": "1"}],
            },
        )
    ).json()

    # Pago registrado a las 05:30:00Z del 1 de noviembre (23:30 del 31 de octubre hora local)
    pay_resp = await client.post(
        f"/api/v1/orders/{order['id']}/payments",
        headers=auth_headers,
        json={
            "amount_cents": 15000,
            "paid_at": "2026-11-01T05:30:00Z",
        },
    )
    assert pay_resp.status_code == 201

    # Octubre debe incluir el pago de 15000
    oct_summary = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=10",
            headers=auth_headers,
        )
    ).json()
    assert oct_summary["income_cents"] == 15000

    # Noviembre NO debe incluir ese pago
    nov_summary = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=11",
            headers=auth_headers,
        )
    ).json()
    assert nov_summary["income_cents"] == 0


@pytest.mark.asyncio
async def test_summary_cancelled_orders_excluded(client: AsyncClient, auth_headers):
    rec_id = await _create_test_recipe(client, auth_headers)

    # Pedido con entrega en Octubre
    order = (
        await client.post(
            "/api/v1/orders/",
            headers=auth_headers,
            json={
                "customer_name": "Diana Cancelada",
                "delivery_at": "2026-10-18T12:00:00Z",
                "items": [{"recipe_id": rec_id, "quantity": "1"}],
            },
        )
    ).json()

    # Pago en octubre
    await client.post(
        f"/api/v1/orders/{order['id']}/payments",
        headers=auth_headers,
        json={
            "amount_cents": 10000,
            "paid_at": "2026-10-10T12:00:00Z",
        },
    )

    # Cancelar el pedido
    patch_resp = await client.patch(
        f"/api/v1/orders/{order['id']}",
        headers=auth_headers,
        json={"status": "cancelado"},
    )
    assert patch_resp.status_code == 200

    # Gasto en octubre
    await client.post(
        "/api/v1/expenses/",
        headers=auth_headers,
        json={
            "description": "Mantenimiento Batidora",
            "amount_cents": 4000,
            "spent_at": "2026-10-12T10:00:00Z",
        },
    )

    oct_summary = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=10",
            headers=auth_headers,
        )
    ).json()

    # Pedido cancelado no suma a income, sales, profit, orders_pending, orders_delivered ni receivable
    assert oct_summary["income_cents"] == 0
    assert oct_summary["expenses_cents"] == 4000
    assert oct_summary["net_cents"] == -4000
    assert oct_summary["orders_delivered"] == 0
    assert oct_summary["orders_pending"] == 0
    assert oct_summary["sales_cents"] == 0
    assert oct_summary["estimated_profit_cents"] == 0
    assert oct_summary["receivable_cents"] == 0


@pytest.mark.asyncio
async def test_summary_isolation(client: AsyncClient, auth_headers, auth_headers_user_2):
    rec_id_u2 = await _create_test_recipe(client, auth_headers_user_2)

    # Usuario 2 crea pedido, pago y gasto en Octubre
    order_u2 = (
        await client.post(
            "/api/v1/orders/",
            headers=auth_headers_user_2,
            json={
                "customer_name": "Cliente de Usuario 2",
                "delivery_at": "2026-10-20T12:00:00Z",
                "items": [{"recipe_id": rec_id_u2, "quantity": "1"}],
            },
        )
    ).json()

    await client.post(
        f"/api/v1/orders/{order_u2['id']}/payments",
        headers=auth_headers_user_2,
        json={"amount_cents": 30000, "paid_at": "2026-10-20T12:00:00Z"},
    )

    await client.post(
        "/api/v1/expenses/",
        headers=auth_headers_user_2,
        json={
            "description": "Gasto U2",
            "amount_cents": 10000,
            "spent_at": "2026-10-15T10:00:00Z",
        },
    )

    # Usuario 1 consulta su propio resumen de Octubre: debe estar completamente limpio
    summary_u1 = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=10",
            headers=auth_headers,
        )
    ).json()

    assert summary_u1["income_cents"] == 0
    assert summary_u1["expenses_cents"] == 0
    assert summary_u1["net_cents"] == 0
    assert summary_u1["orders_delivered"] == 0
    assert summary_u1["orders_pending"] == 0
    assert summary_u1["sales_cents"] == 0
    assert summary_u1["receivable_cents"] == 0

    # Usuario 2 consulta su resumen de Octubre
    summary_u2 = (
        await client.get(
            "/api/v1/summary/monthly?year=2026&month=10",
            headers=auth_headers_user_2,
        )
    ).json()

    assert summary_u2["income_cents"] == 30000
    assert summary_u2["expenses_cents"] == 10000
    assert summary_u2["net_cents"] == 20000
