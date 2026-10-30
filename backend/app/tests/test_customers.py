import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_crud_customer(client: AsyncClient, auth_headers):
    # 1. Create with spaces in name and phone
    resp = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "  Carlos Santillana  ", "phone": "  555-123-4567  ", "notes": "Cliente frecuente"},
    )
    assert resp.status_code == 201
    created = resp.json()
    assert created["name"] == "Carlos Santillana"
    assert created["phone"] == "555-123-4567"
    assert created["notes"] == "Cliente frecuente"
    assert "id" in created
    assert "created_at" in created
    assert "updated_at" in created
    cust_id = created["id"]

    # 2. Get by ID
    get_resp = await client.get(f"/api/v1/customers/{cust_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == cust_id
    assert get_resp.json()["name"] == "Carlos Santillana"

    # 3. Patch
    patch_resp = await client.patch(
        f"/api/v1/customers/{cust_id}",
        headers=auth_headers,
        json={"name": "Carlos S.", "phone": ""},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["name"] == "Carlos S."
    assert patch_resp.json()["phone"] is None

    # 4. List sorted by name
    await client.post("/api/v1/customers/", headers=auth_headers, json={"name": "Ana Bertha"})
    await client.post("/api/v1/customers/", headers=auth_headers, json={"name": "Zacarías"})

    list_resp = await client.get("/api/v1/customers/", headers=auth_headers)
    assert list_resp.status_code == 200
    items = list_resp.json()
    names = [c["name"] for c in items]
    assert names == ["Ana Bertha", "Carlos S.", "Zacarías"]

    # 5. Delete
    del_resp = await client.delete(f"/api/v1/customers/{cust_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    # 6. Verify deleted returns 404 NOT_FOUND
    get_again = await client.get(f"/api/v1/customers/{cust_id}", headers=auth_headers)
    assert get_again.status_code == 404
    assert get_again.json()["code"] == "NOT_FOUND"
    assert get_again.json()["detail"] == "Cliente no encontrado"

    # 7. Invalid id returns 404 NOT_FOUND
    invalid_resp = await client.get("/api/v1/customers/invalid_id", headers=auth_headers)
    assert invalid_resp.status_code == 404
    assert invalid_resp.json()["code"] == "NOT_FOUND"
    assert invalid_resp.json()["detail"] == "Cliente no encontrado"


@pytest.mark.asyncio
async def test_customer_duplicate_name_create_and_rename(client: AsyncClient, auth_headers):
    # Create customer 1
    resp1 = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Don Pedro"},
    )
    assert resp1.status_code == 201

    # Duplicate create (case-insensitive and trimmed)
    resp2 = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "  don pedro  "},
    )
    assert resp2.status_code == 409
    assert resp2.json()["code"] == "DUPLICATE_NAME"
    assert resp2.json()["detail"] == "Ya existe un cliente con ese nombre"

    # Create customer 2
    resp3 = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Doña María"},
    )
    assert resp3.status_code == 201
    c2_id = resp3.json()["id"]

    # Rename customer 2 to existing customer 1 name
    rename_resp = await client.patch(
        f"/api/v1/customers/{c2_id}",
        headers=auth_headers,
        json={"name": "DON PEDRO"},
    )
    assert rename_resp.status_code == 409
    assert rename_resp.json()["code"] == "DUPLICATE_NAME"
    assert rename_resp.json()["detail"] == "Ya existe un cliente con ese nombre"

    # Rename customer 2 to same name should succeed
    same_resp = await client.patch(
        f"/api/v1/customers/{c2_id}",
        headers=auth_headers,
        json={"name": "doña maría"},
    )
    assert same_resp.status_code == 200
    assert same_resp.json()["name"] == "doña maría"


@pytest.mark.asyncio
async def test_search_customers_by_name_and_phone(client: AsyncClient, auth_headers):
    await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Carlos Mendoza", "phone": "5551234567"},
    )
    await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Ana Torres", "phone": "5559876543"},
    )
    await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Roberto Gómez", "phone": "3331112233"},
    )

    # Search by name substring case-insensitive
    resp_name = await client.get("/api/v1/customers/?q=carlos", headers=auth_headers)
    assert resp_name.status_code == 200
    names = [c["name"] for c in resp_name.json()]
    assert names == ["Carlos Mendoza"]

    # Search by upper-case substring
    resp_upper = await client.get("/api/v1/customers/?q=TORRES", headers=auth_headers)
    assert resp_upper.status_code == 200
    names = [c["name"] for c in resp_upper.json()]
    assert names == ["Ana Torres"]

    # Search by phone substring
    resp_phone = await client.get("/api/v1/customers/?q=987", headers=auth_headers)
    assert resp_phone.status_code == 200
    names = [c["name"] for c in resp_phone.json()]
    assert names == ["Ana Torres"]

    # Search by phone matching multiple
    resp_phone_multi = await client.get("/api/v1/customers/?q=555", headers=auth_headers)
    assert resp_phone_multi.status_code == 200
    names = [c["name"] for c in resp_phone_multi.json()]
    assert names == ["Ana Torres", "Carlos Mendoza"]

    # Search with no match
    resp_none = await client.get("/api/v1/customers/?q=inexistente", headers=auth_headers)
    assert resp_none.status_code == 200
    assert resp_none.json() == []


@pytest.mark.asyncio
async def test_update_customer_name_and_phone_updates_active_orders(client: AsyncClient, auth_headers):
    # Create customer
    cust_resp = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Sofía Ruiz", "phone": "5551111"},
    )
    cust_id = cust_resp.json()["id"]

    # Create recipe for order
    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Gelatina", "yield_quantity": "1", "yield_unit": "pz"},
    )
    rec_id = rec_resp.json()["id"]

    # Create order linked to customer
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": cust_id,
            "delivery_at": "2026-11-05T12:00:00Z",
            "items": [{"recipe_id": rec_id, "quantity": "1", "unit_price_cents": 500}],
        },
    )
    order_id = order_resp.json()["id"]

    # Also create an order that was soft-deleted to verify it's not touched
    deleted_order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": cust_id,
            "delivery_at": "2026-11-06T12:00:00Z",
            "items": [{"recipe_id": rec_id, "quantity": "1", "unit_price_cents": 500}],
        },
    )
    deleted_order_id = deleted_order_resp.json()["id"]
    await client.delete(f"/api/v1/orders/{deleted_order_id}", headers=auth_headers)

    # Patch customer name and phone
    patch_cust = await client.patch(
        f"/api/v1/customers/{cust_id}",
        headers=auth_headers,
        json={"name": "Sofía Ruiz de Velasco", "phone": "5559999"},
    )
    assert patch_cust.status_code == 200

    # Retrieve order and verify customer_name and customer_phone changed
    get_ord = await client.get(f"/api/v1/orders/{order_id}", headers=auth_headers)
    assert get_ord.status_code == 200
    ord_data = get_ord.json()
    assert ord_data["customer_name"] == "Sofía Ruiz de Velasco"
    assert ord_data["customer_phone"] == "5559999"
    assert ord_data["customer_id"] == cust_id


@pytest.mark.asyncio
async def test_delete_customer_unlinks_orders_preserves_name_and_phone(client: AsyncClient, auth_headers):
    # Create customer
    cust_resp = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Marcos Valdés", "phone": "5557777"},
    )
    cust_id = cust_resp.json()["id"]

    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Flan Casero", "yield_quantity": "1", "yield_unit": "pz"},
    )
    rec_id = rec_resp.json()["id"]

    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": cust_id,
            "delivery_at": "2026-11-05T12:00:00Z",
            "items": [{"recipe_id": rec_id, "quantity": "1", "unit_price_cents": 300}],
        },
    )
    order_id = order_resp.json()["id"]

    # Delete customer
    del_resp = await client.delete(f"/api/v1/customers/{cust_id}", headers=auth_headers)
    assert del_resp.status_code == 204

    # Order still has name and phone, but customer_id is None
    get_ord = await client.get(f"/api/v1/orders/{order_id}", headers=auth_headers)
    assert get_ord.status_code == 200
    ord_data = get_ord.json()
    assert ord_data["customer_id"] is None
    assert ord_data["customer_name"] == "Marcos Valdés"
    assert ord_data["customer_phone"] == "5557777"


@pytest.mark.asyncio
async def test_customer_isolation_between_workspaces(client: AsyncClient, auth_headers, auth_headers_user_2):
    # User 1 creates customer
    resp = await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Cliente Privado", "phone": "1234567890"},
    )
    assert resp.status_code == 201
    cust_id = resp.json()["id"]

    # User 2 list -> does not see it
    list2 = await client.get("/api/v1/customers/", headers=auth_headers_user_2)
    assert list2.status_code == 200
    assert not any(c["id"] == cust_id for c in list2.json())

    # User 2 get -> 404 NOT_FOUND
    get2 = await client.get(f"/api/v1/customers/{cust_id}", headers=auth_headers_user_2)
    assert get2.status_code == 404
    assert get2.json()["code"] == "NOT_FOUND"
    assert get2.json()["detail"] == "Cliente no encontrado"

    # User 2 patch -> 404 NOT_FOUND
    patch2 = await client.patch(
        f"/api/v1/customers/{cust_id}",
        headers=auth_headers_user_2,
        json={"name": "Hack"},
    )
    assert patch2.status_code == 404
    assert patch2.json()["code"] == "NOT_FOUND"

    # User 2 delete -> 404 NOT_FOUND
    del2 = await client.delete(f"/api/v1/customers/{cust_id}", headers=auth_headers_user_2)
    assert del2.status_code == 404
    assert del2.json()["code"] == "NOT_FOUND"

    # User 2 cannot use customer_id in an order -> 422 INVALID_REFERENCE
    rec2_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers_user_2,
        json={"name": "Receta User 2", "yield_quantity": "1", "yield_unit": "pz"},
    )
    rec2_id = rec2_resp.json()["id"]

    ord_user2 = await client.post(
        "/api/v1/orders/",
        headers=auth_headers_user_2,
        json={
            "customer_id": cust_id,
            "delivery_at": "2026-11-05T12:00:00Z",
            "items": [{"recipe_id": rec2_id, "quantity": "1", "unit_price_cents": 100}],
        },
    )
    assert ord_user2.status_code == 422
    assert ord_user2.json()["code"] == "INVALID_REFERENCE"
