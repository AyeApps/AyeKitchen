from decimal import Decimal

import pytest
from httpx import AsyncClient

from app.models.base import round_to_cents
from app.models.recipe import Recipe, RecipeItem, RecipeItemKind
from app.models.unit import BaseUnit


@pytest.mark.asyncio
async def test_costing_contract_flour_example(client: AsyncClient, auth_headers):
    # Harina 1000 g a $23.50 (2350), línea de 300 g -> cost_cents 705
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de trigo", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

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
    pres_id = pres_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel simple",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "300",
                }
            ],
        },
    )
    assert rec_resp.status_code == 201
    recipe_id = rec_resp.json()["id"]

    cost_resp = await client.get(
        f"/api/v1/recipes/{recipe_id}/cost",
        headers=auth_headers,
    )
    assert cost_resp.status_code == 200
    cost_data = cost_resp.json()

    assert cost_data["recipe_id"] == recipe_id
    assert len(cost_data["lines"]) == 1
    line = cost_data["lines"][0]
    assert line["kind"] == "ingredient"
    assert line["ref_id"] == ing_id
    assert line["ref_name"] == "Harina de trigo"
    assert line["quantity"] == "300"
    assert line["unit_name"] is None
    assert line["quantity_in_base"] == "300"
    assert line["base_unit"] == "g"
    assert line["presentation_id"] == pres_id
    assert line["presentation_label"] == "Selecta · 1000 g"
    assert line["pinned"] is False
    assert line["cost_cents"] == 705
    assert line["missing_price"] is False

    assert cost_data["ingredients_cost_cents"] == 705
    assert cost_data["extras_cost_cents"] == 0
    assert cost_data["batch_cost_cents"] == 705
    assert cost_data["cost_per_yield_unit"] == "705.000000"
    assert cost_data["complete"] is True


@pytest.mark.asyncio
async def test_costing_cup_with_custom_conversion(client: AsyncClient, auth_headers):
    # 2 tazas de harina con taza de 125 g a 2350 por 1000 g dan 588
    units_resp = await client.get("/api/v1/units/", headers=auth_headers)
    taza_unit = next(u for u in units_resp.json() if u["abbreviation"] == "tz")

    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Harina con taza",
            "base_unit": "g",
            "conversions": [
                {"unit_id": taza_unit["id"], "quantity_in_base": "125"}
            ],
        },
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

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

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta en tazas",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "2",
                    "unit_id": taza_unit["id"],
                }
            ],
        },
    )
    assert rec_resp.status_code == 201
    recipe_id = rec_resp.json()["id"]

    cost_resp = await client.get(
        f"/api/v1/recipes/{recipe_id}/cost",
        headers=auth_headers,
    )
    assert cost_resp.status_code == 200
    cost_data = cost_resp.json()

    line = cost_data["lines"][0]
    assert line["unit_name"] == taza_unit["name"]
    assert line["quantity_in_base"] == "250"
    assert line["cost_cents"] == 588
    assert cost_data["ingredients_cost_cents"] == 588
    assert cost_data["batch_cost_cents"] == 588


@pytest.mark.asyncio
async def test_costing_rounding_three_lines_fractional(client: AsyncClient, auth_headers):
    # Tres líneas de 0.4 centavos muestran 0 cada una y ingredients_cost_cents 1
    # 1 g de ingrediente a 400 centavos por 1000 g da exactamente 0.4 centavos por línea.
    ing_ids = []
    for i in range(3):
        ing_resp = await client.post(
            "/api/v1/ingredients/",
            headers=auth_headers,
            json={"name": f"Ingrediente Fracción {i}", "base_unit": "g"},
        )
        ing_id = ing_resp.json()["id"]
        ing_ids.append(ing_id)

        await client.post(
            "/api/v1/presentations/",
            headers=auth_headers,
            json={
                "ingredient_id": ing_id,
                "brand": "Genérica",
                "package_quantity": "1000",
                "price_cents": 400,
            },
        )

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta fraccional",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {"kind": "ingredient", "ref_id": ing_ids[0], "quantity": "1"},
                {"kind": "ingredient", "ref_id": ing_ids[1], "quantity": "1"},
                {"kind": "ingredient", "ref_id": ing_ids[2], "quantity": "1"},
            ],
        },
    )
    assert rec_resp.status_code == 201
    recipe_id = rec_resp.json()["id"]

    cost_resp = await client.get(
        f"/api/v1/recipes/{recipe_id}/cost",
        headers=auth_headers,
    )
    assert cost_resp.status_code == 200
    cost_data = cost_resp.json()

    # Cada línea muestra 0
    for line in cost_data["lines"]:
        assert line["cost_cents"] == 0

    # Pero la suma sin redondear (1.2 centavos) redondea a 1
    assert cost_data["ingredients_cost_cents"] == 1
    assert cost_data["batch_cost_cents"] == 1


@pytest.mark.asyncio
async def test_costing_pinned_vs_current_presentation(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Vainilla", "base_unit": "ml"},
    )
    ing_id = ing_resp.json()["id"]

    # Presentación 1: Barata (100 ml por 1000 centavos -> 10 centavos/ml)
    p1_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Marca Barata",
            "package_quantity": "100",
            "price_cents": 1000,
        },
    )
    p1_id = p1_resp.json()["id"]

    # Presentación 2: Cara (100 ml por 2000 centavos -> 20 centavos/ml)
    # Como se crea después con recorded_at posterior, p2 es la vigente
    p2_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Marca Cara",
            "package_quantity": "100",
            "price_cents": 2000,
        },
    )
    p2_id = p2_resp.json()["id"]

    # Receta 1: Sin fijar (usa la vigente: Marca Cara)
    rec_unpinned = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta sin fijar",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "10",
                }
            ],
        },
    )
    cost1_resp = await client.get(
        f"/api/v1/recipes/{rec_unpinned.json()['id']}/cost",
        headers=auth_headers,
    )
    cost1_data = cost1_resp.json()
    assert cost1_data["lines"][0]["presentation_id"] == p2_id
    assert cost1_data["lines"][0]["pinned"] is False
    assert cost1_data["lines"][0]["cost_cents"] == 200  # 10 ml * 20 = 200

    # Receta 2: Fijando la presentación 1 (Marca Barata)
    rec_pinned = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta fijada",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "10",
                    "pinned_presentation_id": p1_id,
                }
            ],
        },
    )
    cost2_resp = await client.get(
        f"/api/v1/recipes/{rec_pinned.json()['id']}/cost",
        headers=auth_headers,
    )
    cost2_data = cost2_resp.json()
    assert cost2_data["lines"][0]["presentation_id"] == p1_id
    assert cost2_data["lines"][0]["pinned"] is True
    assert cost2_data["lines"][0]["cost_cents"] == 100  # 10 ml * 10 = 100

    # Si se borra la presentación fijada, pasa a usar la vigente con pinned: false
    del_resp = await client.delete(f"/api/v1/presentations/{p1_id}", headers=auth_headers)
    # Nota: la regla de presentación dice que si está en uso en una receta activa da IN_USE!
    # Verifiquemos si da IN_USE según B2
    assert del_resp.status_code == 409
    assert del_resp.json()["code"] == "IN_USE"


@pytest.mark.asyncio
async def test_costing_extras_added_to_batch_cost(client: AsyncClient, auth_headers):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Zulka",
            "package_quantity": "1000",
            "price_cents": 3000,
        },
    )

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Galletas con empaque",
            "yield_quantity": "12",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "200",  # 200 g * 3 = 600 cents
                }
            ],
            "extra_costs": [
                {"name": "Caja", "cost_cents": 150},
                {"name": "Mano de obra", "cost_cents": 250},
            ],
        },
    )
    recipe_id = rec_resp.json()["id"]

    cost_resp = await client.get(
        f"/api/v1/recipes/{recipe_id}/cost",
        headers=auth_headers,
    )
    data = cost_resp.json()
    assert data["ingredients_cost_cents"] == 600
    assert data["extras_cost_cents"] == 400
    assert data["batch_cost_cents"] == 1000
    assert data["cost_per_yield_unit"] == str((Decimal("1000") / Decimal("12")).quantize(Decimal("0.000001")))


@pytest.mark.asyncio
async def test_costing_margin_recipe_vs_workspace(client: AsyncClient, auth_headers):
    # Workspace default margin es 30 por configuración
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Cacao", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Hershey",
            "package_quantity": "1000",
            "price_cents": 10000,
        },
    )

    # 1. Receta con margen explícito del 20%
    rec1 = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Trufas con margen explícito",
            "yield_quantity": "10",
            "yield_unit": "pz",
            "margin_percent": 20,
            "items": [
                {"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}  # Costo 1000 cents
            ],
        },
    )
    c1 = (await client.get(f"/api/v1/recipes/{rec1.json()['id']}/cost", headers=auth_headers)).json()
    assert c1["batch_cost_cents"] == 1000
    assert c1["margin_percent"] == 20
    assert c1["suggested_price_cents"] == 1200  # 1000 * 1.20 = 1200

    # 2. Receta sin margen explícito (usa el margen del workspace: 40%)
    rec2 = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Trufas con margen default",
            "yield_quantity": "10",
            "yield_unit": "pz",
            "items": [
                {"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}  # Costo 1000 cents
            ],
        },
    )
    c2 = (await client.get(f"/api/v1/recipes/{rec2.json()['id']}/cost", headers=auth_headers)).json()
    assert c2["batch_cost_cents"] == 1000
    assert c2["margin_percent"] == 40
    assert c2["suggested_price_cents"] == 1400  # 1000 * 1.40 = 1400


@pytest.mark.asyncio
async def test_costing_subrecipe_betun_example(client: AsyncClient, auth_headers):
    # betún que rinde 800 g y cuesta 4000, usar 200 g aporta 1000
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Mantequilla", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Gloria",
            "package_quantity": "1000",
            "price_cents": 4000,
        },
    )

    betun_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Betún de mantequilla",
            "yield_quantity": "800",
            "yield_unit": "g",
            "items": [
                {"kind": "ingredient", "ref_id": ing_id, "quantity": "1000"}  # cuesta 4000
            ],
        },
    )
    assert betun_resp.status_code == 201
    betun_id = betun_resp.json()["id"]

    pastel_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel de cumpleaños",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "recipe",
                    "ref_id": betun_id,
                    "quantity": "200",
                }
            ],
        },
    )
    assert pastel_resp.status_code == 201
    pastel_id = pastel_resp.json()["id"]

    cost_resp = await client.get(
        f"/api/v1/recipes/{pastel_id}/cost",
        headers=auth_headers,
    )
    assert cost_resp.status_code == 200
    cost_data = cost_resp.json()

    assert len(cost_data["lines"]) == 1
    sub_line = cost_data["lines"][0]
    assert sub_line["kind"] == "recipe"
    assert sub_line["ref_id"] == betun_id
    assert sub_line["ref_name"] == "Betún de mantequilla"
    assert sub_line["quantity"] == "200"
    assert sub_line["quantity_in_base"] == "200"
    assert sub_line["base_unit"] == "g"
    assert sub_line["cost_cents"] == 1000  # 200 * 4000 / 800 = 1000
    assert sub_line["missing_price"] is False
    assert cost_data["batch_cost_cents"] == 1000
    assert cost_data["complete"] is True


@pytest.mark.asyncio
async def test_costing_nested_subrecipes_and_missing_price_propagation(
    client: AsyncClient,
    auth_headers,
):
    # Nivel 3 (base): Bizcocho sin precio
    ing_sin_precio = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Polvo para hornear", "base_unit": "g"},
    )
    ing_id = ing_sin_precio.json()["id"]
    # No le creamos presentación ni precio

    bizcocho = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Bizcocho base",
            "yield_quantity": "500",
            "yield_unit": "g",
            "items": [
                {"kind": "ingredient", "ref_id": ing_id, "quantity": "10"}
            ],
        },
    )
    bizcocho_id = bizcocho.json()["id"]

    # Nivel 2: Capa que usa Bizcocho
    capa = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Capa armada",
            "yield_quantity": "500",
            "yield_unit": "g",
            "items": [
                {"kind": "recipe", "ref_id": bizcocho_id, "quantity": "500"}
            ],
        },
    )
    capa_id = capa.json()["id"]

    # Nivel 1 (raíz): Pastel de bodas que usa Capa
    pastel_boda = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel de bodas",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {"kind": "recipe", "ref_id": capa_id, "quantity": "500"}
            ],
        },
    )
    pastel_boda_id = pastel_boda.json()["id"]

    # Al consultar el costo de la raíz, debe propagarse missing_price
    cost_root = await client.get(
        f"/api/v1/recipes/{pastel_boda_id}/cost",
        headers=auth_headers,
    )
    assert cost_root.status_code == 200
    root_data = cost_root.json()
    assert root_data["complete"] is False
    assert root_data["lines"][0]["missing_price"] is True

    # Ahora agregamos una presentación con precio al ingrediente del nivel 3
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Royal",
            "package_quantity": "100",
            "price_cents": 250,
        },
    )

    cost_root_after = await client.get(
        f"/api/v1/recipes/{pastel_boda_id}/cost",
        headers=auth_headers,
    )
    assert cost_root_after.status_code == 200
    root_after_data = cost_root_after.json()
    assert root_after_data["complete"] is True
    assert root_after_data["lines"][0]["missing_price"] is False
    assert root_after_data["batch_cost_cents"] == 25  # 10 g * 250 / 100 = 25


@pytest.mark.asyncio
async def test_costing_presentation_label_with_supplier_and_servings(
    client: AsyncClient,
    auth_headers,
):
    supp_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Costco"},
    )
    supp_id = supp_resp.json()["id"]

    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Nuez picada", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Kirkland",
            "supplier_id": supp_id,
            "package_quantity": "1360",
            "price_cents": 27200,
        },
    )

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pay de Nuez",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "servings": 8,
            "items": [
                {"kind": "ingredient", "ref_id": ing_id, "quantity": "200"}
            ],
        },
    )
    recipe_id = rec_resp.json()["id"]

    cost_resp = await client.get(
        f"/api/v1/recipes/{recipe_id}/cost",
        headers=auth_headers,
    )
    assert cost_resp.status_code == 200
    data = cost_resp.json()
    assert data["lines"][0]["presentation_label"] == "Kirkland · Costco · 1360 g"

    # 200 g * 27200 / 1360 = 4000 cents
    assert data["batch_cost_cents"] == 4000
    assert data["cost_per_serving_cents"] == round_to_cents(Decimal("4000") / Decimal("8"))
    assert data["cost_per_serving_cents"] == 500


@pytest.mark.asyncio
async def test_costing_pinned_presentation_without_price(client: AsyncClient, auth_headers):
    # Una presentación fijada y activa sin precio deja la línea con pinned: true,
    # missing_price: true y costo 0, sin usar la presentación vigente con precio.
    ing = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Chocolate Semiamargo", "base_unit": "g"},
    )).json()
    ing_id = ing["id"]

    # Presentación 1: La que elige fijar la usuaria (sin precio registrado aún)
    pres_fijada = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Marca Elegida",
            "package_quantity": "1000",
        },
    )).json()
    pres_fijada_id = pres_fijada["id"]

    # Presentación 2: Otra marca con precio (que sería la vigente si no estuviera fijada)
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Marca Vigente Con Precio",
            "package_quantity": "1000",
            "price_cents": 5000,
        },
    )

    # Crear receta fijando la presentación 1 (sin precio)
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel de Chocolate",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "200",
                    "pinned_presentation_id": pres_fijada_id,
                }
            ],
        },
    )).json()
    rec_id = rec["id"]

    cost_resp = await client.get(f"/api/v1/recipes/{rec_id}/cost", headers=auth_headers)
    assert cost_resp.status_code == 200
    data = cost_resp.json()

    line = data["lines"][0]
    assert line["presentation_id"] == pres_fijada_id
    assert line["presentation_label"] == "Marca Elegida · 1000 g"
    assert line["pinned"] is True
    assert line["missing_price"] is True
    assert line["cost_cents"] == 0
    assert data["complete"] is False


@pytest.mark.asyncio
async def test_costing_cycle_in_database_does_not_500(client: AsyncClient, auth_headers):
    # Un ciclo insertado directamente en la base (A usa B y B usa A con Recipe)
    # responde 200 con complete=false gracias a la defensa de profundidad, no 500.
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    rec_a = Recipe(
        workspace_id=ws_id,
        name="Receta Ciclo Corrupto A",
        yield_quantity="100",
        yield_unit=BaseUnit.g,
        items=[],
    )
    await rec_a.insert()

    rec_b = Recipe(
        workspace_id=ws_id,
        name="Receta Ciclo Corrupto B",
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

    cost_resp = await client.get(
        f"/api/v1/recipes/{rec_a.id}/cost",
        headers=auth_headers,
    )
    assert cost_resp.status_code == 200
    data = cost_resp.json()
    assert data["complete"] is False
    assert len(data["lines"]) == 1
    assert data["lines"][0]["missing_price"] is True

