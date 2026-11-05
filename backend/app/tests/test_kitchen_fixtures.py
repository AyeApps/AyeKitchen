import json
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
from httpx import AsyncClient

from app.models.cost_version import CostVersion
from app.models.customer import Customer
from app.models.ingredient import Ingredient
from app.models.order import Expense, Order
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.supplier import Supplier
from app.models.unit import Unit
from app.models.workspace import Workspace


async def _clean_workspace(client: AsyncClient, auth_headers: dict) -> str:
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    for model in [
        Unit,
        Ingredient,
        Supplier,
        Presentation,
        PriceRecord,
        Recipe,
        CostVersion,
        Customer,
        Order,
        Expense,
    ]:
        await model.find(model.workspace_id == ws_id).delete()

    ws = await Workspace.get(ws_id)
    if ws:
        ws.name = "Mi cocina"
        ws.currency = "MXN"
        ws.timezone = "America/Mexico_City"
        ws.default_margin_percent = 40
        ws.price_stale_days = 90
        await ws.save()

    return ws_id


async def _record_case(name: str, client: AsyncClient, auth_headers: dict) -> dict:
    now_iso = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

    export_resp = await client.get("/api/v1/backup/export-current", headers=auth_headers)
    assert export_resp.status_code == 200
    data = export_resp.json()

    recipes_resp = await client.get("/api/v1/recipes/?limit=100", headers=auth_headers)
    assert recipes_resp.status_code == 200
    recipes = recipes_resp.json()["items"]

    recipe_costs = []
    for rec in recipes:
        rec_id = rec["id"]
        cost_resp = await client.get(f"/api/v1/recipes/{rec_id}/cost", headers=auth_headers)
        assert cost_resp.status_code == 200
        recipe_costs.append({
            "recipe_id": rec_id,
            "version_id": None,
            "expected": cost_resp.json(),
        })

        versions_resp = await client.get(
            f"/api/v1/recipes/{rec_id}/versions/",
            headers=auth_headers,
        )
        assert versions_resp.status_code == 200
        versions = versions_resp.json()
        for ver in versions:
            ver_id = ver["id"]
            cost_ver_resp = await client.get(
                f"/api/v1/recipes/{rec_id}/cost?version_id={ver_id}",
                headers=auth_headers,
            )
            assert cost_ver_resp.status_code == 200
            recipe_costs.append({
                "recipe_id": rec_id,
                "version_id": ver_id,
                "expected": cost_ver_resp.json(),
            })

    return {
        "name": name,
        "now": now_iso,
        "data": data,
        "recipe_costs": recipe_costs,
    }


@pytest.mark.asyncio
async def test_kitchen_fixtures_generation(client: AsyncClient, auth_headers):
    generated_at = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    cases = []

    # -------------------------------------------------------------
    # (a) El ejemplo del contrato (harina 1000 g a $23.50, línea de 300 g -> 705)
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    ing_a = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina de trigo", "base_unit": "g"},
    )).json()

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_a["id"],
            "brand": "Selecta",
            "package_quantity": "1000",
            "price_cents": 2350,
        },
    )

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Simple Harina",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_a["id"], "quantity": "300"}],
        },
    )

    cases.append(await _record_case("a_contrato_harina", client, auth_headers))

    # -------------------------------------------------------------
    # (b) Conversión con equivalencia propia (taza = 125 g) y tabla general (taza de leche = 240 ml), más unidad del negocio
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    # Unidad del negocio: puñado (pnd = 50 g)
    pnd_unit = (await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={"name": "Puñado", "abbreviation": "pnd", "base_unit": "g", "factor_to_base": "50"},
    )).json()

    all_units = (await client.get("/api/v1/units/", headers=auth_headers)).json()
    tz_sys_unit = next(u for u in all_units if u["abbreviation"] == "tz")

    # Ingrediente 1: Harina con taza propia (125 g)
    ing_b1 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Harina con Taza Propia",
            "base_unit": "g",
            "conversions": [{"unit_id": tz_sys_unit["id"], "quantity_in_base": "125"}],
        },
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_b1["id"], "brand": "Selecta", "package_quantity": "1000", "price_cents": 2000},
    )

    # Ingrediente 2: Leche con tabla general (taza = 240 ml)
    ing_b2 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Leche Entera", "base_unit": "ml"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_b2["id"], "brand": "Lala", "package_quantity": "1000", "price_cents": 2500},
    )

    # Ingrediente 3: Nuez con unidad del negocio
    ing_b3 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Nuez en Mitades", "base_unit": "g"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_b3["id"], "brand": "Nuez de Campo", "package_quantity": "500", "price_cents": 10000},
    )

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pan Dulce con Nuez",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {"kind": "ingredient", "ref_id": ing_b1["id"], "quantity": "2", "unit_id": tz_sys_unit["id"]},
                {"kind": "ingredient", "ref_id": ing_b2["id"], "quantity": "1", "unit_id": tz_sys_unit["id"]},
                {"kind": "ingredient", "ref_id": ing_b3["id"], "quantity": "2", "unit_id": pnd_unit["id"]},
            ],
        },
    )

    cases.append(await _record_case("b_conversiones_unidades", client, auth_headers))

    # -------------------------------------------------------------
    # (c) Marca fijada, fijada sin precio, fijada borrada, y empate de fecha entre dos marcas
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    # 1. Marca fijada activa
    ing_c1 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Vainilla", "base_unit": "ml"},
    )).json()
    pres_c1_fijada = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c1["id"], "brand": "Papantla", "package_quantity": "100", "price_cents": 1500},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c1["id"], "brand": "Molina Vigente", "package_quantity": "100", "price_cents": 1000},
    )
    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta con Vainilla Fijada",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{
                "kind": "ingredient",
                "ref_id": ing_c1["id"],
                "quantity": "10",
                "pinned_presentation_id": pres_c1_fijada["id"],
            }],
        },
    )

    # 2. Marca fijada sin precio
    ing_c2 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Cocoa", "base_unit": "g"},
    )).json()
    pres_c2_sin_precio = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c2["id"], "brand": "Cocoa Gourmet Sin Precio", "package_quantity": "500"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c2["id"], "brand": "Cocoa Regular", "package_quantity": "500", "price_cents": 3000},
    )
    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Cocoa Sin Precio",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{
                "kind": "ingredient",
                "ref_id": ing_c2["id"],
                "quantity": "50",
                "pinned_presentation_id": pres_c2_sin_precio["id"],
            }],
        },
    )

    # 3. Marca fijada que luego se borra (directo en BD)
    ing_c3 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Canela", "base_unit": "g"},
    )).json()
    pres_c3_borrada = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c3["id"], "brand": "Canela Vieja", "package_quantity": "100", "price_cents": 800},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c3["id"], "brand": "Canela Vigente", "package_quantity": "100", "price_cents": 1200},
    )
    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta con Canela Fijada Borrada",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{
                "kind": "ingredient",
                "ref_id": ing_c3["id"],
                "quantity": "10",
                "pinned_presentation_id": pres_c3_borrada["id"],
            }],
        },
    )
    pres_c3_doc = await Presentation.get(pres_c3_borrada["id"])
    assert pres_c3_doc is not None
    await pres_c3_doc.soft_delete()

    # 4. Empate de fecha entre dos marcas
    ing_c4 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Azúcar Empate", "base_unit": "g"},
    )).json()

    t_same = datetime.now(UTC) - timedelta(days=1)
    # Marca 1 creada antes
    pres_c4_1 = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c4["id"], "brand": "Zulka Antigua", "package_quantity": "1000"},
    )).json()
    await client.post(
        f"/api/v1/presentations/{pres_c4_1['id']}/prices",
        headers=auth_headers,
        json={"price_cents": 2500, "recorded_at": t_same.isoformat()},
    )

    # Marca 2 creada después (gana por created_at)
    pres_c4_2 = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_c4["id"], "brand": "Morena Reciente", "package_quantity": "1000"},
    )).json()
    await client.post(
        f"/api/v1/presentations/{pres_c4_2['id']}/prices",
        headers=auth_headers,
        json={"price_cents": 3500, "recorded_at": t_same.isoformat()},
    )

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Azúcar Empate",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_c4["id"], "quantity": "100"}],
        },
    )

    cases.append(await _record_case("c_marca_fijada_estados_y_empate", client, auth_headers))

    # -------------------------------------------------------------
    # (d) Versión que elige otra marca y versión con marca sin precio
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    ing_d = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Mantequilla Versiones", "base_unit": "g"},
    )).json()

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_d["id"], "brand": "Gloria Base", "package_quantity": "1000", "price_cents": 4000},
    )

    pres_d2 = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_d["id"], "brand": "Lala Versión", "package_quantity": "1000", "price_cents": 5000},
    )).json()

    pres_d3 = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_d["id"], "brand": "Artesanal Sin Precio", "package_quantity": "1000"},
    )).json()

    rec_d = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Galletas de Mantequilla",
            "yield_quantity": "10",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_d["id"], "quantity": "200"}],
        },
    )).json()

    # Versión 1: Con Lala
    await client.post(
        f"/api/v1/recipes/{rec_d['id']}/versions/",
        headers=auth_headers,
        json={"name": "Con Lala", "choices": [{"ingredient_id": ing_d["id"], "presentation_id": pres_d2["id"]}]},
    )

    # Versión 2: Con Artesanal Sin Precio
    await client.post(
        f"/api/v1/recipes/{rec_d['id']}/versions/",
        headers=auth_headers,
        json={"name": "Con Artesanal", "choices": [{"ingredient_id": ing_d["id"], "presentation_id": pres_d3["id"]}]},
    )

    cases.append(await _record_case("d_versiones_costeo", client, auth_headers))

    # -------------------------------------------------------------
    # (e) Subreceta con unidad distinta (kg dentro de una receta que rinde g) y una receta que la usa
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    all_units = (await client.get("/api/v1/units/", headers=auth_headers)).json()
    kg_sys_unit = next(u for u in all_units if u["abbreviation"] == "kg")

    ing_e = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Queso Crema", "base_unit": "g"},
    )).json()

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_e["id"], "brand": "Philadelphia", "package_quantity": "1000", "price_cents": 8000},
    )

    sub_e = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Betún de Queso",
            "yield_quantity": "500",
            "yield_unit": "g",
            "items": [{"kind": "ingredient", "ref_id": ing_e["id"], "quantity": "500"}],
        },
    )).json()

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel de Tres Pisos",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "recipe",
                    "ref_id": sub_e["id"],
                    "quantity": "1.5",
                    "unit_id": kg_sys_unit["id"],
                }
            ],
        },
    )

    cases.append(await _record_case("e_subreceta_unidad_distinta", client, auth_headers))

    # -------------------------------------------------------------
    # (f) Extras, porciones, margen de la receta y margen del negocio
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    ing_f = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Chocolate Amargo", "base_unit": "g"},
    )).json()

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_f["id"], "brand": "Turin", "package_quantity": "1000", "price_cents": 10000},
    )

    # Receta 1: Con margen de receta explícito (25%), extras y 5 porciones
    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Trufas Gourmet",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "servings": 5,
            "margin_percent": 25,
            "items": [{"kind": "ingredient", "ref_id": ing_f["id"], "quantity": "100"}],
            "extra_costs": [
                {"name": "Caja Dorada", "cost_cents": 200},
                {"name": "Lazo", "cost_cents": 50},
            ],
        },
    )

    # Receta 2: Sin margen explícito (usa default del workspace = 40%), sin extras y 4 porciones
    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Chocolate Workspace Margin",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "servings": 4,
            "items": [{"kind": "ingredient", "ref_id": ing_f["id"], "quantity": "200"}],
        },
    )

    cases.append(await _record_case("f_extras_porciones_margenes", client, auth_headers))

    # -------------------------------------------------------------
    # (g) Un precio viejo (más de price_stale_days) y uno reciente
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    tz = ZoneInfo("America/Mexico_City")
    now_local = datetime.now(UTC).astimezone(tz)
    t_stale = (now_local - timedelta(days=95)).astimezone(UTC)

    ing_g1 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Fresa Silvestre", "base_unit": "g"},
    )).json()
    pres_g1 = (await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_g1["id"], "brand": "Campo Viejo", "package_quantity": "1000"},
    )).json()
    await client.post(
        f"/api/v1/presentations/{pres_g1['id']}/prices",
        headers=auth_headers,
        json={"price_cents": 6000, "recorded_at": t_stale.isoformat()},
    )

    ing_g2 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Crema Batida", "base_unit": "ml"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_g2["id"], "brand": "Alpura Fresca", "package_quantity": "1000", "price_cents": 4000},
    )

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Fresas con Crema Stale",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {"kind": "ingredient", "ref_id": ing_g1["id"], "quantity": "200"},
                {"kind": "ingredient", "ref_id": ing_g2["id"], "quantity": "100"},
            ],
        },
    )

    cases.append(await _record_case("g_precios_viejos_y_recientes", client, auth_headers))

    # -------------------------------------------------------------
    # (h) Una receta que rinde 12 pz (precio por pieza)
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    ing_h = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Masa de Galleta", "base_unit": "g"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_h["id"], "brand": "Masa Lista", "package_quantity": "1000", "price_cents": 2000},
    )

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Docena de Galletas",
            "yield_quantity": "12",
            "yield_unit": "pz",
            "margin_percent": 30,
            "items": [{"kind": "ingredient", "ref_id": ing_h["id"], "quantity": "500"}],
            "extra_costs": [{"name": "Caja", "cost_cents": 200}],
        },
    )

    cases.append(await _record_case("h_rendimiento_piezas", client, auth_headers))

    # -------------------------------------------------------------
    # (i) Redondeo: tres líneas de 0.4 centavos
    # -------------------------------------------------------------
    await _clean_workspace(client, auth_headers)

    ing_i1 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Ingrediente Subcentavo 1", "base_unit": "g"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_i1["id"], "brand": "Marca 1", "package_quantity": "1000", "price_cents": 4},
    )

    ing_i2 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Ingrediente Subcentavo 2", "base_unit": "g"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_i2["id"], "brand": "Marca 2", "package_quantity": "1000", "price_cents": 4},
    )

    ing_i3 = (await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Ingrediente Subcentavo 3", "base_unit": "g"},
    )).json()
    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={"ingredient_id": ing_i3["id"], "brand": "Marca 3", "package_quantity": "1000", "price_cents": 4},
    )

    await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Redondeo Subcentavo",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {"kind": "ingredient", "ref_id": ing_i1["id"], "quantity": "100"},
                {"kind": "ingredient", "ref_id": ing_i2["id"], "quantity": "100"},
                {"kind": "ingredient", "ref_id": ing_i3["id"], "quantity": "100"},
            ],
        },
    )

    cases.append(await _record_case("i_redondeo_subcentavos", client, auth_headers))

    # -------------------------------------------------------------
    # Archivo de salida (solo si KITCHEN_FIXTURES_OUT está configurado)
    # -------------------------------------------------------------
    fixtures_payload = {
        "generated_at": generated_at,
        "cases": cases,
    }

    fixtures_out = os.getenv("KITCHEN_FIXTURES_OUT")
    if fixtures_out:
        out_path = Path(fixtures_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(fixtures_payload, f, indent=2, ensure_ascii=False)
