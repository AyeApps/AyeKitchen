import asyncio
from datetime import datetime

import pytest
from httpx import AsyncClient


def _parse_dt(v: str | None) -> datetime | None:
    return datetime.fromisoformat(v) if v else None


@pytest.mark.asyncio
async def test_new_workspace_returns_all_null(client: AsyncClient, auth_headers):
    resp = await client.get("/api/v1/me/changes", headers=auth_headers)
    assert resp.status_code == 200
    assert resp.json() == {
        "home": None,
        "orders": None,
        "recipes": None,
        "catalog": None,
        "customers": None,
    }


@pytest.mark.asyncio
async def test_create_ingredient_changes_catalog_recipes_home(client: AsyncClient, auth_headers):
    c0 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert c0["catalog"] is None
    assert c0["recipes"] is None
    assert c0["home"] is None
    assert c0["orders"] is None
    assert c0["customers"] is None

    await asyncio.sleep(0.01)
    resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de Trigo", "base_unit": "g"},
    )
    assert resp.status_code == 201

    c1 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert c1["catalog"] is not None
    assert c1["recipes"] is not None
    assert c1["home"] is not None
    assert c1["orders"] is None
    assert c1["customers"] is None


@pytest.mark.asyncio
async def test_add_price_to_brand_changes_catalog_and_recipes(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Mantequilla", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Gloria",
            "package_quantity": "500",
        },
    )
    assert pres_resp.status_code == 201
    pres_id = pres_resp.json()["id"]

    c0 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert c0["orders"] is None
    assert c0["customers"] is None

    await asyncio.sleep(0.01)
    price_resp = await client.post(
        f"/api/v1/presentations/{pres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 4500},
    )
    assert price_resp.status_code == 201

    c1 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert _parse_dt(c1["catalog"]) > _parse_dt(c0["catalog"])
    assert _parse_dt(c1["recipes"]) > _parse_dt(c0["recipes"])
    assert _parse_dt(c1["home"]) > _parse_dt(c0["home"])
    assert c1["orders"] == c0["orders"]
    assert c1["customers"] == c0["customers"]


@pytest.mark.asyncio
async def test_edit_recipe_changes_recipes_orders_home_not_catalog(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Vainilla líquida", "base_unit": "ml"},
    )
    ing_id = ing_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Esencia Base",
            "yield_quantity": "100",
            "yield_unit": "ml",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}],
        },
    )
    assert rec_resp.status_code == 201
    rec_id = rec_resp.json()["id"]

    c0 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()

    await asyncio.sleep(0.01)
    patch_resp = await client.patch(
        f"/api/v1/recipes/{rec_id}",
        headers=auth_headers,
        json={"name": "Esencia Concentrada"},
    )
    assert patch_resp.status_code == 200

    c1 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert _parse_dt(c1["recipes"]) > _parse_dt(c0["recipes"])
    assert _parse_dt(c1["orders"]) > _parse_dt(c0["orders"])
    assert _parse_dt(c1["home"]) > _parse_dt(c0["home"])
    assert c1["catalog"] == c0["catalog"]


@pytest.mark.asyncio
async def test_order_lifecycle_changes_orders_customers_home(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Chocolate", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Chocolate",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "200"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    c0 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()

    # 1. Crear pedido
    await asyncio.sleep(0.01)
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Ana García",
            "delivery_at": "2026-11-20T12:00:00Z",
            "items": [
                {
                    "recipe_id": rec_id,
                    "quantity": "1",
                    "unit_price_cents": 35000,
                }
            ],
        },
    )
    assert order_resp.status_code == 201
    order_id = order_resp.json()["id"]

    c1 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert c1["orders"] is not None and (c0["orders"] is None or _parse_dt(c1["orders"]) > _parse_dt(c0["orders"]))
    assert c1["customers"] is not None and (c0["customers"] is None or _parse_dt(c1["customers"]) > _parse_dt(c0["customers"]))
    assert _parse_dt(c1["home"]) > _parse_dt(c0["home"])

    # 2. Agregar pago
    await asyncio.sleep(0.01)
    pay_resp = await client.post(
        f"/api/v1/orders/{order_id}/payments",
        headers=auth_headers,
        json={"amount_cents": 10000},
    )
    assert pay_resp.status_code == 201

    c2 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert _parse_dt(c2["orders"]) > _parse_dt(c1["orders"])
    assert _parse_dt(c2["customers"]) > _parse_dt(c1["customers"])
    assert _parse_dt(c2["home"]) > _parse_dt(c1["home"])

    # 3. Borrar pedido (soft delete)
    await asyncio.sleep(0.01)
    del_resp = await client.delete(f"/api/v1/orders/{order_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    c3 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert _parse_dt(c3["orders"]) > _parse_dt(c2["orders"])
    assert _parse_dt(c3["customers"]) > _parse_dt(c2["customers"])
    assert _parse_dt(c3["home"]) > _parse_dt(c2["home"])


@pytest.mark.asyncio
async def test_rename_customer_changes_customers_and_orders(client: AsyncClient, auth_headers):
    cust_resp = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Cliente Uno", "phone": "5512345678"},
    )
    assert cust_resp.status_code == 201
    cust_id = cust_resp.json()["id"]

    c0 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()

    await asyncio.sleep(0.01)
    patch_resp = await client.patch(
        f"/api/v1/customers/{cust_id}",
        headers=auth_headers,
        json={"name": "Cliente Uno Modificado"},
    )
    assert patch_resp.status_code == 200

    c1 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert _parse_dt(c1["customers"]) > _parse_dt(c0["customers"])
    assert c1["orders"] is not None and (c0["orders"] is None or _parse_dt(c1["orders"]) > _parse_dt(c0["orders"]))


@pytest.mark.asyncio
async def test_delete_supplier_changes_catalog(client: AsyncClient, auth_headers):
    supp_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Proveedor Central"},
    )
    assert supp_resp.status_code == 201
    supp_id = supp_resp.json()["id"]

    c0 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()

    await asyncio.sleep(0.01)
    del_resp = await client.delete(f"/api/v1/suppliers/{supp_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    c1 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert _parse_dt(c1["catalog"]) > _parse_dt(c0["catalog"])


@pytest.mark.asyncio
async def test_create_cost_version_changes_recipes(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Zulka",
            "package_quantity": "1000",
        },
    )
    pres_id = pres_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Almíbar",
            "yield_quantity": "100",
            "yield_unit": "ml",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "50"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    c0 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()

    await asyncio.sleep(0.01)
    ver_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={
            "name": "Con Zulka",
            "choices": [{"ingredient_id": ing_id, "presentation_id": pres_id}],
        },
    )
    assert ver_resp.status_code == 201

    c1 = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert _parse_dt(c1["recipes"]) > _parse_dt(c0["recipes"])


@pytest.mark.asyncio
async def test_changes_isolation_user_2_does_not_affect_user_1(
    client: AsyncClient, auth_headers, auth_headers_user_2
):
    # User 1 crea un ingrediente
    u1_ing = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Canela", "base_unit": "g"},
    )
    assert u1_ing.status_code == 201

    c_u1_initial = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert c_u1_initial["catalog"] is not None

    # User 2 realiza diversas escrituras
    u2_supp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers_user_2,
        json={"name": "Proveedor U2"},
    )
    assert u2_supp.status_code == 201

    u2_ing = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers_user_2,
        json={"name": "Nuez U2", "base_unit": "g"},
    )
    assert u2_ing.status_code == 201
    u2_ing_id = u2_ing.json()["id"]

    u2_pres = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers_user_2,
        json={
            "ingredient_id": u2_ing_id,
            "brand": "Nuez Brand",
            "package_quantity": "500",
            "price_cents": 12000,
        },
    )
    assert u2_pres.status_code == 201

    u2_cust = await client.post(
        "/api/v1/customers/",
        headers=auth_headers_user_2,
        json={"name": "Cliente U2"},
    )
    assert u2_cust.status_code == 201

    u2_exp = await client.post(
        "/api/v1/expenses/",
        headers=auth_headers_user_2,
        json={"description": "Gas U2", "amount_cents": 5000},
    )
    assert u2_exp.status_code == 201

    # User 2 tiene sus marcas actualizadas
    c_u2 = (await client.get("/api/v1/me/changes", headers=auth_headers_user_2)).json()
    assert c_u2["catalog"] is not None
    assert c_u2["home"] is not None
    assert c_u2["customers"] is not None

    # User 1 sigue exactamente con las mismas marcas de antes
    c_u1_after = (await client.get("/api/v1/me/changes", headers=auth_headers)).json()
    assert c_u1_after == c_u1_initial
