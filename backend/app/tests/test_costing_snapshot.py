import inspect
from datetime import UTC, datetime
from decimal import Decimal

import pytest
from httpx import AsyncClient

from app.core.errors import AppError
from app.models.ingredient import Ingredient
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.supplier import Supplier
from app.models.unit import BaseUnit, Unit
from app.services.conversion_service import (
    convert_between_base_units,
    convert_to_base,
)
from app.services.costing_snapshot import load_costing_snapshot
from app.services.presentation_service import (
    get_current_presentation,
    get_latest_price,
)


@pytest.mark.asyncio
async def test_costing_snapshot_no_queries_per_line(
    client: AsyncClient,
    auth_headers,
    monkeypatch,
):
    """Verifica que el costeo no haga consultas por línea.

    Arma un workspace con 3 recetas:
    - Receta 1: subreceta de la receta 2
    - Receta 2: con subreceta (Receta 1) y con marca fijada
    - Receta 3: con versión de costeo
    Verifica que las rutas respondan 200 con los mismos valores con monkeypatch activado.
    """
    # 1. Ingredientes
    ing_a_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de Trigo", "base_unit": "g"},
    )
    assert ing_a_resp.status_code == 201
    ing_a_id = ing_a_resp.json()["id"]

    ing_b_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Leche Entera", "base_unit": "ml"},
    )
    assert ing_b_resp.status_code == 201
    ing_b_id = ing_b_resp.json()["id"]

    # 2. Presentaciones y precios
    p_a1_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_a_id,
            "brand": "Marca Selecta",
            "package_quantity": "1000",
            "price_cents": 2500,
        },
    )
    assert p_a1_resp.status_code == 201
    p_a1_id = p_a1_resp.json()["id"]

    p_a2_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_a_id,
            "brand": "Marca Económica",
            "package_quantity": "1000",
            "price_cents": 2000,
        },
    )
    assert p_a2_resp.status_code == 201
    p_a2_id = p_a2_resp.json()["id"]

    p_b1_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_b_id,
            "brand": "Lala",
            "package_quantity": "1000",
            "price_cents": 3000,
        },
    )
    assert p_b1_resp.status_code == 201

    # 3. Receta 1: Crema pastelera (subreceta)
    rec1_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Crema Pastelera",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_b_id,
                    "quantity": "250",
                }
            ],
        },
    )
    assert rec1_resp.status_code == 201
    rec1_id = rec1_resp.json()["id"]

    # 4. Receta 2: Pastel con subreceta (receta 1) y marca fijada (p_a1)
    rec2_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Relleno",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "recipe",
                    "ref_id": rec1_id,
                    "quantity": "1",
                },
                {
                    "kind": "ingredient",
                    "ref_id": ing_a_id,
                    "quantity": "500",
                    "pinned_presentation_id": p_a1_id,
                },
            ],
        },
    )
    assert rec2_resp.status_code == 201
    rec2_id = rec2_resp.json()["id"]

    # 5. Receta 3: Pastel simple con versión
    rec3_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Simple",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_a_id,
                    "quantity": "400",
                }
            ],
        },
    )
    assert rec3_resp.status_code == 201
    rec3_id = rec3_resp.json()["id"]

    ver_resp = await client.post(
        f"/api/v1/recipes/{rec3_id}/versions/",
        headers=auth_headers,
        json={
            "name": "Versión Económica",
            "choices": [
                {
                    "ingredient_id": ing_a_id,
                    "presentation_id": p_a2_id,
                }
            ],
        },
    )
    assert ver_resp.status_code == 201
    ver_id = ver_resp.json()["id"]

    # Ejecutar peticiones ANTES de monkeypatch
    r_list_pre = await client.get("/api/v1/recipes/", headers=auth_headers)
    assert r_list_pre.status_code == 200

    r_cost_pre = await client.get(f"/api/v1/recipes/{rec2_id}/cost", headers=auth_headers)
    assert r_cost_pre.status_code == 200

    r_cost_ver_pre = await client.get(
        f"/api/v1/recipes/{rec3_id}/cost?version_id={ver_id}",
        headers=auth_headers,
    )
    assert r_cost_ver_pre.status_code == 200

    r_comp_pre = await client.get(
        f"/api/v1/recipes/{rec3_id}/versions/compare",
        headers=auth_headers,
    )
    assert r_comp_pre.status_code == 200

    # Activar monkeypatch para prohibir consultas por línea
    def _forbidden(name: str):
        def _fail(*args, **kwargs):
            raise RuntimeError(f"Consulta a BD prohibida durante costeo: {name}")

        return _fail

    orig_recipe_find_one = Recipe.find_one

    def _forbidden_recipe_find_one(*args, **kwargs):
        # Permitir resolución inicial de la receta o versión del endpoint por id
        stack = [f.function for f in inspect.stack()]
        if "get_recipe" in stack or "get_cost_version" in stack:
            return orig_recipe_find_one(*args, **kwargs)
        raise RuntimeError("Recipe.find_one prohibido durante costeo!")

    monkeypatch.setattr(Ingredient, "find_one", _forbidden("Ingredient.find_one"))
    monkeypatch.setattr(Recipe, "find_one", _forbidden_recipe_find_one)
    monkeypatch.setattr(Presentation, "find_one", _forbidden("Presentation.find_one"))
    monkeypatch.setattr(Supplier, "find_one", _forbidden("Supplier.find_one"))
    monkeypatch.setattr(Unit, "get", _forbidden("Unit.get"))
    monkeypatch.setattr(PriceRecord, "find_one", _forbidden("PriceRecord.find_one"))
    monkeypatch.setattr(
        "app.services.costing_service.get_current_presentation",
        _forbidden("get_current_presentation"),
    )
    monkeypatch.setattr(
        "app.services.presentation_service.get_current_presentation",
        _forbidden("get_current_presentation"),
    )
    monkeypatch.setattr(
        "app.services.costing_service.get_latest_price",
        _forbidden("get_latest_price"),
    )
    monkeypatch.setattr(
        "app.services.presentation_service.get_latest_price",
        _forbidden("get_latest_price"),
    )

    # Ejecutar peticiones DESPUÉS de monkeypatch: deben responder 200 idéntico
    r_list_post = await client.get("/api/v1/recipes/", headers=auth_headers)
    assert r_list_post.status_code == 200
    assert r_list_post.json() == r_list_pre.json()

    r_cost_post = await client.get(f"/api/v1/recipes/{rec2_id}/cost", headers=auth_headers)
    assert r_cost_post.status_code == 200
    assert r_cost_post.json() == r_cost_pre.json()

    r_cost_ver_post = await client.get(
        f"/api/v1/recipes/{rec3_id}/cost?version_id={ver_id}",
        headers=auth_headers,
    )
    assert r_cost_ver_post.status_code == 200
    assert r_cost_ver_post.json() == r_cost_ver_pre.json()

    r_comp_post = await client.get(
        f"/api/v1/recipes/{rec3_id}/versions/compare",
        headers=auth_headers,
    )
    assert r_comp_post.status_code == 200
    assert r_comp_post.json() == r_comp_pre.json()


@pytest.mark.asyncio
async def test_current_presentation_tie_breaker(client: AsyncClient, auth_headers):
    """La marca vigente de la foto coincide con get_current_presentation en un caso con empate de fecha."""
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    assert me_resp.status_code == 200
    ws_id = me_resp.json()["workspace"]["id"]

    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    # Crear presentación 1
    p1 = Presentation(
        workspace_id=ws_id,
        ingredient_id=ing_id,
        brand="Marca Vieja",
        package_quantity=Decimal("1000"),
        created_at=datetime(2026, 1, 1, 10, 0, tzinfo=UTC),
    )
    await p1.insert()

    # Crear presentación 2 (más reciente en created_at)
    p2 = Presentation(
        workspace_id=ws_id,
        ingredient_id=ing_id,
        brand="Marca Nueva",
        package_quantity=Decimal("1000"),
        created_at=datetime(2026, 1, 1, 11, 0, tzinfo=UTC),
    )
    await p2.insert()

    # Empate exacto en recorded_at
    tie_recorded_at = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)

    pr1 = PriceRecord(
        workspace_id=ws_id,
        presentation_id=str(p1.id),
        price_cents=2000,
        recorded_at=tie_recorded_at,
        created_at=datetime(2026, 1, 1, 12, 1, tzinfo=UTC),
    )
    await pr1.insert()

    pr2 = PriceRecord(
        workspace_id=ws_id,
        presentation_id=str(p2.id),
        price_cents=2200,
        recorded_at=tie_recorded_at,
        created_at=datetime(2026, 1, 1, 12, 2, tzinfo=UTC),
    )
    await pr2.insert()

    orig_current = await get_current_presentation(ws_id, ing_id)
    assert orig_current is not None
    assert str(orig_current.presentation.id) == str(p2.id)

    snapshot = await load_costing_snapshot(ws_id)
    snap_current = snapshot.get_current_presentation(ing_id)

    assert snap_current is not None
    assert str(snap_current.presentation.id) == str(orig_current.presentation.id)
    assert str(snap_current.price_record.id) == str(orig_current.price_record.id)
    assert snap_current.price_record.price_cents == 2200

    orig_price = await get_latest_price(ws_id, str(p2.id))
    assert orig_price is not None
    assert orig_price.price_cents == 2200
    assert snapshot.get_latest_price(str(p2.id)) is not None
    assert snapshot.get_latest_price(str(p2.id)).price_cents == 2200


@pytest.mark.asyncio
async def test_unit_not_convertible_identical_with_and_without_snapshot(
    client: AsyncClient,
    auth_headers,
):
    """Una unidad no convertible da el mismo UNIT_NOT_CONVERTIBLE, con el mismo texto, con y sin foto."""
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    assert me_resp.status_code == 200
    ws_id = me_resp.json()["workspace"]["id"]

    ing = Ingredient(
        workspace_id=ws_id,
        name="Mantequilla",
        base_unit=BaseUnit.g,
    )
    await ing.insert()

    # Buscar unidad 'ml' (base_unit ml) que no es convertible a 'g' sin regla propia
    ml_unit = await Unit.find_one(Unit.abbreviation == "ml", Unit.deleted_at == None)  # noqa: E711
    assert ml_unit is not None

    # 1. Probar convert_to_base sin snapshot
    err_without_snap: AppError | None = None
    try:
        await convert_to_base(ws_id, Decimal("2"), str(ml_unit.id), ing)
    except AppError as e:
        err_without_snap = e

    assert err_without_snap is not None
    assert err_without_snap.status_code == 422
    assert err_without_snap.code == "UNIT_NOT_CONVERTIBLE"

    # 2. Probar convert_to_base con snapshot
    snapshot = await load_costing_snapshot(ws_id)
    err_with_snap: AppError | None = None
    try:
        snapshot.convert_to_base(Decimal("2"), str(ml_unit.id), ing)
    except AppError as e:
        err_with_snap = e

    assert err_with_snap is not None
    assert err_with_snap.status_code == err_without_snap.status_code
    assert err_with_snap.code == err_without_snap.code
    assert err_with_snap.detail == err_without_snap.detail

    # 3. Probar convert_between_base_units sin snapshot
    err_between_without: AppError | None = None
    try:
        await convert_between_base_units(ws_id, Decimal("5"), str(ml_unit.id), BaseUnit.g)
    except AppError as e:
        err_between_without = e

    assert err_between_without is not None
    assert err_between_without.status_code == 422
    assert err_between_without.code == "UNIT_NOT_CONVERTIBLE"

    # 4. Probar convert_between_base_units con snapshot
    err_between_with: AppError | None = None
    try:
        snapshot.convert_between_base_units(Decimal("5"), str(ml_unit.id), BaseUnit.g)
    except AppError as e:
        err_between_with = e

    assert err_between_with is not None
    assert err_between_with.status_code == err_between_without.status_code
    assert err_between_with.code == err_between_without.code
    assert err_between_with.detail == err_between_without.detail


@pytest.mark.asyncio
async def test_workspace_isolation_snapshot(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    """Aislamiento: la foto de un workspace no trae datos del otro usuario."""
    # Usuario 1 crea datos
    me1 = await client.get("/api/v1/me/", headers=auth_headers)
    ws1_id = me1.json()["workspace"]["id"]

    ing1_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Chocolate Amargo", "base_unit": "g"},
    )
    ing1_id = ing1_resp.json()["id"]

    supp1_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Proveedor Uno"},
    )
    supp1_id = supp1_resp.json()["id"]

    pres1_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing1_id,
            "brand": "Turín",
            "package_quantity": "500",
            "supplier_id": supp1_id,
            "price_cents": 5000,
        },
    )
    pres1_id = pres1_resp.json()["id"]

    rec1_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Trufas",
            "yield_quantity": "10",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing1_id, "quantity": "200"}],
        },
    )
    rec1_id = rec1_resp.json()["id"]

    unit1_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "Barra",
            "abbreviation": "br",
            "base_unit": "g",
            "factor_to_base": "100",
        },
    )
    unit1_id = unit1_resp.json()["id"]

    # Usuario 2 crea datos en su workspace
    me2 = await client.get("/api/v1/me/", headers=auth_headers_user_2)
    ws2_id = me2.json()["workspace"]["id"]
    assert ws1_id != ws2_id

    ing2_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers_user_2,
        json={"name": "Vainilla Líquida", "base_unit": "ml"},
    )
    ing2_id = ing2_resp.json()["id"]

    supp2_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers_user_2,
        json={"name": "Proveedor Dos"},
    )
    supp2_id = supp2_resp.json()["id"]

    pres2_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers_user_2,
        json={
            "ingredient_id": ing2_id,
            "brand": "Papantla",
            "package_quantity": "250",
            "supplier_id": supp2_id,
            "price_cents": 1500,
        },
    )
    pres2_id = pres2_resp.json()["id"]

    rec2_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers_user_2,
        json={
            "name": "Flan",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing2_id, "quantity": "10"}],
        },
    )
    rec2_id = rec2_resp.json()["id"]

    unit2_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers_user_2,
        json={
            "name": "Gotero",
            "abbreviation": "got",
            "base_unit": "ml",
            "factor_to_base": "1",
        },
    )
    unit2_id = unit2_resp.json()["id"]

    # Cargar snapshot de Workspace 1
    snap1 = await load_costing_snapshot(ws1_id)

    # Verificar que tiene sus propios datos
    assert str(snap1.workspace.id) == ws1_id
    assert ing1_id in snap1.ingredients_by_id
    assert supp1_id in snap1.suppliers_by_id
    assert pres1_id in snap1.presentations_by_id
    assert pres1_id in snap1.latest_prices_by_presentation
    assert rec1_id in snap1.recipes_by_id
    assert unit1_id in snap1.units_by_id

    # Verificar que NO contiene ningún dato del Workspace 2
    assert ing2_id not in snap1.ingredients_by_id
    assert supp2_id not in snap1.suppliers_by_id
    assert pres2_id not in snap1.presentations_by_id
    assert pres2_id not in snap1.latest_prices_by_presentation
    assert rec2_id not in snap1.recipes_by_id
    assert unit2_id not in snap1.units_by_id

    # Verificar exclusión de soft-deleted
    await client.delete(f"/api/v1/recipes/{rec1_id}", headers=auth_headers)
    snap1_after = await load_costing_snapshot(ws1_id)
    assert rec1_id not in snap1_after.recipes_by_id
