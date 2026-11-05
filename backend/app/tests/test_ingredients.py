from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient

from app.models.presentation import Presentation
from app.models.recipe import Recipe, RecipeItem, RecipeItemKind
from app.models.unit import BaseUnit


@pytest.mark.asyncio
async def test_crud_ingredient(client: AsyncClient, auth_headers):
    # Find system unit "taza"
    units_resp = await client.get("/api/v1/units/", headers=auth_headers)
    taza = next(u for u in units_resp.json() if u["name"] == "taza")

    # 1. Create
    create_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Harina de trigo",
            "base_unit": "g",
            "group": "Secos",
            "notes": "Todo uso",
            "conversions": [
                {"unit_id": taza["id"], "quantity_in_base": "125"},
            ],
        },
    )
    assert create_resp.status_code == 201
    created = create_resp.json()
    assert created["name"] == "Harina de trigo"
    assert created["base_unit"] == "g"
    assert created["group"] == "Secos"
    assert len(created["conversions"]) == 1
    assert created["conversions"][0]["unit_id"] == taza["id"]
    assert created["conversions"][0]["unit_name"] == "taza"
    assert created["conversions"][0]["quantity_in_base"] == "125"
    ing_id = created["id"]

    # 2. Get by ID
    get_resp = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == ing_id
    assert get_resp.json()["conversions"][0]["unit_name"] == "taza"

    # 3. Patch
    patch_resp = await client.patch(
        f"/api/v1/ingredients/{ing_id}",
        headers=auth_headers,
        json={"name": "Harina de Repostería", "notes": "Especial para pasteles"},
    )
    assert patch_resp.status_code == 200
    patched = patch_resp.json()
    assert patched["name"] == "Harina de Repostería"
    assert patched["notes"] == "Especial para pasteles"

    # 4. Delete
    del_resp = await client.delete(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    # 5. Verify deleted
    get_again = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert get_again.status_code == 404
    assert get_again.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_ingredient_duplicate_name(client: AsyncClient, auth_headers):
    resp1 = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Mantequilla", "base_unit": "g"},
    )
    assert resp1.status_code == 201

    resp2 = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "  mantequilla  ", "base_unit": "g"},
    )
    assert resp2.status_code == 409
    assert resp2.json()["code"] == "DUPLICATE_NAME"


@pytest.mark.asyncio
async def test_ingredient_invalid_reference(client: AsyncClient, auth_headers, auth_headers_user_2):
    # 1. Non-existent unit id
    resp1 = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Azúcar",
            "base_unit": "g",
            "conversions": [{"unit_id": "507f1f77bcf86cd799439011", "quantity_in_base": "200"}],
        },
    )
    assert resp1.status_code == 422
    assert resp1.json()["code"] == "INVALID_REFERENCE"

    # 2. Unit from another workspace
    u2_unit_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers_user_2,
        json={"name": "Copa", "abbreviation": "cp", "base_unit": "ml", "factor_to_base": "150"},
    )
    assert u2_unit_resp.status_code == 201
    u2_unit_id = u2_unit_resp.json()["id"]

    resp2 = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Vino",
            "base_unit": "ml",
            "conversions": [{"unit_id": u2_unit_id, "quantity_in_base": "150"}],
        },
    )
    assert resp2.status_code == 422
    assert resp2.json()["code"] == "INVALID_REFERENCE"

    # 3. Repeated unit_id in conversions
    units_resp = await client.get("/api/v1/units/", headers=auth_headers)
    taza_id = next(u["id"] for u in units_resp.json() if u["name"] == "taza")

    resp3 = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Cacao",
            "base_unit": "g",
            "conversions": [
                {"unit_id": taza_id, "quantity_in_base": "100"},
                {"unit_id": taza_id, "quantity_in_base": "110"},
            ],
        },
    )
    assert resp3.status_code == 422
    assert resp3.json()["code"] == "INVALID_REFERENCE"


@pytest.mark.asyncio
async def test_ingredient_pagination_and_filters(client: AsyncClient, auth_headers):
    # Create several ingredients
    names = [
        ("Azúcar Blanca", "Secos"),
        ("Azúcar Glass", "Secos"),
        ("Azúcar Mascabado", "Secos"),
        ("Crema para Batir", "Lácteos"),
        ("Leche Condensada", "Lácteos"),
    ]
    for name, grp in names:
        await client.post(
            "/api/v1/ingredients/",
            headers=auth_headers,
            json={"name": name, "base_unit": "g", "group": grp},
        )

    # Test pagination
    p_resp = await client.get("/api/v1/ingredients/?page=1&limit=2", headers=auth_headers)
    assert p_resp.status_code == 200
    data = p_resp.json()
    assert data["total"] == 5
    assert data["page"] == 1
    assert data["limit"] == 2
    assert data["pages"] == 3
    assert len(data["items"]) == 2

    # Test page 2
    p2_resp = await client.get("/api/v1/ingredients/?page=2&limit=2", headers=auth_headers)
    assert len(p2_resp.json()["items"]) == 2

    # Test filter q (case-insensitive contains)
    q_resp = await client.get("/api/v1/ingredients/?q=azúcar", headers=auth_headers)
    assert q_resp.status_code == 200
    q_data = q_resp.json()
    assert q_data["total"] == 3
    assert all("Azúcar" in item["name"] for item in q_data["items"])

    # Test filter group
    g_resp = await client.get("/api/v1/ingredients/?group=Lácteos", headers=auth_headers)
    assert g_resp.status_code == 200
    g_data = g_resp.json()
    assert g_data["total"] == 2
    assert all(item["group"] == "Lácteos" for item in g_data["items"])


@pytest.mark.asyncio
async def test_ingredient_patch_base_unit_in_use(client: AsyncClient, auth_headers):
    create_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Aceite de Oliva", "base_unit": "ml"},
    )
    ing_id = create_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # Create active presentation for this ingredient
    pres = Presentation(
        workspace_id=ws_id,
        ingredient_id=ing_id,
        brand="Borges",
        package_quantity="1000",
    )
    await pres.insert()

    # Try to change base_unit to "g"
    patch_resp = await client.patch(
        f"/api/v1/ingredients/{ing_id}",
        headers=auth_headers,
        json={"base_unit": "g"},
    )
    assert patch_resp.status_code == 409
    assert patch_resp.json()["code"] == "IN_USE"


@pytest.mark.asyncio
async def test_ingredient_delete_in_use_recipe(client: AsyncClient, auth_headers):
    create_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Polvo para Hornear", "base_unit": "g"},
    )
    ing_id = create_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # Create active recipe referencing this ingredient
    rec = Recipe(
        workspace_id=ws_id,
        name="Bizcocho Vainilla",
        yield_quantity="1",
        yield_unit=BaseUnit.pz,
        items=[
            RecipeItem(
                kind=RecipeItemKind.ingredient,
                ref_id=ing_id,
                quantity="10",
                unit_id=None,
            )
        ],
    )
    await rec.insert()

    del_resp = await client.delete(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert del_resp.status_code == 409
    assert del_resp.json()["code"] == "IN_USE"


@pytest.mark.asyncio
async def test_ingredient_delete_soft_deletes_presentations(client: AsyncClient, auth_headers):
    create_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Vainilla Liquida", "base_unit": "ml"},
    )
    ing_id = create_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    pres = Presentation(
        workspace_id=ws_id,
        ingredient_id=ing_id,
        brand="Molina",
        package_quantity="500",
    )
    await pres.insert()

    del_resp = await client.delete(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    # Presentation must now be soft-deleted
    updated_pres = await Presentation.get(pres.id)
    assert updated_pres.deleted_at is not None


@pytest.mark.asyncio
async def test_ingredient_isolation(client: AsyncClient, auth_headers, auth_headers_user_2):
    # User 1 creates ingredient
    create_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Ingrediente Secreto", "base_unit": "g"},
    )
    assert create_resp.status_code == 201
    ing_id = create_resp.json()["id"]

    # User 2 list should not contain it
    u2_list = await client.get("/api/v1/ingredients/", headers=auth_headers_user_2)
    assert u2_list.status_code == 200
    assert not any(i["id"] == ing_id for i in u2_list.json()["items"])

    # User 2 GET -> 404
    u2_get = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers_user_2)
    assert u2_get.status_code == 404
    assert u2_get.json()["code"] == "NOT_FOUND"

    # User 2 PATCH -> 404
    u2_patch = await client.patch(
        f"/api/v1/ingredients/{ing_id}",
        headers=auth_headers_user_2,
        json={"name": "Hacked"},
    )
    assert u2_patch.status_code == 404
    assert u2_patch.json()["code"] == "NOT_FOUND"

    # User 2 DELETE -> 404
    u2_del = await client.delete(f"/api/v1/ingredients/{ing_id}", headers=auth_headers_user_2)
    assert u2_del.status_code == 404
    assert u2_del.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_update_ingredient_base_unit_in_use_recipe(client: AsyncClient, auth_headers):
    # 1. Create ingredient with base_unit "g" and no presentations
    create_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de Almendras", "base_unit": "g"},
    )
    assert create_resp.status_code == 201
    ing_id = create_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # 2. Create active recipe referencing this ingredient
    rec = Recipe(
        workspace_id=ws_id,
        name="Macarons",
        yield_quantity="20",
        yield_unit=BaseUnit.pz,
        items=[
            RecipeItem(
                kind=RecipeItemKind.ingredient,
                ref_id=ing_id,
                quantity="200",
                unit_id=None,
            )
        ],
    )
    await rec.insert()

    # 3. Attempt to change base_unit to "ml" -> 409 IN_USE
    patch_resp = await client.patch(
        f"/api/v1/ingredients/{ing_id}",
        headers=auth_headers,
        json={"base_unit": "ml"},
    )
    assert patch_resp.status_code == 409
    assert patch_resp.json()["code"] == "IN_USE"

    # 4. Verify ingredient preserved its original base_unit
    get_resp = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["base_unit"] == "g"


@pytest.mark.asyncio
async def test_ingredient_patch_conversion_in_use_cannot_remove(client: AsyncClient, auth_headers):
    # 1. Obtener unidad taza
    units_resp = await client.get("/api/v1/units/", headers=auth_headers)
    taza = next(u for u in units_resp.json() if u["abbreviation"] == "tz")

    # 2. Crear ingrediente con conversión de taza = 125 g
    create_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Harina Pastelera Especial",
            "base_unit": "g",
            "conversions": [
                {"unit_id": taza["id"], "quantity_in_base": "125"}
            ],
        },
    )
    assert create_resp.status_code == 201
    ing_id = create_resp.json()["id"]

    # 3. Crear receta activa que usa Harina con unidad taza
    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Panqué de Vainilla",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "2",
                    "unit_id": taza["id"],
                }
            ],
        },
    )
    assert rec_resp.status_code == 201

    # 4. Intentar quitar la conversión de taza -> 409 IN_USE
    patch_del_resp = await client.patch(
        f"/api/v1/ingredients/{ing_id}",
        headers=auth_headers,
        json={"conversions": []},
    )
    assert patch_del_resp.status_code == 409
    assert patch_del_resp.json()["code"] == "IN_USE"

    # Verificar que la conversión sigue guardada
    get_resp = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert len(get_resp.json()["conversions"]) == 1
    assert get_resp.json()["conversions"][0]["quantity_in_base"] == "125"

    # 5. Cambiar el quantity_in_base de esa conversión sí está permitido -> 200
    patch_update_resp = await client.patch(
        f"/api/v1/ingredients/{ing_id}",
        headers=auth_headers,
        json={
            "conversions": [
                {"unit_id": taza["id"], "quantity_in_base": "130"}
            ]
        },
    )
    assert patch_update_resp.status_code == 200
    get_resp2 = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert len(get_resp2.json()["conversions"]) == 1
    assert get_resp2.json()["conversions"][0]["quantity_in_base"] == "130"


@pytest.mark.asyncio
async def test_ingredient_brand_summary_no_brands(client: AsyncClient, auth_headers):
    resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Vainilla", "base_unit": "ml"},
    )
    assert resp.status_code == 201
    created = resp.json()
    assert created["brands_count"] == 0
    assert created["current_brand"] is None

    get_resp = await client.get(f"/api/v1/ingredients/{created['id']}", headers=auth_headers)
    assert get_resp.status_code == 200
    detail = get_resp.json()
    assert detail["brands_count"] == 0
    assert detail["current_brand"] is None


@pytest.mark.asyncio
async def test_ingredient_brand_summary_three_brands(client: AsyncClient, auth_headers):
    # Crear proveedor
    sup_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Costco"},
    )
    assert sup_resp.status_code == 201
    supplier_id = sup_resp.json()["id"]

    # Crear ingrediente
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de fuerza", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    # Marca 1: Sin precio
    p1_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Marca Sin Precio",
            "package_quantity": "1000",
        },
    )
    assert p1_resp.status_code == 201

    # Marca 2: Precio más antiguo (t1)
    t1 = datetime.now(UTC) - timedelta(days=2)
    p2_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Marca Antigua",
            "package_quantity": "1000",
            "price_cents": 2000,
        },
    )
    assert p2_resp.status_code == 201
    p2_id = p2_resp.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p2_id}/prices",
        headers=auth_headers,
        json={"price_cents": 2000, "recorded_at": t1.isoformat()},
    )

    # Marca 3: Precio más reciente (t2) con proveedor Costco
    t2 = datetime.now(UTC)
    p3_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Marca Vigente",
            "supplier_id": supplier_id,
            "package_quantity": "1000",
            "price_cents": 2350,
        },
    )
    assert p3_resp.status_code == 201
    p3_id = p3_resp.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p3_id}/prices",
        headers=auth_headers,
        json={"price_cents": 2350, "recorded_at": t2.isoformat()},
    )

    # Consultar ingrediente
    get_resp = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    data = get_resp.json()
    assert data["brands_count"] == 3
    assert data["current_brand"] is not None
    assert data["current_brand"]["presentation_id"] == p3_id
    assert data["current_brand"]["brand"] == "Marca Vigente"
    assert data["current_brand"]["supplier_name"] == "Costco"
    assert data["current_brand"]["cost_per_base_unit"] == "2.350000"


@pytest.mark.asyncio
async def test_ingredient_brand_summary_deleted_brand_not_counted(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Levadura", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    p1 = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Levadura A", "package_quantity": "500", "price_cents": 1000},
    )
    p2 = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Levadura B", "package_quantity": "500", "price_cents": 1200},
    )
    p1_id = p1.json()["id"]
    p2_id = p2.json()["id"]

    get1 = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert get1.json()["brands_count"] == 2

    del_resp = await client.delete(f"/api/v1/presentations/{p2_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    get2 = await client.get(f"/api/v1/ingredients/{ing_id}", headers=auth_headers)
    assert get2.json()["brands_count"] == 1
    assert get2.json()["current_brand"]["presentation_id"] == p1_id
    assert get2.json()["current_brand"]["brand"] == "Levadura A"


@pytest.mark.asyncio
async def test_ingredient_brand_summary_list_each_has_own_summary(client: AsyncClient, auth_headers):
    ing_a = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Avena", "base_unit": "g"},
    )
    ing_a_id = ing_a.json()["id"]
    pres_a = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_a_id, "brand": "Quaker", "package_quantity": "800", "price_cents": 4000},
    )
    pres_a_id = pres_a.json()["id"]

    ing_b = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Canela en polvo", "base_unit": "g"},
    )
    ing_b_id = ing_b.json()["id"]

    list_resp = await client.get("/api/v1/ingredients/", headers=auth_headers)
    assert list_resp.status_code == 200
    items = {item["id"]: item for item in list_resp.json()["items"]}

    assert ing_a_id in items
    assert items[ing_a_id]["brands_count"] == 1
    assert items[ing_a_id]["current_brand"]["presentation_id"] == pres_a_id
    assert items[ing_a_id]["current_brand"]["brand"] == "Quaker"

    assert ing_b_id in items
    assert items[ing_b_id]["brands_count"] == 0
    assert items[ing_b_id]["current_brand"] is None


@pytest.mark.asyncio
async def test_ingredient_brand_summary_isolation(client: AsyncClient, auth_headers, auth_headers_user_2):
    ing_u1 = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Cacao", "base_unit": "g"},
    )
    ing_u1_id = ing_u1.json()["id"]

    ing_u2 = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers_user_2,
        json={"name": "Cacao", "base_unit": "g"},
    )
    ing_u2_id = ing_u2.json()["id"]
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers_user_2,
        json={"ingredient_id": ing_u2_id, "brand": "Hershey", "package_quantity": "500", "price_cents": 5500},
    )

    get_u1 = await client.get(f"/api/v1/ingredients/{ing_u1_id}", headers=auth_headers)
    assert get_u1.status_code == 200
    assert get_u1.json()["brands_count"] == 0
    assert get_u1.json()["current_brand"] is None

    list_u1 = await client.get("/api/v1/ingredients/", headers=auth_headers)
    items_u1 = {item["id"]: item for item in list_u1.json()["items"]}
    assert items_u1[ing_u1_id]["brands_count"] == 0
    assert items_u1[ing_u1_id]["current_brand"] is None

    get_u2 = await client.get(f"/api/v1/ingredients/{ing_u2_id}", headers=auth_headers_user_2)
    assert get_u2.status_code == 200
    assert get_u2.json()["brands_count"] == 1
    assert get_u2.json()["current_brand"]["brand"] == "Hershey"
