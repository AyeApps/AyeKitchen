import json

import pytest
from httpx import AsyncClient

from app.models.backup import Backup


@pytest.mark.asyncio
async def test_backup_upload_and_download_roundtrip(client: AsyncClient, auth_headers):
    # JSON con formato del respaldo
    doc = {
        "schema_version": 1,
        "exported_at": "2026-11-05T12:00:00.000Z",
        "device_id": "iphone-alberto",
        "settings": {
            "name": "Mi pastelería",
            "currency": "MXN",
            "timezone": "America/Mexico_City",
            "default_margin_percent": 30,
            "price_stale_days": 30,
        },
        "units": [],
        "ingredients": [],
        "suppliers": [],
        "presentations": [],
        "price_records": [],
        "recipes": [],
        "cost_versions": [],
        "customers": [],
        "orders": [],
        "expenses": [],
    }
    raw_bytes = json.dumps(doc, indent=2).encode("utf-8")

    # Subir respaldo
    put_resp = await client.put(
        "/api/v1/backup/",
        headers={**auth_headers, "Content-Type": "application/json"},
        content=raw_bytes,
    )
    assert put_resp.status_code == 201
    info = put_resp.json()
    assert info["schema_version"] == 1
    assert info["device_id"] == "iphone-alberto"
    assert info["size_bytes"] == len(raw_bytes)
    backup_id = info["id"]

    # Bajar respaldo latest: debe devolver exactamente los mismos bytes
    get_resp = await client.get("/api/v1/backup/latest", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.headers["content-type"].startswith("application/json")
    assert get_resp.content == raw_bytes

    # Lista de respaldos
    list_resp = await client.get("/api/v1/backup/", headers=auth_headers)
    assert list_resp.status_code == 200
    items = list_resp.json()
    assert len(items) == 1
    assert items[0]["id"] == backup_id


@pytest.mark.asyncio
async def test_backup_pruning_keeps_only_5(client: AsyncClient, auth_headers):
    device_id = "iphone-prune"
    # Subir 7 respaldos con el mismo dispositivo
    for i in range(7):
        doc = {
            "schema_version": 1,
            "exported_at": f"2026-11-05T12:0{i}:00.000Z",
            "device_id": device_id,
            "settings": {"name": f"Respaldo {i}"},
        }
        resp = await client.put(
            "/api/v1/backup/",
            headers=auth_headers,
            content=json.dumps(doc).encode("utf-8"),
        )
        assert resp.status_code == 201

    # Verificar que solo se conservan 5 en la API y físicamente en la BD
    list_resp = await client.get("/api/v1/backup/", headers=auth_headers)
    assert list_resp.status_code == 200
    items = list_resp.json()
    assert len(items) == 5

    # Conteo en BD
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]
    db_count = await Backup.find(Backup.workspace_id == ws_id).count()
    assert db_count == 5


@pytest.mark.asyncio
async def test_backup_invalid_backup_validations(client: AsyncClient, auth_headers):
    # 1. Cuerpo no JSON
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=b"esto no es json",
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # 2. JSON que no es objeto (ej. lista)
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=b"[1, 2, 3]",
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # 3. schema_version faltante
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps({"device_id": "dev1", "exported_at": "2026-11-05T12:00:00Z"}).encode(),
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # 4. schema_version no entero o booleano
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps({
            "schema_version": True,
            "device_id": "dev1",
            "exported_at": "2026-11-05T12:00:00Z",
        }).encode(),
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # 5. schema_version mayor a 1
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps({
            "schema_version": 2,
            "device_id": "dev1",
            "exported_at": "2026-11-05T12:00:00Z",
        }).encode(),
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # 6. device_id vacío o ausente
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps({
            "schema_version": 1,
            "device_id": "   ",
            "exported_at": "2026-11-05T12:00:00Z",
        }).encode(),
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # 7. exported_at inválido
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps({
            "schema_version": 1,
            "device_id": "dev1",
            "exported_at": "fecha-no-valida",
        }).encode(),
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"


@pytest.mark.asyncio
async def test_backup_too_large(client: AsyncClient, auth_headers):
    # Más de 10 MB (10 * 1024 * 1024 + 10 bytes)
    big_data = b"x" * (10 * 1024 * 1024 + 10)
    resp = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=big_data,
    )
    assert resp.status_code == 413
    assert resp.json()["code"] == "BACKUP_TOO_LARGE"


@pytest.mark.asyncio
async def test_backup_conflict_rules(client: AsyncClient, auth_headers):
    # Dispositivo A sube el primer respaldo
    doc_a = {
        "schema_version": 1,
        "exported_at": "2026-11-05T10:00:00.000Z",
        "device_id": "device-A",
    }
    resp_a = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps(doc_a).encode(),
    )
    assert resp_a.status_code == 201

    # Dispositivo B intenta subir sin base_backup_id -> 409 BACKUP_CONFLICT
    doc_b = {
        "schema_version": 1,
        "exported_at": "2026-11-05T11:00:00.000Z",
        "device_id": "device-B",
    }
    resp_b_conflict = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps(doc_b).encode(),
    )
    assert resp_b_conflict.status_code == 409
    assert resp_b_conflict.json()["code"] == "BACKUP_CONFLICT"
    assert "2026-11-05" in resp_b_conflict.json()["detail"]

    # Dispositivo B intenta con base_backup_id incorrecto -> 409
    resp_b_wrong = await client.put(
        "/api/v1/backup/?base_backup_id=otro-id-inventado",
        headers=auth_headers,
        content=json.dumps(doc_b).encode(),
    )
    assert resp_b_wrong.status_code == 409
    assert resp_b_wrong.json()["code"] == "BACKUP_CONFLICT"

    # Dispositivo B sube con force=true -> 201 pasa
    resp_b_force = await client.put(
        "/api/v1/backup/?force=true",
        headers=auth_headers,
        content=json.dumps(doc_b).encode(),
    )
    assert resp_b_force.status_code == 201

    # Ahora el último respaldo es de B (id_b)
    # El mismo dispositivo B sube de nuevo -> pasa sin conflicto
    doc_b_2 = {
        "schema_version": 1,
        "exported_at": "2026-11-05T12:00:00.000Z",
        "device_id": "device-B",
    }
    resp_b_same = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps(doc_b_2).encode(),
    )
    assert resp_b_same.status_code == 201
    id_b_2 = resp_b_same.json()["id"]

    # Dispositivo A sube conociendo base_backup_id correcto (id_b_2) -> pasa
    doc_a_2 = {
        "schema_version": 1,
        "exported_at": "2026-11-05T13:00:00.000Z",
        "device_id": "device-A",
    }
    resp_a_ok = await client.put(
        f"/api/v1/backup/?base_backup_id={id_b_2}",
        headers=auth_headers,
        content=json.dumps(doc_a_2).encode(),
    )
    assert resp_a_ok.status_code == 201


@pytest.mark.asyncio
async def test_backup_latest_empty_404(client: AsyncClient, auth_headers):
    resp = await client.get("/api/v1/backup/latest", headers=auth_headers)
    assert resp.status_code == 404
    assert resp.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_backup_export_current(client: AsyncClient, auth_headers):
    # 1. Crear unidad del negocio
    unit_resp = await client.post(
        "/api/v1/units/",
        headers=auth_headers,
        json={
            "name": "Porción pequeña",
            "abbreviation": "porc",
            "base_unit": "g",
            "factor_to_base": "50",
        },
    )
    assert unit_resp.status_code == 201
    unit_id = unit_resp.json()["id"]

    # Obtener id de unidad del sistema "tz"
    all_units = (await client.get("/api/v1/units/", headers=auth_headers)).json()
    tz_sys_unit = next(u for u in all_units if u["abbreviation"] == "tz")

    # 2. Crear ingrediente con equivalencia a taza
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={
            "name": "Harina Blanca",
            "base_unit": "g",
            "conversions": [{"unit_id": tz_sys_unit["id"], "quantity_in_base": "125"}],
        },
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    # 3. Presentación
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

    # 4. Receta que usa taza (unidad sistema) y unidad del negocio
    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pan Dulce",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [
                {
                    "kind": "ingredient",
                    "ref_id": ing_id,
                    "quantity": "2",
                    "unit_id": tz_sys_unit["id"],
                }
            ],
        },
    )
    assert rec_resp.status_code == 201
    rec_id = rec_resp.json()["id"]

    # 5. Pedido con esa receta
    delivery_date = "2026-11-07T12:00:00Z"
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Ana García",
            "delivery_at": delivery_date,
            "items": [
                {
                    "recipe_id": rec_id,
                    "quantity": "3",
                }
            ],
        },
    )
    assert order_resp.status_code == 201

    # 6. Borrar la receta para verificar que recipe_name se conserva y borrados se exportan
    del_rec_resp = await client.delete(f"/api/v1/recipes/{rec_id}", headers=auth_headers)
    assert del_rec_resp.status_code == 204

    # 7. Llamar export-current
    export_resp = await client.get("/api/v1/backup/export-current", headers=auth_headers)
    assert export_resp.status_code == 200
    export_data = export_resp.json()

    assert export_data["schema_version"] == 1
    assert export_data["device_id"] == "server-export"
    assert export_data["settings"]["currency"] == "MXN"

    # Unidades: solo la del negocio, no las del sistema
    unit_ids = [u["id"] for u in export_data["units"]]
    assert unit_id in unit_ids
    assert not any(u["id"].startswith("sys.") for u in export_data["units"])

    # Conversión del ingrediente traducida a sys.tz
    exported_ing = next(i for i in export_data["ingredients"] if i["id"] == ing_id)
    assert exported_ing["conversions"][0]["unit_id"] == "sys.tz"
    assert exported_ing["conversions"][0]["quantity_in_base"] == "125"

    # Receta borrada incluida con deleted_at no nulo y unit_id traducido a sys.tz
    exported_rec = next(r for r in export_data["recipes"] if r["id"] == rec_id)
    assert exported_rec["deleted_at"] is not None
    assert exported_rec["items"][0]["unit_id"] == "sys.tz"

    # Pedido tiene recipe_name de la receta borrada
    exported_order = export_data["orders"][0]
    assert exported_order["items"][0]["recipe_name"] == "Pan Dulce"


@pytest.mark.asyncio
async def test_backup_isolation(client: AsyncClient, auth_headers, auth_headers_user_2):
    # User 1 sube un respaldo
    doc_1 = {
        "schema_version": 1,
        "exported_at": "2026-11-05T12:00:00.000Z",
        "device_id": "iphone-u1",
        "settings": {"name": "Cocina User 1"},
    }
    resp1 = await client.put(
        "/api/v1/backup/",
        headers=auth_headers,
        content=json.dumps(doc_1).encode(),
    )
    assert resp1.status_code == 201

    # User 2 consulta lista -> vacía
    list2 = await client.get("/api/v1/backup/", headers=auth_headers_user_2)
    assert list2.status_code == 200
    assert list2.json() == []

    # User 2 latest -> 404
    latest2 = await client.get("/api/v1/backup/latest", headers=auth_headers_user_2)
    assert latest2.status_code == 404
    assert latest2.json()["code"] == "NOT_FOUND"

    # User 2 export-current no ve entidades de User 1
    # Crear un ingrediente con User 1
    await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Ingrediente Privado U1", "base_unit": "g"},
    )
    export_u2 = (await client.get("/api/v1/backup/export-current", headers=auth_headers_user_2)).json()
    assert len(export_u2["ingredients"]) == 0

    # User 2 sube un respaldo -> no choca con el de User 1
    doc_2 = {
        "schema_version": 1,
        "exported_at": "2026-11-05T13:00:00.000Z",
        "device_id": "iphone-u2",
        "settings": {"name": "Cocina User 2"},
    }
    resp2 = await client.put(
        "/api/v1/backup/",
        headers=auth_headers_user_2,
        content=json.dumps(doc_2).encode(),
    )
    assert resp2.status_code == 201
