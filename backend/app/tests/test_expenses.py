import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_expense_crud_and_filters(client: AsyncClient, auth_headers):
    # 1. Crear proveedor
    supp_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Central de Abastos"},
    )
    assert supp_resp.status_code == 201
    supp_id = supp_resp.json()["id"]

    # 2. Crear gasto con proveedor
    exp1 = (await client.post(
        "/api/v1/expenses/",
        headers=auth_headers,
        json={
            "description": "Bulto de Harina 50kg",
            "amount_cents": 45000,
            "spent_at": "2026-10-15T10:00:00Z",
            "category": "Insumos",
            "supplier_id": supp_id,
        },
    )).json()
    assert exp1["amount_cents"] == 45000
    assert exp1["category"] == "Insumos"
    assert exp1["supplier_id"] == supp_id
    exp1_id = exp1["id"]

    # Crear gasto 2 (otro mes y otra categoría)
    exp2 = (await client.post(
        "/api/v1/expenses/",
        headers=auth_headers,
        json={
            "description": "Recibo de Gas",
            "amount_cents": 12000,
            "spent_at": "2026-11-02T10:00:00Z",
            "category": "Servicios",
        },
    )).json()
    exp2_id = exp2["id"]

    # 3. Filtrar gastos por fecha (mes de octubre)
    oct_resp = await client.get(
        "/api/v1/expenses/?from=2026-10-01T00:00:00Z&to=2026-10-31T23:59:59Z",
        headers=auth_headers,
    )
    assert oct_resp.status_code == 200
    assert oct_resp.json()["total"] == 1
    assert oct_resp.json()["items"][0]["id"] == exp1_id

    # Filtrar por categoría
    serv_resp = await client.get(
        "/api/v1/expenses/?category=Servicios",
        headers=auth_headers,
    )
    assert serv_resp.status_code == 200
    assert serv_resp.json()["total"] == 1
    assert serv_resp.json()["items"][0]["id"] == exp2_id

    # 4. PATCH gasto
    patch_resp = await client.patch(
        f"/api/v1/expenses/{exp1_id}",
        headers=auth_headers,
        json={"amount_cents": 48000, "description": "Bulto Harina Extra Fina"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["amount_cents"] == 48000
    assert patch_resp.json()["description"] == "Bulto Harina Extra Fina"

    # 5. DELETE gasto (soft delete)
    del_resp = await client.delete(
        f"/api/v1/expenses/{exp1_id}",
        headers=auth_headers,
    )
    assert del_resp.status_code == 204

    # Verificar que no aparece en listado
    list_after = (await client.get("/api/v1/expenses/", headers=auth_headers)).json()
    assert exp1_id not in [it["id"] for it in list_after["items"]]


@pytest.mark.asyncio
async def test_expense_invalid_supplier(client: AsyncClient, auth_headers):
    # Proveedor inexistente -> 422 INVALID_REFERENCE
    resp = await client.post(
        "/api/v1/expenses/",
        headers=auth_headers,
        json={
            "description": "Compra dudosa",
            "amount_cents": 5000,
            "supplier_id": "507f1f77bcf86cd799439011",
        },
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_REFERENCE"


@pytest.mark.asyncio
async def test_expense_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    exp = (await client.post(
        "/api/v1/expenses/",
        headers=auth_headers,
        json={"description": "Gasto Secreto", "amount_cents": 3000},
    )).json()
    exp_id = exp["id"]

    # Usuario 2 no puede editarlo ni borrarlo
    assert (await client.patch(f"/api/v1/expenses/{exp_id}", headers=auth_headers_user_2, json={"amount_cents": 1})).status_code == 404
    assert (await client.delete(f"/api/v1/expenses/{exp_id}", headers=auth_headers_user_2)).status_code == 404

    # Usuario 2 no lo ve en su lista
    list_u2 = (await client.get("/api/v1/expenses/", headers=auth_headers_user_2)).json()
    assert exp_id not in [it["id"] for it in list_u2["items"]]
