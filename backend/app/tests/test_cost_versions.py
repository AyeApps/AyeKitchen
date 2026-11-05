from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_cost_version_crud_and_duplicate_name(client: AsyncClient, auth_headers):
    # Setup flour and two presentations
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de trigo", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    p1_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Selecta",
            "package_quantity": "1000",
            "price_cents": 2350,
        },
    )
    assert p1_resp.status_code == 201
    p1_id = p1_resp.json()["id"]

    p2_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Tres Estrellas",
            "package_quantity": "1000",
            "price_cents": 3000,
        },
    )
    assert p2_resp.status_code == 201
    p2_id = p2_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel simple",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "300"}],
        },
    )
    assert rec_resp.status_code == 201
    recipe_id = rec_resp.json()["id"]

    # Name "Base" (case-insensitive) is forbidden -> 409 DUPLICATE_NAME
    for invalid_name in ["Base", "base", " BASE "]:
        resp = await client.post(
            f"/api/v1/recipes/{recipe_id}/versions/",
            headers=auth_headers,
            json={"name": invalid_name},
        )
        assert resp.status_code == 409
        assert resp.json()["code"] == "DUPLICATE_NAME"

    # Create version
    v_resp = await client.post(
        f"/api/v1/recipes/{recipe_id}/versions/",
        headers=auth_headers,
        json={
            "name": "Con Tres Estrellas",
            "choices": [{"ingredient_id": ing_id, "presentation_id": p2_id}],
        },
    )
    assert v_resp.status_code == 201
    v_data = v_resp.json()
    assert v_data["name"] == "Con Tres Estrellas"
    assert v_data["recipe_id"] == recipe_id
    assert len(v_data["choices"]) == 1
    assert v_data["choices"][0]["ingredient_id"] == ing_id
    assert v_data["choices"][0]["ingredient_name"] == "Harina de trigo"
    assert v_data["choices"][0]["presentation_id"] == p2_id
    assert v_data["choices"][0]["brand"] == "Tres Estrellas"
    v1_id = v_data["id"]

    # Duplicate name in same recipe -> 409 DUPLICATE_NAME
    dup_resp = await client.post(
        f"/api/v1/recipes/{recipe_id}/versions/",
        headers=auth_headers,
        json={"name": "con tres estrellas"},
    )
    assert dup_resp.status_code == 409
    assert dup_resp.json()["code"] == "DUPLICATE_NAME"

    # List versions
    list_resp = await client.get(
        f"/api/v1/recipes/{recipe_id}/versions/",
        headers=auth_headers,
    )
    assert list_resp.status_code == 200
    versions = list_resp.json()
    assert len(versions) == 1
    assert versions[0]["id"] == v1_id

    # Create second version
    v2_resp = await client.post(
        f"/api/v1/recipes/{recipe_id}/versions/",
        headers=auth_headers,
        json={"name": "Con Selecta", "choices": [{"ingredient_id": ing_id, "presentation_id": p1_id}]},
    )
    assert v2_resp.status_code == 201
    v2_id = v2_resp.json()["id"]

    # Patch version 2 to rename to same name as version 1 -> 409 DUPLICATE_NAME
    patch_dup = await client.patch(
        f"/api/v1/recipes/{recipe_id}/versions/{v2_id}",
        headers=auth_headers,
        json={"name": "CON TRES ESTRELLAS"},
    )
    assert patch_dup.status_code == 409
    assert patch_dup.json()["code"] == "DUPLICATE_NAME"

    # Patch version 2 to rename to "Base" -> 409 DUPLICATE_NAME
    patch_base = await client.patch(
        f"/api/v1/recipes/{recipe_id}/versions/{v2_id}",
        headers=auth_headers,
        json={"name": "Base"},
    )
    assert patch_base.status_code == 409
    assert patch_base.json()["code"] == "DUPLICATE_NAME"

    # Patch version 2 to valid name
    patch_ok = await client.patch(
        f"/api/v1/recipes/{recipe_id}/versions/{v2_id}",
        headers=auth_headers,
        json={"name": "Con Selecta Económica"},
    )
    assert patch_ok.status_code == 200
    assert patch_ok.json()["name"] == "Con Selecta Económica"

    # Delete version 2
    del_resp = await client.delete(
        f"/api/v1/recipes/{recipe_id}/versions/{v2_id}",
        headers=auth_headers,
    )
    assert del_resp.status_code == 204

    # Now versions has only version 1
    list_resp2 = await client.get(
        f"/api/v1/recipes/{recipe_id}/versions/",
        headers=auth_headers,
    )
    assert len(list_resp2.json()) == 1


@pytest.mark.asyncio
async def test_cost_version_invalid_reference_validations(client: AsyncClient, auth_headers):
    # Flour and Sugar
    f_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de trigo", "base_unit": "g"},
    )
    f_id = f_resp.json()["id"]
    fp_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": f_id, "brand": "Selecta", "package_quantity": "1000", "price_cents": 2350},
    )
    fp_id = fp_resp.json()["id"]

    s_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar", "base_unit": "g"},
    )
    s_id = s_resp.json()["id"]
    sp_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": s_id, "brand": "Zulka", "package_quantity": "1000", "price_cents": 2800},
    )
    sp_id = sp_resp.json()["id"]

    # Recipe with only Flour
    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Solo Harina",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": f_id, "quantity": "300"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    # 1. Ingredient not in recipe
    r1 = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "V1", "choices": [{"ingredient_id": s_id, "presentation_id": sp_id}]},
    )
    assert r1.status_code == 422
    assert r1.json()["code"] == "INVALID_REFERENCE"

    # 2. Repeated ingredient in choices
    r2 = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={
            "name": "V2",
            "choices": [
                {"ingredient_id": f_id, "presentation_id": fp_id},
                {"ingredient_id": f_id, "presentation_id": fp_id},
            ],
        },
    )
    assert r2.status_code == 422
    assert r2.json()["code"] == "INVALID_REFERENCE"

    # 3. Presentation of another ingredient (brand of sugar for flour)
    r3 = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "V3", "choices": [{"ingredient_id": f_id, "presentation_id": sp_id}]},
    )
    assert r3.status_code == 422
    assert r3.json()["code"] == "INVALID_REFERENCE"
    assert "harina de trigo" in r3.json()["detail"].lower()

    # 4. Nonexistent presentation
    r4 = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "V4", "choices": [{"ingredient_id": f_id, "presentation_id": "000000000000000000000000"}]},
    )
    assert r4.status_code == 422
    assert r4.json()["code"] == "INVALID_REFERENCE"


@pytest.mark.asyncio
async def test_costing_contract_flour_example_with_versions(client: AsyncClient, auth_headers):
    # Harina 1000 g a $23.50 (Selecta) y 1000 g a $30.00 (Tres Estrellas).
    # Receta con 300 g.
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de trigo", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    # Selecta created first with older price, or Tres Estrellas created with older price so Selecta is current
    t_old = (datetime.now(UTC) - timedelta(hours=2)).isoformat()
    t_new = datetime.now(UTC).isoformat()

    p_tres = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Tres Estrellas",
            "package_quantity": "1000",
        },
    )
    p_tres_id = p_tres.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p_tres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 3000, "recorded_at": t_old},
    )

    p_sel = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Selecta",
            "package_quantity": "1000",
        },
    )
    p_sel_id = p_sel.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p_sel_id}/prices",
        headers=auth_headers,
        json={"price_cents": 2350, "recorded_at": t_new},
    )

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel básico",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "300"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    # 1. Cost without version:
    cost_base = await client.get(
        f"/api/v1/recipes/{rec_id}/cost",
        headers=auth_headers,
    )
    assert cost_base.status_code == 200
    base_data = cost_base.json()
    assert base_data["batch_cost_cents"] == 705
    assert base_data["version_id"] is None
    assert base_data["version_name"] is None
    assert len(base_data["lines"]) == 1
    assert base_data["lines"][0]["cost_cents"] == 705
    assert base_data["lines"][0]["brand_source"] == "current"
    assert base_data["lines"][0]["pinned"] is False

    # 2. Create version that chooses Tres Estrellas
    v_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={
            "name": "Con Tres Estrellas",
            "choices": [{"ingredient_id": ing_id, "presentation_id": p_tres_id}],
        },
    )
    assert v_resp.status_code == 201
    v_id = v_resp.json()["id"]

    # Cost with version:
    cost_v = await client.get(
        f"/api/v1/recipes/{rec_id}/cost?version_id={v_id}",
        headers=auth_headers,
    )
    assert cost_v.status_code == 200
    v_cost_data = cost_v.json()
    assert v_cost_data["batch_cost_cents"] == 900
    assert v_cost_data["version_id"] == v_id
    assert v_cost_data["version_name"] == "Con Tres Estrellas"
    assert len(v_cost_data["lines"]) == 1
    assert v_cost_data["lines"][0]["cost_cents"] == 900
    assert v_cost_data["lines"][0]["brand_source"] == "version"
    assert v_cost_data["lines"][0]["pinned"] is True


@pytest.mark.asyncio
async def test_costing_pinned_line_and_missing_price(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    p_sel = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Selecta", "package_quantity": "1000", "price_cents": 2350},
    )
    p_sel_id = p_sel.json()["id"]

    # Presentation without price
    p_noprice = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Sin Precio", "package_quantity": "1000"},
    )
    p_noprice_id = p_noprice.json()["id"]

    # Recipe pinned to Selecta
    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel fijado",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "300",
                    "pinned_presentation_id": p_sel_id,
                }
            ],
        },
    )
    rec_id = rec_resp.json()["id"]

    # Version with no choices
    v_empty_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "Sin Cambios"},
    )
    v_empty_id = v_empty_resp.json()["id"]

    cost_pinned = await client.get(
        f"/api/v1/recipes/{rec_id}/cost?version_id={v_empty_id}",
        headers=auth_headers,
    )
    assert cost_pinned.status_code == 200
    p_data = cost_pinned.json()
    assert p_data["lines"][0]["brand_source"] == "recipe"
    assert p_data["lines"][0]["pinned"] is True
    assert p_data["lines"][0]["cost_cents"] == 705

    # Version choosing presentation with missing price
    v_noprice_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "Con Sin Precio", "choices": [{"ingredient_id": ing_id, "presentation_id": p_noprice_id}]},
    )
    v_noprice_id = v_noprice_resp.json()["id"]

    cost_noprice = await client.get(
        f"/api/v1/recipes/{rec_id}/cost?version_id={v_noprice_id}",
        headers=auth_headers,
    )
    assert cost_noprice.status_code == 200
    np_data = cost_noprice.json()
    assert np_data["complete"] is False
    assert np_data["lines"][0]["missing_price"] is True
    assert np_data["lines"][0]["cost_cents"] == 0
    assert np_data["lines"][0]["brand_source"] == "version"
    assert np_data["lines"][0]["pinned"] is True


@pytest.mark.asyncio
async def test_compare_cost_versions_endpoint(client: AsyncClient, auth_headers):
    # Harina 1000g: Selecta 2350 (705 base), Tres Estrellas 3000 (900), Economica 2000 (600)
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    t1 = (datetime.now(UTC) - timedelta(hours=3)).isoformat()
    t2 = (datetime.now(UTC) - timedelta(hours=2)).isoformat()
    t3 = (datetime.now(UTC) - timedelta(hours=1)).isoformat()

    p_tres = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Tres Estrellas", "package_quantity": "1000"},
    )
    p_tres_id = p_tres.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p_tres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 3000, "recorded_at": t1},
    )

    p_eco = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Económica", "package_quantity": "1000"},
    )
    p_eco_id = p_eco.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p_eco_id}/prices",
        headers=auth_headers,
        json={"price_cents": 2000, "recorded_at": t2},
    )

    p_sel = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Selecta", "package_quantity": "1000"},
    )
    p_sel_id = p_sel.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p_sel_id}/prices",
        headers=auth_headers,
        json={"price_cents": 2350, "recorded_at": t3},
    )

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "servings": 4,
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "300"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    v1_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "Con Tres Estrellas", "choices": [{"ingredient_id": ing_id, "presentation_id": p_tres_id}]},
    )
    v1_id = v1_resp.json()["id"]

    v2_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "Con Económica", "choices": [{"ingredient_id": ing_id, "presentation_id": p_eco_id}]},
    )
    v2_id = v2_resp.json()["id"]

    compare_resp = await client.get(
        f"/api/v1/recipes/{rec_id}/versions/compare",
        headers=auth_headers,
    )
    assert compare_resp.status_code == 200
    rows = compare_resp.json()
    assert len(rows) == 3

    # Base first
    assert rows[0]["version_id"] is None
    assert rows[0]["name"] == "Base"
    assert rows[0]["batch_cost_cents"] == 705

    # Version 1 next
    assert rows[1]["version_id"] == v1_id
    assert rows[1]["name"] == "Con Tres Estrellas"
    assert rows[1]["batch_cost_cents"] == 900

    # Version 2 last
    assert rows[2]["version_id"] == v2_id
    assert rows[2]["name"] == "Con Económica"
    assert rows[2]["batch_cost_cents"] == 600


@pytest.mark.asyncio
async def test_update_recipe_items_removes_choices(client: AsyncClient, auth_headers):
    f_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina", "base_unit": "g"},
    )
    f_id = f_resp.json()["id"]
    fp_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": f_id, "brand": "Selecta", "package_quantity": "1000", "price_cents": 2350},
    )
    fp_id = fp_resp.json()["id"]

    s_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar", "base_unit": "g"},
    )
    s_id = s_resp.json()["id"]
    sp_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": s_id, "brand": "Zulka", "package_quantity": "1000", "price_cents": 2800},
    )
    sp_id = sp_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Completo",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {"kind": "ingredient", "ref_id": f_id, "quantity": "300"},
                {"kind": "ingredient", "ref_id": s_id, "quantity": "100"},
            ],
        },
    )
    rec_id = rec_resp.json()["id"]

    # Version with choices for both
    v_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={
            "name": "Versión 1",
            "choices": [
                {"ingredient_id": f_id, "presentation_id": fp_id},
                {"ingredient_id": s_id, "presentation_id": sp_id},
            ],
        },
    )
    assert len(v_resp.json()["choices"]) == 2

    # Update recipe items to only have Harina
    patch_rec = await client.patch(
        f"/api/v1/recipes/{rec_id}",
        headers=auth_headers,
        json={
            "items": [{"kind": "ingredient", "ref_id": f_id, "quantity": "300"}],
        },
    )
    assert patch_rec.status_code == 200

    # Version should now only have Harina choice
    v_list = await client.get(f"/api/v1/recipes/{rec_id}/versions/", headers=auth_headers)
    v_choices = v_list.json()[0]["choices"]
    assert len(v_choices) == 1
    assert v_choices[0]["ingredient_id"] == f_id


@pytest.mark.asyncio
async def test_delete_presentation_removes_choice_and_falls_back(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    t_old = (datetime.now(UTC) - timedelta(hours=2)).isoformat()
    t_new = datetime.now(UTC).isoformat()

    p_tres = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Tres Estrellas", "package_quantity": "1000"},
    )
    p_tres_id = p_tres.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p_tres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 3000, "recorded_at": t_old},
    )

    p_sel = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Selecta", "package_quantity": "1000"},
    )
    p_sel_id = p_sel.json()["id"]
    await client.post(
        f"/api/v1/presentations/{p_sel_id}/prices",
        headers=auth_headers,
        json={"price_cents": 2350, "recorded_at": t_new},
    )

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "300"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    v_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "Con Tres Estrellas", "choices": [{"ingredient_id": ing_id, "presentation_id": p_tres_id}]},
    )
    v_id = v_resp.json()["id"]

    # Before deleting, cost with version is 900
    c_before = await client.get(f"/api/v1/recipes/{rec_id}/cost?version_id={v_id}", headers=auth_headers)
    assert c_before.json()["batch_cost_cents"] == 900

    # Delete Tres Estrellas
    del_p = await client.delete(f"/api/v1/presentations/{p_tres_id}", headers=auth_headers)
    assert del_p.status_code == 204

    # Version choice should be removed
    v_list = await client.get(f"/api/v1/recipes/{rec_id}/versions/", headers=auth_headers)
    assert len(v_list.json()[0]["choices"]) == 0

    # Cost with version falls back to current (Selecta, 705)
    c_after = await client.get(f"/api/v1/recipes/{rec_id}/cost?version_id={v_id}", headers=auth_headers)
    assert c_after.json()["batch_cost_cents"] == 705
    assert c_after.json()["lines"][0]["brand_source"] == "current"


@pytest.mark.asyncio
async def test_delete_recipe_soft_deletes_versions(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta a borrar",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    v_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "V1"},
    )
    assert v_resp.status_code == 201
    v_id = v_resp.json()["id"]

    # Delete recipe
    del_r = await client.delete(f"/api/v1/recipes/{rec_id}", headers=auth_headers)
    assert del_r.status_code == 204

    # Versions list returns 404
    v_list = await client.get(f"/api/v1/recipes/{rec_id}/versions/", headers=auth_headers)
    assert v_list.status_code == 404

    # Cost with version returns 404
    cost_v = await client.get(f"/api/v1/recipes/{rec_id}/cost?version_id={v_id}", headers=auth_headers)
    assert cost_v.status_code == 404


@pytest.mark.asyncio
async def test_version_of_another_recipe_returns_404(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    r1_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta A",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}],
        },
    )
    r1_id = r1_resp.json()["id"]

    r2_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta B",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}],
        },
    )
    r2_id = r2_resp.json()["id"]

    v_resp = await client.post(
        f"/api/v1/recipes/{r1_id}/versions/",
        headers=auth_headers,
        json={"name": "Versión de A"},
    )
    v_id = v_resp.json()["id"]

    # Accessing version of recipe A via recipe B endpoints returns 404 NOT_FOUND
    c_resp = await client.get(f"/api/v1/recipes/{r2_id}/cost?version_id={v_id}", headers=auth_headers)
    assert c_resp.status_code == 404
    assert c_resp.json()["code"] == "NOT_FOUND"

    patch_resp = await client.patch(
        f"/api/v1/recipes/{r2_id}/versions/{v_id}",
        headers=auth_headers,
        json={"name": "Intento"},
    )
    assert patch_resp.status_code == 404
    assert patch_resp.json()["code"] == "NOT_FOUND"

    del_resp = await client.delete(
        f"/api/v1/recipes/{r2_id}/versions/{v_id}",
        headers=auth_headers,
    )
    assert del_resp.status_code == 404
    assert del_resp.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_cost_version_workspace_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    # User 1 creates recipe and version
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina U1", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    p_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_id, "brand": "Marca U1", "package_quantity": "1000", "price_cents": 2000},
    )
    p_id = p_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta U1",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    v_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=auth_headers,
        json={"name": "Versión U1", "choices": [{"ingredient_id": ing_id, "presentation_id": p_id}]},
    )
    assert v_resp.status_code == 201
    v_id = v_resp.json()["id"]

    # User 2 cannot access user 1's version endpoints
    assert (await client.get(f"/api/v1/recipes/{rec_id}/versions/", headers=auth_headers_user_2)).status_code == 404
    assert (
        await client.post(
            f"/api/v1/recipes/{rec_id}/versions/",
            headers=auth_headers_user_2,
            json={"name": "Intento"},
        )
    ).status_code == 404
    assert (
        await client.get(
            f"/api/v1/recipes/{rec_id}/versions/compare",
            headers=auth_headers_user_2,
        )
    ).status_code == 404
    assert (
        await client.patch(
            f"/api/v1/recipes/{rec_id}/versions/{v_id}",
            headers=auth_headers_user_2,
            json={"name": "Intento"},
        )
    ).status_code == 404
    assert (
        await client.delete(
            f"/api/v1/recipes/{rec_id}/versions/{v_id}",
            headers=auth_headers_user_2,
        )
    ).status_code == 404
    assert (
        await client.get(
            f"/api/v1/recipes/{rec_id}/cost?version_id={v_id}",
            headers=auth_headers_user_2,
        )
    ).status_code == 404

    # User 2 creates own recipe, but cannot choose User 1's presentation
    u2_ing = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers_user_2,
        json={"name": "Harina U2", "base_unit": "g"},
    )
    u2_ing_id = u2_ing.json()["id"]
    u2_rec = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers_user_2,
        json={
            "name": "Receta U2",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": u2_ing_id, "quantity": "100"}],
        },
    )
    u2_rec_id = u2_rec.json()["id"]

    # Try to choose User 1's presentation
    foreign_p_choice = await client.post(
        f"/api/v1/recipes/{u2_rec_id}/versions/",
        headers=auth_headers_user_2,
        json={"name": "Con Marca Ajena", "choices": [{"ingredient_id": u2_ing_id, "presentation_id": p_id}]},
    )
    assert foreign_p_choice.status_code == 422
    assert foreign_p_choice.json()["code"] == "INVALID_REFERENCE"
