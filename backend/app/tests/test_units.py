import pytest
from httpx import AsyncClient

from app.models.ingredient import Ingredient, IngredientConversion
from app.models.recipe import Recipe, RecipeItem, RecipeItemKind
from app.models.unit import BaseUnit, Unit
from app.services.unit_service import seed_system_units


@pytest.mark.asyncio
async def test_seed_system_units_idempotent():
    await seed_system_units()
    count_first = await Unit.find(Unit.workspace_id == None).count()  # noqa: E711
    assert count_first == 12

    await seed_system_units()
    count_second = await Unit.find(Unit.workspace_id == None).count()  # noqa: E711
    assert count_second == 12


@pytest.mark.asyncio
async def test_list_units(client: AsyncClient, auth_headers):
    resp = await client.get("/api/v1/units/", headers=auth_headers)
    assert resp.status_code == 200
    units = resp.json()
    assert len(units) >= 12
    taza = next((u for u in units if u["abbreviation"] == "tz"), None)
    assert taza is not None
    assert taza["name"] == "taza"
    assert taza["base_unit"] == "ml"
    assert taza["factor_to_base"] == "240"
    assert taza["is_system"] is True


@pytest.mark.asyncio
async def test_crud_custom_unit(client: AsyncClient, auth_headers):
    # 1. Create
    create_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "Cucharón",
            "abbreviation": "cchn",
            "base_unit": "ml",
            "factor_to_base": "60",
        },
    )
    assert create_resp.status_code == 201
    created = create_resp.json()
    assert created["name"] == "Cucharón"
    assert created["abbreviation"] == "cchn"
    assert created["factor_to_base"] == "60"
    assert created["is_system"] is False
    unit_id = created["id"]

    # 2. Get by ID
    get_resp = await client.get(f"/api/v1/units/{unit_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == unit_id

    # 3. Patch
    patch_resp = await client.patch(
        f"/api/v1/units/{unit_id}",
        headers=auth_headers,
        json={"name": "Cucharón Grande", "factor_to_base": "75"},
    )
    assert patch_resp.status_code == 200
    patched = patch_resp.json()
    assert patched["name"] == "Cucharón Grande"
    assert patched["factor_to_base"] == "75"

    # 4. List includes custom unit
    list_resp = await client.get("/api/v1/units/", headers=auth_headers)
    assert any(u["id"] == unit_id for u in list_resp.json())

    # 5. Delete
    del_resp = await client.delete(f"/api/v1/units/{unit_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    # 6. Verify deleted
    get_again = await client.get(f"/api/v1/units/{unit_id}", headers=auth_headers)
    assert get_again.status_code == 404
    assert get_again.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_system_unit_readonly(client: AsyncClient, auth_headers):
    list_resp = await client.get("/api/v1/units/", headers=auth_headers)
    taza = next(u for u in list_resp.json() if u["name"] == "taza")

    # PATCH system unit
    patch_resp = await client.patch(
        f"/api/v1/units/{taza['id']}",
        headers=auth_headers,
        json={"name": "Taza Modificada"},
    )
    assert patch_resp.status_code == 403
    assert patch_resp.json()["code"] == "SYSTEM_UNIT_READONLY"

    # DELETE system unit
    del_resp = await client.delete(f"/api/v1/units/{taza['id']}", headers=auth_headers)
    assert del_resp.status_code == 403
    assert del_resp.json()["code"] == "SYSTEM_UNIT_READONLY"


@pytest.mark.asyncio
async def test_duplicate_name_or_abbr(client: AsyncClient, auth_headers):
    # Duplicate with system unit name (case-insensitive)
    resp1 = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "TAZA",
            "abbreviation": "tz_custom",
            "base_unit": "ml",
            "factor_to_base": "240",
        },
    )
    assert resp1.status_code == 409
    assert resp1.json()["code"] == "DUPLICATE_NAME"

    # Duplicate with system unit abbr (case-insensitive)
    resp2 = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "Taza personalizada",
            "abbreviation": "TZ",
            "base_unit": "ml",
            "factor_to_base": "250",
        },
    )
    assert resp2.status_code == 409
    assert resp2.json()["code"] == "DUPLICATE_NAME"

    # Create a custom unit
    resp3 = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "Pizca",
            "abbreviation": "pzc",
            "base_unit": "g",
            "factor_to_base": "0.5",
        },
    )
    assert resp3.status_code == 201

    # Duplicate with custom unit
    resp4 = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "pizca",
            "abbreviation": "pzc2",
            "base_unit": "g",
            "factor_to_base": "1",
        },
    )
    assert resp4.status_code == 409
    assert resp4.json()["code"] == "DUPLICATE_NAME"


@pytest.mark.asyncio
async def test_delete_unit_in_use_ingredient(client: AsyncClient, auth_headers):
    # Create custom unit
    u_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={"name": "Gotero", "abbreviation": "gt", "base_unit": "ml", "factor_to_base": "0.05"},
    )
    unit_id = u_resp.json()["id"]

    # Get workspace id
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # Create ingredient referencing this unit in conversions
    ing = Ingredient(
        workspace_id=ws_id,
        name="Esencia de vainilla",
        base_unit=BaseUnit.ml,
        conversions=[IngredientConversion(unit_id=unit_id, quantity_in_base="0.05")],
    )
    await ing.insert()

    # Try to delete unit
    del_resp = await client.delete(f"/api/v1/units/{unit_id}", headers=auth_headers)
    assert del_resp.status_code == 409
    assert del_resp.json()["code"] == "IN_USE"


@pytest.mark.asyncio
async def test_delete_unit_in_use_recipe(client: AsyncClient, auth_headers):
    # Create custom unit
    u_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={"name": "Barra", "abbreviation": "bar", "base_unit": "g", "factor_to_base": "90"},
    )
    unit_id = u_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # Create recipe referencing this unit in items
    rec = Recipe(
        workspace_id=ws_id,
        name="Galletas",
        yield_quantity="10",
        yield_unit=BaseUnit.pz,
        items=[
            RecipeItem(
                kind=RecipeItemKind.ingredient,
                ref_id="dummy_ref",
                quantity="2",
                unit_id=unit_id,
            )
        ],
    )
    await rec.insert()

    del_resp = await client.delete(f"/api/v1/units/{unit_id}", headers=auth_headers)
    assert del_resp.status_code == 409
    assert del_resp.json()["code"] == "IN_USE"


@pytest.mark.asyncio
async def test_unit_isolation(client: AsyncClient, auth_headers, auth_headers_user_2):
    # User 1 creates custom unit
    create_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "Pizca Secreta",
            "abbreviation": "ps",
            "base_unit": "g",
            "factor_to_base": "0.2",
        },
    )
    assert create_resp.status_code == 201
    unit_id = create_resp.json()["id"]

    # User 2 list should NOT include it
    list_user2 = await client.get("/api/v1/units/", headers=auth_headers_user_2)
    assert not any(u["id"] == unit_id for u in list_user2.json())

    # User 2 GET by id -> 404
    get_user2 = await client.get(f"/api/v1/units/{unit_id}", headers=auth_headers_user_2)
    assert get_user2.status_code == 404
    assert get_user2.json()["code"] == "NOT_FOUND"

    # User 2 PATCH -> 404
    patch_user2 = await client.patch(
        f"/api/v1/units/{unit_id}",
        headers=auth_headers_user_2,
        json={"name": "Hacked"},
    )
    assert patch_user2.status_code == 404
    assert patch_user2.json()["code"] == "NOT_FOUND"

    # User 2 DELETE -> 404
    del_user2 = await client.delete(f"/api/v1/units/{unit_id}", headers=auth_headers_user_2)
    assert del_user2.status_code == 404
    assert del_user2.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_update_unit_base_unit_in_use_recipe(client: AsyncClient, auth_headers):
    # 1. Create custom unit
    u_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={"name": "Vaso", "abbreviation": "vs", "base_unit": "ml", "factor_to_base": "250"},
    )
    assert u_resp.status_code == 201
    unit_id = u_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # 2. Create active recipe referencing this unit
    rec = Recipe(
        workspace_id=ws_id,
        name="Licuado",
        yield_quantity="1",
        yield_unit=BaseUnit.pz,
        items=[
            RecipeItem(
                kind=RecipeItemKind.ingredient,
                ref_id="dummy_ref",
                quantity="1",
                unit_id=unit_id,
            )
        ],
    )
    await rec.insert()

    # 3. Attempt to change base_unit to "g" -> 409 IN_USE
    patch_resp = await client.patch(
        f"/api/v1/units/{unit_id}",
        headers=auth_headers,
        json={"base_unit": "g"},
    )
    assert patch_resp.status_code == 409
    assert patch_resp.json()["code"] == "IN_USE"

    # Verify unit preserved original base_unit
    get_resp = await client.get(f"/api/v1/units/{unit_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["base_unit"] == "ml"


@pytest.mark.asyncio
async def test_update_unit_base_unit_in_use_ingredient(client: AsyncClient, auth_headers):
    # 1. Create custom unit
    u_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={"name": "Medida", "abbreviation": "med", "base_unit": "g", "factor_to_base": "50"},
    )
    assert u_resp.status_code == 201
    unit_id = u_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # 2. Create ingredient referencing this unit in conversions
    ing = Ingredient(
        workspace_id=ws_id,
        name="Cacao en polvo",
        base_unit=BaseUnit.g,
        conversions=[IngredientConversion(unit_id=unit_id, quantity_in_base="50")],
    )
    await ing.insert()

    # 3. Attempt to change base_unit to "ml" -> 409 IN_USE
    patch_resp = await client.patch(
        f"/api/v1/units/{unit_id}",
        headers=auth_headers,
        json={"base_unit": "ml"},
    )
    assert patch_resp.status_code == 409
    assert patch_resp.json()["code"] == "IN_USE"

    # Verify unit preserved original base_unit
    get_resp = await client.get(f"/api/v1/units/{unit_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["base_unit"] == "g"


@pytest.mark.asyncio
async def test_update_unit_factor_to_base_in_use_recipe(client: AsyncClient, auth_headers):
    # 1. Create custom unit
    u_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={"name": "Tazón", "abbreviation": "tzn", "base_unit": "ml", "factor_to_base": "300"},
    )
    assert u_resp.status_code == 201
    unit_id = u_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # 2. Create active recipe referencing this unit
    rec = Recipe(
        workspace_id=ws_id,
        name="Sopa",
        yield_quantity="2",
        yield_unit=BaseUnit.pz,
        items=[
            RecipeItem(
                kind=RecipeItemKind.ingredient,
                ref_id="dummy_ref",
                quantity="1",
                unit_id=unit_id,
            )
        ],
    )
    await rec.insert()

    # 3. Change factor_to_base of unit in use -> 200
    patch_resp = await client.patch(
        f"/api/v1/units/{unit_id}",
        headers=auth_headers,
        json={"factor_to_base": "350"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["factor_to_base"] == "350"
    assert patch_resp.json()["base_unit"] == "ml"
