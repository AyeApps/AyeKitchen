from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient

from app.models.recipe import Recipe, RecipeItem, RecipeItemKind
from app.models.unit import BaseUnit
from app.services.presentation_service import (
    get_current_presentation,
    get_latest_price,
)


@pytest.mark.asyncio
async def test_create_presentation_with_price_and_cost_per_base_unit(
    client: AsyncClient,
    auth_headers,
):
    # 1. Create ingredient in "g"
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina Selecta", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    # 2. Create presentation with price_cents 2350 and package_quantity 1000
    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Selecta",
            "package_quantity": "1000",
            "price_cents": 2350,
        },
    )
    assert pres_resp.status_code == 201
    data = pres_resp.json()
    assert data["cost_per_base_unit"] == "2.350000"
    assert data["latest_price_cents"] == 2350
    assert data["latest_price_at"] is not None
    assert data["package_quantity"] == "1000"
    assert data["base_unit"] == "g"
    assert data["is_current"] is True


@pytest.mark.asyncio
async def test_create_presentation_with_package_unit_conversion(
    client: AsyncClient,
    auth_headers,
):
    # Find system unit "kg"
    units_resp = await client.get("/api/v1/units/", headers=auth_headers)
    kg = next(u for u in units_resp.json() if u["abbreviation"] == "kg")

    # Create ingredient in "g"
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar Zulka", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    # Create presentation: 1 kg -> should convert to 1000 g
    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Zulka",
            "package_quantity": "1",
            "package_unit_id": kg["id"],
        },
    )
    assert pres_resp.status_code == 201
    data = pres_resp.json()
    assert data["package_quantity"] == "1000"

    # Verify via GET
    get_resp = await client.get(f"/api/v1/presentations/{data['id']}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["package_quantity"] == "1000"


@pytest.mark.asyncio
async def test_add_price_updates_latest_price_and_history_descending(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Mantequilla Gloria", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    t1 = datetime.now(UTC) + timedelta(minutes=5)
    t2 = datetime.now(UTC) + timedelta(minutes=10)

    # Create presentation with initial price 1000
    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Gloria",
            "package_quantity": "500",
            "price_cents": 1000,
        },
    )
    pres_id = pres_resp.json()["id"]

    # Add second price at t1
    p1_resp = await client.post(
        f"/api/v1/presentations/{pres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 1200, "recorded_at": t1.isoformat(), "note": "Subió"},
    )
    assert p1_resp.status_code == 201
    assert p1_resp.json()["price_cents"] == 1200

    # Add third price at t2
    p2_resp = await client.post(
        f"/api/v1/presentations/{pres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 1500, "recorded_at": t2.isoformat(), "note": "Subió más"},
    )
    assert p2_resp.status_code == 201

    # Verify GET presentation shows latest price 1500
    get_resp = await client.get(f"/api/v1/presentations/{pres_id}", headers=auth_headers)
    assert get_resp.json()["latest_price_cents"] == 1500

    # Verify price history is sorted recorded_at descending
    prices_resp = await client.get(f"/api/v1/presentations/{pres_id}/prices", headers=auth_headers)
    assert prices_resp.status_code == 200
    prices = prices_resp.json()
    assert len(prices) == 3
    assert prices[0]["price_cents"] == 1500
    assert prices[1]["price_cents"] == 1200
    assert prices[2]["price_cents"] == 1000


@pytest.mark.asyncio
async def test_is_current_follows_latest_recorded_at(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Leche Entera", "base_unit": "ml"},
    )
    ing_id = ing_resp.json()["id"]

    t1 = datetime.now(UTC) - timedelta(hours=3)
    t2 = datetime.now(UTC) - timedelta(hours=2)
    t3 = datetime.now(UTC) - timedelta(hours=1)

    # Brand A with price at t1
    p_a = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Lala", "package_quantity": "1000"},
    )
    id_a = p_a.json()["id"]
    await client.post(
        f"/api/v1/presentations/{id_a}/prices",
        headers=auth_headers,
        json={"price_cents": 2500, "recorded_at": t1.isoformat()},
    )

    # Brand B with price at t2 (newer)
    p_b = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Alpura", "package_quantity": "1000"},
    )
    id_b = p_b.json()["id"]
    await client.post(
        f"/api/v1/presentations/{id_b}/prices",
        headers=auth_headers,
        json={"price_cents": 2600, "recorded_at": t2.isoformat()},
    )

    # Now Alpura is current, Lala is not
    get_a = await client.get(f"/api/v1/presentations/{id_a}", headers=auth_headers)
    get_b = await client.get(f"/api/v1/presentations/{id_b}", headers=auth_headers)
    assert get_a.json()["is_current"] is False
    assert get_b.json()["is_current"] is True

    # Lala receives newer price at t3
    await client.post(
        f"/api/v1/presentations/{id_a}/prices",
        headers=auth_headers,
        json={"price_cents": 2700, "recorded_at": t3.isoformat()},
    )

    # Now Lala is current again
    get_a2 = await client.get(f"/api/v1/presentations/{id_a}", headers=auth_headers)
    get_b2 = await client.get(f"/api/v1/presentations/{id_b}", headers=auth_headers)
    assert get_a2.json()["is_current"] is True
    assert get_b2.json()["is_current"] is False


@pytest.mark.asyncio
async def test_get_current_presentation_none_when_no_price(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Polvo Royal", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # Presentation without price
    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Royal", "package_quantity": "100"},
    )
    pres_id = pres_resp.json()["id"]

    # get_current_presentation must return None
    curr = await get_current_presentation(ws_id, ing_id)
    assert curr is None

    # is_current is False, price fields are None
    get_resp = await client.get(f"/api/v1/presentations/{pres_id}", headers=auth_headers)
    data = get_resp.json()
    assert data["is_current"] is False
    assert data["latest_price_cents"] is None
    assert data["cost_per_base_unit"] is None


@pytest.mark.asyncio
async def test_delete_pinned_presentation_in_recipe_in_use(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Chocolate Amargo", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Turin", "package_quantity": "500"},
    )
    pres_id = pres_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # Create recipe pinning this presentation
    rec = Recipe(
        workspace_id=ws_id,
        name="Pastel de Chocolate Fino",
        yield_quantity="1",
        yield_unit=BaseUnit.pz,
        items=[
            RecipeItem(
                kind=RecipeItemKind.ingredient,
                ref_id=ing_id,
                quantity="250",
                pinned_presentation_id=pres_id,
            )
        ],
    )
    await rec.insert()

    # Attempt to delete presentation -> 409 IN_USE
    del_resp = await client.delete(f"/api/v1/presentations/{pres_id}", headers=auth_headers)
    assert del_resp.status_code == 409
    assert del_resp.json()["code"] == "IN_USE"

    # Soft delete recipe
    await rec.soft_delete()

    # Now deletion succeeds -> 204
    del_resp2 = await client.delete(f"/api/v1/presentations/{pres_id}", headers=auth_headers)
    assert del_resp2.status_code == 204

    # Verify deleted -> 404
    get_resp = await client.get(f"/api/v1/presentations/{pres_id}", headers=auth_headers)
    assert get_resp.status_code == 404
    assert get_resp.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_presentation_invalid_reference_foreign_supplier(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    # User 1 creates ingredient
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Canela en Rama", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    # User 2 creates supplier
    supp_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers_user_2,
        json={"name": "Mercado U2"},
    )
    foreign_supp_id = supp_resp.json()["id"]

    # User 1 tries to create presentation referencing User 2's supplier -> 422
    resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "San Pedro",
            "supplier_id": foreign_supp_id,
            "package_quantity": "100",
        },
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_REFERENCE"


@pytest.mark.asyncio
async def test_presentation_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    # User 1 creates presentation
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Extracto Almendra", "base_unit": "ml"},
    )
    ing_id = ing_resp.json()["id"]

    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Deiman",
            "package_quantity": "120",
            "price_cents": 850,
        },
    )
    pres_id = pres_resp.json()["id"]

    # User 2 cannot access presentation
    u2_get = await client.get(f"/api/v1/presentations/{pres_id}", headers=auth_headers_user_2)
    assert u2_get.status_code == 404
    assert u2_get.json()["code"] == "NOT_FOUND"

    u2_patch = await client.patch(
        f"/api/v1/presentations/{pres_id}",
        headers=auth_headers_user_2,
        json={"brand": "Hacked"},
    )
    assert u2_patch.status_code == 404
    assert u2_patch.json()["code"] == "NOT_FOUND"

    u2_del = await client.delete(f"/api/v1/presentations/{pres_id}", headers=auth_headers_user_2)
    assert u2_del.status_code == 404
    assert u2_del.json()["code"] == "NOT_FOUND"

    # User 2 cannot access price history
    u2_prices = await client.get(f"/api/v1/presentations/{pres_id}/prices", headers=auth_headers_user_2)
    assert u2_prices.status_code == 404
    assert u2_prices.json()["code"] == "NOT_FOUND"

    u2_add_price = await client.post(
        f"/api/v1/presentations/{pres_id}/prices",
        headers=auth_headers_user_2,
        json={"price_cents": 999},
    )
    assert u2_add_price.status_code == 404
    assert u2_add_price.json()["code"] == "NOT_FOUND"

    # User 2 list does not include presentation
    u2_list = await client.get("/api/v1/presentations/", headers=auth_headers_user_2)
    assert u2_list.status_code == 200
    assert not any(p["id"] == pres_id for p in u2_list.json()["items"])


@pytest.mark.asyncio
async def test_crud_and_patch_presentation(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Nuez Picada", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    supp_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Central de Abastos"},
    )
    supp_id = supp_resp.json()["id"]

    # Create
    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Nuez de Oro",
            "supplier_id": supp_id,
            "package_quantity": "500",
            "barcode": "1234567890",
        },
    )
    assert pres_resp.status_code == 201
    pres = pres_resp.json()
    pres_id = pres["id"]
    assert pres["supplier_name"] == "Central de Abastos"
    assert pres["barcode"] == "1234567890"

    # PATCH brand and clear supplier
    patch_resp = await client.patch(
        f"/api/v1/presentations/{pres_id}",
        headers=auth_headers,
        json={
            "brand": "Nuez de Oro Gourmet",
            "supplier_id": None,
            "package_quantity": "600",
        },
    )
    assert patch_resp.status_code == 200
    patched = patch_resp.json()
    assert patched["brand"] == "Nuez de Oro Gourmet"
    assert patched["supplier_id"] is None
    assert patched["supplier_name"] is None
    assert patched["package_quantity"] == "600"


@pytest.mark.asyncio
async def test_list_presentations_filter_and_ordering(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Levadura Seca", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    t1 = datetime.now(UTC) - timedelta(hours=2)
    t2 = datetime.now(UTC)

    # 1. Presentation with older price
    p1_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Levadura A", "package_quantity": "100"},
    )
    p1_id = p1_resp.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p1_id}/prices",
        headers=auth_headers,
        json={"price_cents": 50, "recorded_at": t1.isoformat()},
    )

    # 2. Presentation with NO price (should be at the end)
    p2_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Levadura B", "package_quantity": "100"},
    )
    p2_id = p2_resp.json()["id"]

    # 3. Presentation with newer price
    p3_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Levadura C", "package_quantity": "100"},
    )
    p3_id = p3_resp.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p3_id}/prices",
        headers=auth_headers,
        json={"price_cents": 60, "recorded_at": t2.isoformat()},
    )

    # Query with ingredient_id filter
    list_resp = await client.get(f"/api/v1/presentations/?ingredient_id={ing_id}", headers=auth_headers)
    assert list_resp.status_code == 200
    items = list_resp.json()["items"]
    assert len(items) == 3
    # Order: p3 (newer price), p1 (older price), p2 (no price)
    assert items[0]["id"] == p3_id
    assert items[1]["id"] == p1_id
    assert items[2]["id"] == p2_id
    assert items[0]["is_current"] is True
    assert items[1]["is_current"] is False
    assert items[2]["is_current"] is False


@pytest.mark.asyncio
async def test_get_latest_price_service(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Sal de Mar", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "La Fina", "package_quantity": "1000", "price_cents": 150},
    )
    pres_id = pres_resp.json()["id"]

    pr = await get_latest_price(ws_id, pres_id)
    assert pr is not None
    assert pr.price_cents == 150

    # Presentation without prices
    pres2_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Pegaso", "package_quantity": "1000"},
    )
    pr2 = await get_latest_price(ws_id, pres2_resp.json()["id"])
    assert pr2 is None
