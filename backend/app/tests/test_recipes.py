import pytest
from httpx import AsyncClient

from app.models.recipe import Recipe, RecipeItem, RecipeItemKind
from app.models.unit import BaseUnit


@pytest.mark.asyncio
async def test_recipe_crud(client: AsyncClient, auth_headers):
    # Crear ingrediente base
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina Blanca", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    # 1. Crear subreceta: Bizcocho
    bizcocho_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Bizcocho esponjoso",
            "description": "Base para pasteles",
            "yield_quantity": "500",
            "yield_unit": "g",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "400",
                }
            ],
            "extra_costs": [
                {"name": "Gas", "cost_cents": 50}
            ],
        },
    )
    assert bizcocho_resp.status_code == 201
    bizcocho = bizcocho_resp.json()
    bizcocho_id = bizcocho["id"]
    assert bizcocho["name"] == "Bizcocho esponjoso"
    assert bizcocho["items"][0]["ref_name"] == "Harina Blanca"
    assert bizcocho["items"][0]["unit_name"] is None
    assert bizcocho["yield_quantity"] == "500"
    assert bizcocho["yield_unit"] == "g"

    # 2. Crear receta con subreceta: Pastel
    pastel_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel decorado",
            "description": "Pastel con betún",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "servings": 10,
            "margin_percent": 25,
            "items": [
                {
                    "kind": "recipe",
                    "ref_id": bizcocho_id,
                    "quantity": "500",
                }
            ],
            "extra_costs": [
                {"name": "Caja", "cost_cents": 100}
            ],
        },
    )
    assert pastel_resp.status_code == 201
    pastel = pastel_resp.json()
    pastel_id = pastel["id"]
    assert pastel["items"][0]["ref_name"] == "Bizcocho esponjoso"
    assert pastel["servings"] == 10
    assert pastel["margin_percent"] == 25

    # 3. GET por id
    get_resp = await client.get(
        f"/api/v1/recipes/{pastel_id}",
        headers=auth_headers,
    )
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == pastel_id
    assert get_resp.json()["items"][0]["ref_name"] == "Bizcocho esponjoso"

    # 4. Listar recetas con paginación y filtro q
    list_resp = await client.get(
        "/api/v1/recipes/?q=pastel",
        headers=auth_headers,
    )
    assert list_resp.status_code == 200
    list_data = list_resp.json()
    assert list_data["total"] == 1
    assert list_data["items"][0]["id"] == pastel_id
    assert "batch_cost_cents" in list_data["items"][0]
    assert "complete" in list_data["items"][0]

    # 5. PATCH receta
    patch_resp = await client.patch(
        f"/api/v1/recipes/{pastel_id}",
        headers=auth_headers,
        json={
            "name": "Pastel super decorado",
            "servings": 12,
            "extra_costs": [
                {"name": "Caja grande", "cost_cents": 150}
            ],
        },
    )
    assert patch_resp.status_code == 200
    patched = patch_resp.json()
    assert patched["name"] == "Pastel super decorado"
    assert patched["servings"] == 12
    assert len(patched["extra_costs"]) == 1
    assert patched["extra_costs"][0]["name"] == "Caja grande"

    # 6. DELETE receta
    del_resp = await client.delete(
        f"/api/v1/recipes/{pastel_id}",
        headers=auth_headers,
    )
    assert del_resp.status_code == 204

    # Verificar que ya no existe (404)
    get_after_del = await client.get(
        f"/api/v1/recipes/{pastel_id}",
        headers=auth_headers,
    )
    assert get_after_del.status_code == 404
    assert get_after_del.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_recipe_duplicate_name(client: AsyncClient, auth_headers):
    resp1 = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pay de Limón",
            "yield_quantity": "1",
            "yield_unit": "pz",
        },
    )
    assert resp1.status_code == 201

    # Mismo nombre en minúsculas
    resp2 = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "pay de limón",
            "yield_quantity": "1",
            "yield_unit": "pz",
        },
    )
    assert resp2.status_code == 409
    assert resp2.json()["code"] == "DUPLICATE_NAME"


@pytest.mark.asyncio
async def test_recipe_cycle_direct_and_indirect(client: AsyncClient, auth_headers):
    # Receta A
    rec_a_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta A",
            "yield_quantity": "100",
            "yield_unit": "g",
        },
    )
    assert rec_a_resp.status_code == 201
    a_id = rec_a_resp.json()["id"]

    # 1. Ciclo directo: A intenta usarse a sí misma
    patch_direct = await client.patch(
        f"/api/v1/recipes/{a_id}",
        headers=auth_headers,
        json={
            "items": [
                {"kind": "recipe", "ref_id": a_id, "quantity": "10"}
            ]
        },
    )
    assert patch_direct.status_code == 422
    assert patch_direct.json()["code"] == "RECIPE_CYCLE"

    # Receta B que usa A (B -> A)
    rec_b_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta B",
            "yield_quantity": "100",
            "yield_unit": "g",
            "items": [
                {"kind": "recipe", "ref_id": a_id, "quantity": "10"}
            ],
        },
    )
    assert rec_b_resp.status_code == 201
    b_id = rec_b_resp.json()["id"]

    # 2. Ciclo indirecto: A intenta usar B (A -> B -> A)
    patch_indirect = await client.patch(
        f"/api/v1/recipes/{a_id}",
        headers=auth_headers,
        json={
            "items": [
                {"kind": "recipe", "ref_id": b_id, "quantity": "10"}
            ]
        },
    )
    assert patch_indirect.status_code == 422
    assert patch_indirect.json()["code"] == "RECIPE_CYCLE"


@pytest.mark.asyncio
async def test_recipe_too_deep_11_levels(client: AsyncClient, auth_headers):
    # Construimos una cadena de 10 recetas permitida: Nivel 10 -> Nivel 9 -> ... -> Nivel 1
    # Nivel 1 es la hoja (base sin subrecetas) y Nivel 10 es la raíz
    prev_id = None
    created_ids = []
    for i in range(1, 11):
        items = []
        if prev_id:
            items.append({"kind": "recipe", "ref_id": prev_id, "quantity": "10"})
        resp = await client.post(
            "/api/v1/recipes/",
            headers=auth_headers,
            json={
                "name": f"Nivel {i}",
                "yield_quantity": "100",
                "yield_unit": "g",
                "items": items,
            },
        )
        assert resp.status_code == 201
        prev_id = resp.json()["id"]
        created_ids.append(prev_id)

    leaf_id = created_ids[0]  # Nivel 1 (hoja)
    root_id = created_ids[-1]  # Nivel 10 (raíz)

    # 1. Agregar una receta encima de la raíz de una cadena de 10 responde RECIPE_TOO_DEEP
    resp_top = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Nivel 11 Encima de Raíz",
            "yield_quantity": "100",
            "yield_unit": "g",
            "items": [
                {"kind": "recipe", "ref_id": root_id, "quantity": "10"}
            ],
        },
    )
    assert resp_top.status_code == 422
    assert resp_top.json()["code"] == "RECIPE_TOO_DEEP"

    # Verificar que no se guardó la receta nueva
    get_top_list = await client.get("/api/v1/recipes/?q=Nivel 11 Encima de Raíz", headers=auth_headers)
    assert get_top_list.status_code == 200
    assert get_top_list.json()["total"] == 0

    # 2. Hacer que una receta existente sin subrecetas pase a usar la raíz responde RECIPE_TOO_DEEP
    rec_existente = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Existente Aislada",
            "yield_quantity": "100",
            "yield_unit": "g",
            "items": [],
        },
    )).json()
    rec_existente_id = rec_existente["id"]

    patch_existente = await client.patch(
        f"/api/v1/recipes/{rec_existente_id}",
        headers=auth_headers,
        json={
            "items": [
                {"kind": "recipe", "ref_id": root_id, "quantity": "10"}
            ]
        },
    )
    assert patch_existente.status_code == 422
    assert patch_existente.json()["code"] == "RECIPE_TOO_DEEP"

    # Verificar que no se guardó y sigue sin items
    get_existente = await client.get(f"/api/v1/recipes/{rec_existente_id}", headers=auth_headers)
    assert get_existente.status_code == 200
    assert len(get_existente.json()["items"]) == 0

    # 3. Agregar subreceta bajo la hoja de una cadena de 10 responde RECIPE_TOO_DEEP y no guarda
    extra_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Subreceta Extra para Fondo",
            "yield_quantity": "50",
            "yield_unit": "g",
            "items": [],
        },
    )
    assert extra_resp.status_code == 201
    extra_id = extra_resp.json()["id"]

    patch_leaf = await client.patch(
        f"/api/v1/recipes/{leaf_id}",
        headers=auth_headers,
        json={
            "items": [
                {"kind": "recipe", "ref_id": extra_id, "quantity": "10"}
            ]
        },
    )
    assert patch_leaf.status_code == 422
    assert patch_leaf.json()["code"] == "RECIPE_TOO_DEEP"

    # Verificar que no se guardó y la hoja sigue sin items
    get_leaf = await client.get(f"/api/v1/recipes/{leaf_id}", headers=auth_headers)
    assert get_leaf.status_code == 200
    assert len(get_leaf.json()["items"]) == 0


@pytest.mark.asyncio
async def test_recipe_create_with_corrupted_cycle_in_db_does_not_500(client: AsyncClient, auth_headers):
    # Inserta directamente con el modelo Recipe un ciclo (A usa B y B usa A)
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    rec_a = Recipe(
        workspace_id=ws_id,
        name="Ciclo Corrupto A",
        yield_quantity="100",
        yield_unit=BaseUnit.g,
        items=[],
    )
    await rec_a.insert()

    rec_b = Recipe(
        workspace_id=ws_id,
        name="Ciclo Corrupto B",
        yield_quantity="100",
        yield_unit=BaseUnit.g,
        items=[
            RecipeItem(
                kind=RecipeItemKind.recipe,
                ref_id=str(rec_a.id),
                quantity="50",
            )
        ],
    )
    await rec_b.insert()

    rec_a.items = [
        RecipeItem(
            kind=RecipeItemKind.recipe,
            ref_id=str(rec_b.id),
            quantity="50",
        )
    ]
    await rec_a.save()

    # Intentar crear por la API una receta nueva sin subrecetas: debe responder 201 o 422, NUNCA 500
    resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Nueva Limpia",
            "yield_quantity": "100",
            "yield_unit": "g",
            "items": [],
        },
    )
    assert resp.status_code in (201, 422)
    assert resp.status_code != 500


@pytest.mark.asyncio
async def test_usable_as_subrecipe(client: AsyncClient, auth_headers):
    # Estructura:
    # A (base)
    # B usa A (B -> A)
    # C usa B (C -> B -> A)
    # D independiente
    r_a = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Receta A", "yield_quantity": "100", "yield_unit": "g"},
    )).json()
    a_id = r_a["id"]

    r_b = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta B",
            "yield_quantity": "100",
            "yield_unit": "g",
            "items": [{"kind": "recipe", "ref_id": a_id, "quantity": "10"}],
        },
    )).json()
    b_id = r_b["id"]

    r_c = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta C",
            "yield_quantity": "100",
            "yield_unit": "g",
            "items": [{"kind": "recipe", "ref_id": b_id, "quantity": "10"}],
        },
    )).json()
    c_id = r_c["id"]

    r_d = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Receta D", "yield_quantity": "100", "yield_unit": "g"},
    )).json()
    d_id = r_d["id"]

    # Para A: debe excluir a sí misma (A) y a sus ancestros (B y C, quienes la usan)
    usable_a_resp = await client.get(
        f"/api/v1/recipes/{a_id}/usable-as-subrecipe",
        headers=auth_headers,
    )
    assert usable_a_resp.status_code == 200
    usable_a_ids = [r["id"] for r in usable_a_resp.json()]
    assert d_id in usable_a_ids
    assert a_id not in usable_a_ids
    assert b_id not in usable_a_ids
    assert c_id not in usable_a_ids

    # Para D: como nadie la contiene, puede usar A, B y C
    usable_d_resp = await client.get(
        f"/api/v1/recipes/{d_id}/usable-as-subrecipe",
        headers=auth_headers,
    )
    assert usable_d_resp.status_code == 200
    usable_d_ids = [r["id"] for r in usable_d_resp.json()]
    assert d_id not in usable_d_ids
    assert a_id in usable_d_ids
    assert b_id in usable_d_ids
    assert c_id in usable_d_ids


@pytest.mark.asyncio
async def test_recipe_in_use_cannot_delete(client: AsyncClient, auth_headers):
    # Receta A y Receta B que usa A
    r_a = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Receta Base", "yield_quantity": "100", "yield_unit": "g"},
    )).json()
    a_id = r_a["id"]

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Consumidora",
            "yield_quantity": "100",
            "yield_unit": "g",
            "items": [{"kind": "recipe", "ref_id": a_id, "quantity": "10"}],
        },
    )

    # Intentar borrar Receta Base -> IN_USE
    del_resp = await client.delete(
        f"/api/v1/recipes/{a_id}",
        headers=auth_headers,
    )
    assert del_resp.status_code == 409
    assert del_resp.json()["code"] == "IN_USE"


@pytest.mark.asyncio
async def test_recipe_invalid_reference_pinned_presentation_other_ingredient(
    client: AsyncClient,
    auth_headers,
):
    ing1 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina", "base_unit": "g"},
    )).json()

    ing2 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar", "base_unit": "g"},
    )).json()

    # Presentación para Azúcar
    pres2 = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing2["id"],
            "brand": "Zulka",
            "package_quantity": "1000",
        },
    )).json()

    # Intentar crear receta usando Harina pero con pinned_presentation_id de Azúcar
    resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta con presentación ajena",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing1["id"],
                    "quantity": "100",
                    "pinned_presentation_id": pres2["id"],
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_REFERENCE"


@pytest.mark.asyncio
async def test_recipe_unit_not_convertible(client: AsyncClient, auth_headers):
    # Buscar unidad taza (ml)
    units_resp = await client.get("/api/v1/units/", headers=auth_headers)
    taza = next(u for u in units_resp.json() if u["abbreviation"] == "tz")

    # Ingrediente Harina (g) sin conversión propia para taza
    ing = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina Sin Conversión", "base_unit": "g"},
    )).json()

    # Intentar crear receta con 2 tazas de Harina
    resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta taza no convertible",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing["id"],
                    "quantity": "2",
                    "unit_id": taza["id"],
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "UNIT_NOT_CONVERTIBLE"


@pytest.mark.asyncio
async def test_recipe_workspace_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    # Usuario 1 crea receta
    r1 = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Secreta User 1",
            "yield_quantity": "1",
            "yield_unit": "pz",
        },
    )).json()
    r1_id = r1["id"]

    # Usuario 2 no puede leerla (404)
    get_resp = await client.get(
        f"/api/v1/recipes/{r1_id}",
        headers=auth_headers_user_2,
    )
    assert get_resp.status_code == 404
    assert get_resp.json()["code"] == "NOT_FOUND"

    # Usuario 2 no puede ver su costo (404)
    cost_resp = await client.get(
        f"/api/v1/recipes/{r1_id}/cost",
        headers=auth_headers_user_2,
    )
    assert cost_resp.status_code == 404
    assert cost_resp.json()["code"] == "NOT_FOUND"

    # Usuario 2 no puede ver usable-as-subrecipe (404)
    usable_resp = await client.get(
        f"/api/v1/recipes/{r1_id}/usable-as-subrecipe",
        headers=auth_headers_user_2,
    )
    assert usable_resp.status_code == 404
    assert usable_resp.json()["code"] == "NOT_FOUND"

    # Usuario 2 no puede editarla (404)
    patch_resp = await client.patch(
        f"/api/v1/recipes/{r1_id}",
        headers=auth_headers_user_2,
        json={"name": "Intento de hackeo"},
    )
    assert patch_resp.status_code == 404
    assert patch_resp.json()["code"] == "NOT_FOUND"

    # Usuario 2 no puede borrarla (404)
    del_resp = await client.delete(
        f"/api/v1/recipes/{r1_id}",
        headers=auth_headers_user_2,
    )
    assert del_resp.status_code == 404
    assert del_resp.json()["code"] == "NOT_FOUND"

    # Usuario 2 no la ve en su lista
    list_resp = await client.get(
        "/api/v1/recipes/",
        headers=auth_headers_user_2,
    )
    assert list_resp.status_code == 200
    ids_user_2 = [r["id"] for r in list_resp.json()["items"]]
    assert r1_id not in ids_user_2


@pytest.mark.asyncio
async def test_list_recipes_with_failing_cost_recipe(client: AsyncClient, auth_headers):
    # 1. Crear ingrediente sin conversión para taza
    ing = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina Sin Conversión Lista", "base_unit": "g"},
    )).json()
    ing_id = ing["id"]

    # Crear presentación con precio para receta válida
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Selecta",
            "package_quantity": "1000",
            "price_cents": 2000,
        },
    )

    # 2. Crear receta válida normal: Galletas
    rec_ok = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Galletas Válidas",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}
            ],
        },
    )).json()
    rec_ok_id = rec_ok["id"]

    # 3. Insertar directamente con Beanie una receta rota con taza no convertible
    units_resp = await client.get("/api/v1/units/", headers=auth_headers)
    taza = next(u for u in units_resp.json() if u["abbreviation"] == "tz")

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    rec_broken = Recipe(
        workspace_id=ws_id,
        name="Receta Rota Conversión",
        yield_quantity="1",
        yield_unit=BaseUnit.pz,
        items=[
            RecipeItem(
                kind=RecipeItemKind.ingredient,
                ref_id=ing_id,
                quantity="2",
                unit_id=taza["id"],
            )
        ],
    )
    await rec_broken.insert()
    broken_id = str(rec_broken.id)

    # 4. Listar recetas con GET /recipes/
    # Debe responder 200; la receta rota sale con batch_cost_cents=null y complete=false
    # mientras la válida sale con su costo normal
    list_resp = await client.get("/api/v1/recipes/", headers=auth_headers)
    assert list_resp.status_code == 200
    items_map = {item["id"]: item for item in list_resp.json()["items"]}

    assert broken_id in items_map
    assert items_map[broken_id]["batch_cost_cents"] is None
    assert items_map[broken_id]["complete"] is False

    assert rec_ok_id in items_map
    assert items_map[rec_ok_id]["batch_cost_cents"] == 200  # 100 g * 2000 / 1000 = 200
    assert items_map[rec_ok_id]["complete"] is True

    # 5. GET /recipes/{id}/cost de la rota sigue lanzando AppError 422
    cost_broken_resp = await client.get(
        f"/api/v1/recipes/{broken_id}/cost",
        headers=auth_headers,
    )
    assert cost_broken_resp.status_code == 422
    assert cost_broken_resp.json()["code"] == "UNIT_NOT_CONVERTIBLE"
