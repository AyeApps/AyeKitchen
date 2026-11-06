import hashlib
import json

import pytest
from httpx import AsyncClient

from app.models.backup import Backup
from app.models.cost_version import CostVersion
from app.models.customer import Customer
from app.models.ingredient import Ingredient
from app.models.order import Expense, Order
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.reference_image import ReferenceImage
from app.models.supplier import Supplier
from app.models.unit import Unit
from app.models.user import User
from app.models.workspace import Workspace


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


async def _seed_user_data(client: AsyncClient, headers: dict) -> dict:
    """Crea recursos en las distintas colecciones para un usuario vía endpoints existentes."""
    # 1. Workspace info
    me_resp = await client.get("/api/v1/me/", headers=headers)
    assert me_resp.status_code == 200
    ws_id = me_resp.json()["workspace"]["id"]
    user_id = me_resp.json()["id"]

    # Modificar ajustes del workspace para verificar que vuelven a fábrica
    ws = await Workspace.get(ws_id)
    assert ws is not None
    ws.name = "Mi Cocina Personalizada"
    ws.default_margin_percent = 65
    ws.price_stale_days = 45
    await ws.save()

    # 2. Unidad propia
    unit_resp = await client.post(
        "/api/v1/units/",
        headers=headers,
        json={"name": "Caja 12", "abbreviation": "c12", "base_unit": "pz", "factor_to_base": "12"},
    )
    assert unit_resp.status_code == 201

    # 3. Ingrediente activo e ingrediente que será soft-deleted
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=headers,
        json={"name": "Harina Fuerza", "base_unit": "g"},
    )
    assert ing_resp.status_code == 201
    ing_id = ing_resp.json()["id"]

    ing_del_resp = await client.post(
        "/api/v1/ingredients/",
        headers=headers,
        json={"name": "Azúcar a borrar", "base_unit": "g"},
    )
    assert ing_del_resp.status_code == 201
    ing_del_id = ing_del_resp.json()["id"]
    del_resp = await client.delete(f"/api/v1/ingredients/{ing_del_id}", headers=headers)
    assert del_resp.status_code == 204

    # 4. Proveedor
    sup_resp = await client.post(
        "/api/v1/suppliers/",
        headers=headers,
        json={"name": "Costco Gourmet"},
    )
    assert sup_resp.status_code == 201
    sup_id = sup_resp.json()["id"]

    # 5. Presentación y registro de precio
    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Selecta Alta",
            "package_quantity": "1000",
            "price_cents": 2800,
            "supplier_id": sup_id,
        },
    )
    assert pres_resp.status_code == 201
    pres_id = pres_resp.json()["id"]

    # 6. Receta
    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=headers,
        json={
            "name": "Pan Rústico",
            "yield_quantity": "2",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "500"}],
        },
    )
    assert rec_resp.status_code == 201
    rec_id = rec_resp.json()["id"]

    # 7. Versión de costeo
    cv_resp = await client.post(
        f"/api/v1/recipes/{rec_id}/versions/",
        headers=headers,
        json={"name": "Versión Premium", "choices": [{"ingredient_id": ing_id, "presentation_id": pres_id}]},
    )
    assert cv_resp.status_code == 201

    # 8. Cliente
    cust_resp = await client.post(
        "/api/v1/customers/",
        headers=headers,
        json={"name": "Cliente Frecuente", "phone": "5551234567"},
    )
    assert cust_resp.status_code == 201
    cust_id = cust_resp.json()["id"]

    # 9. Pedido
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=headers,
        json={
            "customer_id": cust_id,
            "customer_name": "Cliente Frecuente",
            "delivery_at": "2026-12-01T15:00:00Z",
            "items": [{"recipe_id": rec_id, "unit_price_cents": 5000, "quantity": 2}],
        },
    )
    assert order_resp.status_code == 201

    # 10. Gasto
    exp_resp = await client.post(
        "/api/v1/expenses/",
        headers=headers,
        json={
            "description": "Gas para horno",
            "amount_cents": 45000,
            "spent_at": "2026-11-01T10:00:00Z",
            "supplier_id": sup_id,
        },
    )
    assert exp_resp.status_code == 201

    # 11. Respaldo
    backup_doc = {
        "schema_version": 1,
        "exported_at": "2026-11-06T12:00:00.000Z",
        "device_id": "device-test-1",
        "settings": {"name": "Mi Cocina"},
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
    backup_bytes = json.dumps(backup_doc).encode("utf-8")
    b_resp = await client.put(
        "/api/v1/backup/",
        headers={**headers, "Content-Type": "application/json"},
        content=backup_bytes,
    )
    assert b_resp.status_code == 201

    # 12. Imagen de referencia
    img_data = b"image-raw-content-test-123456"
    img_sha = _sha256(img_data)
    img_resp = await client.put(
        f"/api/v1/backup/references/ref-img-1?sha256={img_sha}",
        headers={**headers, "Content-Type": "image/jpeg"},
        content=img_data,
    )
    assert img_resp.status_code == 201

    return {"workspace_id": ws_id, "user_id": user_id}


@pytest.mark.asyncio
async def test_delete_my_data_erases_all_collections_and_resets_workspace(
    client: AsyncClient,
    auth_headers,
):
    ids = await _seed_user_data(client, auth_headers)
    ws_id = ids["workspace_id"]

    # Verificar que existen datos antes de borrar
    assert await Unit.find(Unit.workspace_id == ws_id).count() == 1
    assert await Ingredient.find(Ingredient.workspace_id == ws_id).count() == 2  # 1 activo + 1 soft-deleted
    assert await Supplier.find(Supplier.workspace_id == ws_id).count() == 1
    assert await Presentation.find(Presentation.workspace_id == ws_id).count() == 1
    assert await PriceRecord.find(PriceRecord.workspace_id == ws_id).count() == 1
    assert await Recipe.find(Recipe.workspace_id == ws_id).count() == 1
    assert await CostVersion.find(CostVersion.workspace_id == ws_id).count() == 1
    assert await Customer.find(Customer.workspace_id == ws_id).count() == 1
    assert await Order.find(Order.workspace_id == ws_id).count() == 1
    assert await Expense.find(Expense.workspace_id == ws_id).count() == 1
    assert await Backup.find(Backup.workspace_id == ws_id).count() == 1
    assert await ReferenceImage.find(ReferenceImage.workspace_id == ws_id).count() == 1

    # Ejecutar DELETE /me/data
    del_resp = await client.delete("/api/v1/me/data", headers=auth_headers)
    assert del_resp.status_code == 204
    assert del_resp.text == ""

    # Verificar que ninguna colección tiene documentos de ese workspace (físicamente borrados)
    assert await Unit.find(Unit.workspace_id == ws_id).count() == 0
    assert await Ingredient.find(Ingredient.workspace_id == ws_id).count() == 0
    assert await Supplier.find(Supplier.workspace_id == ws_id).count() == 0
    assert await Presentation.find(Presentation.workspace_id == ws_id).count() == 0
    assert await PriceRecord.find(PriceRecord.workspace_id == ws_id).count() == 0
    assert await Recipe.find(Recipe.workspace_id == ws_id).count() == 0
    assert await CostVersion.find(CostVersion.workspace_id == ws_id).count() == 0
    assert await Customer.find(Customer.workspace_id == ws_id).count() == 0
    assert await Order.find(Order.workspace_id == ws_id).count() == 0
    assert await Expense.find(Expense.workspace_id == ws_id).count() == 0
    assert await Backup.find(Backup.workspace_id == ws_id).count() == 0
    assert await ReferenceImage.find(ReferenceImage.workspace_id == ws_id).count() == 0

    # Unidades del sistema siguen intactas (workspace_id == None)
    system_units_count = await Unit.find(Unit.workspace_id == None).count()  # noqa: E711
    assert system_units_count == 12

    # GET /me/ responde 200 con los ajustes de fábrica
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    assert me_resp.status_code == 200
    ws_data = me_resp.json()["workspace"]
    assert ws_data["name"] == "Mi cocina"
    assert ws_data["currency"] == "MXN"
    assert ws_data["default_margin_percent"] == 40
    assert ws_data["price_stale_days"] == 90

    # GET /backup/ y GET /backup/references/ vienen vacíos
    b_list = await client.get("/api/v1/backup/", headers=auth_headers)
    assert b_list.status_code == 200
    assert b_list.json() == []

    ref_list = await client.get("/api/v1/backup/references/", headers=auth_headers)
    assert ref_list.status_code == 200
    assert ref_list.json() == []


@pytest.mark.asyncio
async def test_delete_my_data_idempotent(client: AsyncClient, auth_headers):
    # Sin datos o después de borrar, DELETE /me/data sigue respondiendo 204
    resp1 = await client.delete("/api/v1/me/data", headers=auth_headers)
    assert resp1.status_code == 204

    resp2 = await client.delete("/api/v1/me/data", headers=auth_headers)
    assert resp2.status_code == 204


@pytest.mark.asyncio
async def test_delete_my_data_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    ids1 = await _seed_user_data(client, auth_headers)
    ids2 = await _seed_user_data(client, auth_headers_user_2)

    # Usuario 1 borra sus datos
    resp = await client.delete("/api/v1/me/data", headers=auth_headers)
    assert resp.status_code == 204

    # Los datos de usuario 1 fueron borrados
    assert await Ingredient.find(Ingredient.workspace_id == ids1["workspace_id"]).count() == 0

    # Los datos de usuario 2 siguen intactos
    assert await Unit.find(Unit.workspace_id == ids2["workspace_id"]).count() == 1
    assert await Ingredient.find(Ingredient.workspace_id == ids2["workspace_id"]).count() == 2
    assert await Supplier.find(Supplier.workspace_id == ids2["workspace_id"]).count() == 1
    assert await Presentation.find(Presentation.workspace_id == ids2["workspace_id"]).count() == 1
    assert await PriceRecord.find(PriceRecord.workspace_id == ids2["workspace_id"]).count() == 1
    assert await Recipe.find(Recipe.workspace_id == ids2["workspace_id"]).count() == 1
    assert await CostVersion.find(CostVersion.workspace_id == ids2["workspace_id"]).count() == 1
    assert await Customer.find(Customer.workspace_id == ids2["workspace_id"]).count() == 1
    assert await Order.find(Order.workspace_id == ids2["workspace_id"]).count() == 1
    assert await Expense.find(Expense.workspace_id == ids2["workspace_id"]).count() == 1
    assert await Backup.find(Backup.workspace_id == ids2["workspace_id"]).count() == 1
    assert await ReferenceImage.find(ReferenceImage.workspace_id == ids2["workspace_id"]).count() == 1


@pytest.mark.asyncio
async def test_delete_account_removes_workspace_and_user_with_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    ids1 = await _seed_user_data(client, auth_headers)
    ids2 = await _seed_user_data(client, auth_headers_user_2)

    ws1_id = ids1["workspace_id"]
    u1_id = ids1["user_id"]
    ws2_id = ids2["workspace_id"]
    u2_id = ids2["user_id"]

    # Usuario 1 elimina su cuenta
    del_resp = await client.delete("/api/v1/me/", headers=auth_headers)
    assert del_resp.status_code == 204
    assert del_resp.text == ""

    # Workspace y User de usuario 1 ya no existen en Kitchen
    assert await Workspace.get(ws1_id) is None
    assert await User.get(u1_id) is None

    # Todos los datos de su workspace fueron eliminados
    assert await Ingredient.find(Ingredient.workspace_id == ws1_id).count() == 0
    assert await Backup.find(Backup.workspace_id == ws1_id).count() == 0
    assert await ReferenceImage.find(ReferenceImage.workspace_id == ws1_id).count() == 0

    # Usuario 2 y sus datos siguen totalmente intactos
    assert await Workspace.get(ws2_id) is not None
    assert await User.get(u2_id) is not None
    assert await Ingredient.find(Ingredient.workspace_id == ws2_id).count() == 2
    assert await Backup.find(Backup.workspace_id == ws2_id).count() == 1
    assert await ReferenceImage.find(ReferenceImage.workspace_id == ws2_id).count() == 1


@pytest.mark.asyncio
async def test_get_me_after_delete_account_auto_provisions_new_user_and_workspace(
    client: AsyncClient,
    auth_headers,
):
    ids = await _seed_user_data(client, auth_headers)
    ws_id = ids["workspace_id"]

    # Eliminar cuenta
    del_resp = await client.delete("/api/v1/me/", headers=auth_headers)
    assert del_resp.status_code == 204

    # NOTA: Según el diseño en deps.py (_get_auth_context), si un token válido de aye-auth
    # realiza una petición autenticada pero el User local no existe en MongoDB (porque fue
    # borrado físicamente), deps.py auto-aprovisiona de forma transparente un nuevo User
    # y un nuevo Workspace personal vacío con valores de fábrica. No se modifica deps.py.
    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    assert me_resp.status_code == 200
    new_data = me_resp.json()
    new_ws_id = new_data["workspace"]["id"]

    # Es un nuevo workspace distinto al anterior
    assert new_ws_id != ws_id
    assert new_data["workspace"]["name"] == "Mi cocina"
    assert new_data["workspace"]["currency"] == "MXN"
    assert new_data["workspace"]["default_margin_percent"] == 40
    assert new_data["workspace"]["price_stale_days"] == 90
