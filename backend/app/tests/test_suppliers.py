import pytest
from httpx import AsyncClient

from app.models.presentation import Presentation


@pytest.mark.asyncio
async def test_crud_supplier(client: AsyncClient, auth_headers):
    # 1. Create
    resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Walmart Supercenter", "notes": "Comprar lácteos aquí"},
    )
    assert resp.status_code == 201
    created = resp.json()
    assert created["name"] == "Walmart Supercenter"
    assert created["notes"] == "Comprar lácteos aquí"
    sup_id = created["id"]

    # 2. Get by ID
    get_resp = await client.get(f"/api/v1/suppliers/{sup_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == sup_id

    # 3. Patch
    patch_resp = await client.patch(
        f"/api/v1/suppliers/{sup_id}",
        headers=auth_headers,
        json={"name": "Walmart Express", "notes": "Sucursal cercana"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["name"] == "Walmart Express"
    assert patch_resp.json()["notes"] == "Sucursal cercana"

    # 4. List sorted by name
    await client.post("/api/v1/suppliers/", headers=auth_headers, json={"name": "Costco"})
    await client.post("/api/v1/suppliers/", headers=auth_headers, json={"name": "Central de Abastos"})

    list_resp = await client.get("/api/v1/suppliers/", headers=auth_headers)
    assert list_resp.status_code == 200
    names = [s["name"] for s in list_resp.json()]
    assert names == sorted(names)

    # 5. Delete
    del_resp = await client.delete(f"/api/v1/suppliers/{sup_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    # 6. Verify deleted
    get_again = await client.get(f"/api/v1/suppliers/{sup_id}", headers=auth_headers)
    assert get_again.status_code == 404
    assert get_again.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_supplier_duplicate_name(client: AsyncClient, auth_headers):
    resp1 = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "La Comer"},
    )
    assert resp1.status_code == 201

    resp2 = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "  la comer  "},
    )
    assert resp2.status_code == 409
    assert resp2.json()["code"] == "DUPLICATE_NAME"


@pytest.mark.asyncio
async def test_delete_supplier_sets_presentation_supplier_null(client: AsyncClient, auth_headers):
    # Create supplier
    sup_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Sams Club"},
    )
    sup_id = sup_resp.json()["id"]

    me_resp = await client.get("/api/v1/me/", headers=auth_headers)
    ws_id = me_resp.json()["workspace"]["id"]

    # Create presentation with this supplier_id
    pres = Presentation(
        workspace_id=ws_id,
        ingredient_id="dummy_ing",
        brand="Member's Mark",
        supplier_id=sup_id,
        package_quantity="2000",
    )
    await pres.insert()

    # Delete supplier
    del_resp = await client.delete(f"/api/v1/suppliers/{sup_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    # Reload presentation
    updated_pres = await Presentation.get(pres.id)
    assert updated_pres.supplier_id is None
    assert updated_pres.deleted_at is None


@pytest.mark.asyncio
async def test_supplier_isolation(client: AsyncClient, auth_headers, auth_headers_user_2):
    # User 1 creates supplier
    sup_resp = await client.post(
        "/api/v1/suppliers/",
        headers=auth_headers,
        json={"name": "Mercado Local"},
    )
    sup_id = sup_resp.json()["id"]

    # User 2 list should not contain it
    u2_list = await client.get("/api/v1/suppliers/", headers=auth_headers_user_2)
    assert not any(s["id"] == sup_id for s in u2_list.json())

    # User 2 GET -> 404
    u2_get = await client.get(f"/api/v1/suppliers/{sup_id}", headers=auth_headers_user_2)
    assert u2_get.status_code == 404
    assert u2_get.json()["code"] == "NOT_FOUND"

    # User 2 PATCH -> 404
    u2_patch = await client.patch(
        f"/api/v1/suppliers/{sup_id}",
        headers=auth_headers_user_2,
        json={"name": "Hacked"},
    )
    assert u2_patch.status_code == 404
    assert u2_patch.json()["code"] == "NOT_FOUND"

    # User 2 DELETE -> 404
    u2_del = await client.delete(f"/api/v1/suppliers/{sup_id}", headers=auth_headers_user_2)
    assert u2_del.status_code == 404
    assert u2_del.json()["code"] == "NOT_FOUND"
