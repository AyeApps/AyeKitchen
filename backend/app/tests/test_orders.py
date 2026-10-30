import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_create_order_without_price_takes_suggested_and_stores_snapshot(
    client: AsyncClient,
    auth_headers,
):
    # Harina 1000 g a $23.50 (2350 centavos)
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina Pedidos", "base_unit": "g"},
    )
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
    pres_id = pres_resp.json()["id"]

    # Receta con 300 g -> costo 705. Margen workspace default 40% -> suggested_price 705 * 1.40 = 987
    rec_resp = await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Vainilla Pedido",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "300"}],
        },
    )
    rec_id = rec_resp.json()["id"]

    # 1. Crear pedido sin unit_price_cents
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Ana Gómez",
            "customer_phone": "5551234567",
            "delivery_at": "2026-11-01T15:00:00Z",
            "items": [{"recipe_id": rec_id, "quantity": "2"}],
            "notes": "Sin nuez",
        },
    )
    assert order_resp.status_code == 201
    order_data = order_resp.json()
    order_id = order_data["id"]

    assert order_data["customer_name"] == "Ana Gómez"
    assert order_data["items"][0]["recipe_name"] == "Pastel Vainilla Pedido"
    assert order_data["items"][0]["unit_price_cents"] == 987
    assert order_data["items"][0]["unit_cost_cents_snapshot"] == 705

    # 2 tandas * 987 = 1974 total, 2 * 705 = 1410 costo, ganancia 564
    assert order_data["total_cents"] == 1974
    assert order_data["cost_cents"] == 1410
    assert order_data["profit_cents"] == 564
    assert order_data["paid_cents"] == 0
    assert order_data["balance_cents"] == 1974

    # 2. Cambiar después el precio del ingrediente NO cambia el cost_cents de este pedido
    await client.post(
        f"/api/v1/presentations/{pres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 5000},
    )

    get_order = await client.get(f"/api/v1/orders/{order_id}", headers=auth_headers)
    assert get_order.status_code == 200
    get_data = get_order.json()
    assert get_data["items"][0]["unit_cost_cents_snapshot"] == 705
    assert get_data["cost_cents"] == 1410
    assert get_data["total_cents"] == 1974


@pytest.mark.asyncio
async def test_patch_order_adds_new_line_preserves_existing_snapshot(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Mantequilla Pedidos", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "Gloria",
            "package_quantity": "1000",
            "price_cents": 4000,
        },
    )
    pres_id = pres_resp.json()["id"]

    rec1 = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Uno",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "100"}],  # costo 400
        },
    )).json()

    rec2 = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Receta Dos",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "200"}],  # costo 800
        },
    )).json()

    # Pedido original con solo Receta Uno
    order = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Carlos Pérez",
            "delivery_at": "2026-11-05T10:00:00Z",
            "items": [{"recipe_id": rec1["id"], "quantity": "1", "unit_price_cents": 1000}],
        },
    )).json()
    order_id = order["id"]
    assert order["items"][0]["unit_cost_cents_snapshot"] == 400

    # Subir el precio de la mantequilla
    await client.post(
        f"/api/v1/presentations/{pres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 8000},
    )

    # PATCH agregando Receta Dos: la línea de Receta Uno debe conservar snapshot 400, Receta Dos toma 1600
    patch_resp = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={
            "items": [
                {"recipe_id": rec1["id"], "quantity": "1", "unit_price_cents": 1000},
                {"recipe_id": rec2["id"], "quantity": "1", "unit_price_cents": 2500},
            ]
        },
    )
    assert patch_resp.status_code == 200
    patched_data = patch_resp.json()

    items_map = {it["recipe_id"]: it for it in patched_data["items"]}
    assert items_map[rec1["id"]]["unit_cost_cents_snapshot"] == 400
    assert items_map[rec2["id"]]["unit_cost_cents_snapshot"] == 1600


@pytest.mark.asyncio
async def test_order_payments_flow_and_exceeds_balance(
    client: AsyncClient,
    auth_headers,
):
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Huevo Pedidos", "base_unit": "pz"},
    )
    ing_id = ing_resp.json()["id"]

    await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "San Juan",
            "package_quantity": "12",
            "price_cents": 600,
        },
    )

    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Flan Casero",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "6"}],
        },
    )).json()

    order = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Laura",
            "delivery_at": "2026-11-10T12:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "2", "unit_price_cents": 1000}],  # total 2000
        },
    )).json()
    order_id = order["id"]
    assert order["total_cents"] == 2000
    assert order["balance_cents"] == 2000

    # 1. Pago parcial 1: 500
    p1 = (await client.post(
        f"/api/v1/orders/{order_id}/payments",
        headers=auth_headers,
        json={"amount_cents": 500, "method": "efectivo"},
    )).json()
    assert p1["paid_cents"] == 500
    assert p1["balance_cents"] == 1500
    p1_id = p1["payments"][0]["id"]

    # 2. Pago parcial 2: 1000
    p2 = (await client.post(
        f"/api/v1/orders/{order_id}/payments",
        headers=auth_headers,
        json={"amount_cents": 1000, "method": "transferencia"},
    )).json()
    assert p2["paid_cents"] == 1500
    assert p2["balance_cents"] == 500

    # 3. Intentar pagar más del saldo restante -> 422 PAYMENT_EXCEEDS_BALANCE
    p_exceeds = await client.post(
        f"/api/v1/orders/{order_id}/payments",
        headers=auth_headers,
        json={"amount_cents": 600},
    )
    assert p_exceeds.status_code == 422
    assert p_exceeds.json()["code"] == "PAYMENT_EXCEEDS_BALANCE"

    # 4. Borrar un pago
    del_p_resp = await client.delete(
        f"/api/v1/orders/{order_id}/payments/{p1_id}",
        headers=auth_headers,
    )
    assert del_p_resp.status_code == 200
    del_data = del_p_resp.json()
    assert del_data["paid_cents"] == 1000
    assert del_data["balance_cents"] == 1000
    assert len(del_data["payments"]) == 1

    # 5. Borrar pago inexistente -> 404
    del_fake = await client.delete(
        f"/api/v1/orders/{order_id}/payments/pago_inexistente",
        headers=auth_headers,
    )
    assert del_fake.status_code == 404
    assert del_fake.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_order_filters_status_from_to(client: AsyncClient, auth_headers):
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Gelatina", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # Pedido 1: pendiente, 2026-11-01
    await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Cliente Uno",
            "delivery_at": "2026-11-01T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 100}],
        },
    )

    # Pedido 2: entregado, 2026-11-05
    o2 = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Cliente Dos",
            "delivery_at": "2026-11-05T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 100}],
        },
    )).json()
    await client.patch(
        f"/api/v1/orders/{o2['id']}",
        headers=auth_headers,
        json={"status": "entregado"},
    )

    # Pedido 3: pendiente, 2026-11-15
    await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Cliente Tres",
            "delivery_at": "2026-11-15T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 100}],
        },
    )

    # Filtro status=entregado
    resp_status = await client.get("/api/v1/orders/?status=entregado", headers=auth_headers)
    assert resp_status.status_code == 200
    assert resp_status.json()["total"] == 1
    assert resp_status.json()["items"][0]["customer_name"] == "Cliente Dos"

    # Filtro from y to (2026-11-01 a 2026-11-10)
    resp_date = await client.get(
        "/api/v1/orders/?from=2026-11-01T00:00:00Z&to=2026-11-10T23:59:59Z",
        headers=auth_headers,
    )
    assert resp_date.status_code == 200
    assert resp_date.json()["total"] == 2
    names = [it["customer_name"] for it in resp_date.json()["items"]]
    assert "Cliente Uno" in names
    assert "Cliente Dos" in names
    assert "Cliente Tres" not in names


@pytest.mark.asyncio
async def test_order_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Receta User 1", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    order = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Cliente Privado",
            "delivery_at": "2026-11-01T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 500}],
        },
    )).json()
    order_id = order["id"]

    # Usuario 2 no puede leerlo (404)
    assert (await client.get(f"/api/v1/orders/{order_id}", headers=auth_headers_user_2)).status_code == 404

    # Usuario 2 no puede editarlo (404)
    assert (await client.patch(f"/api/v1/orders/{order_id}", headers=auth_headers_user_2, json={"customer_name": "Hacker"})).status_code == 404

    # Usuario 2 no puede agregar pago (404)
    assert (await client.post(f"/api/v1/orders/{order_id}/payments", headers=auth_headers_user_2, json={"amount_cents": 100})).status_code == 404

    # Usuario 2 no puede borrarlo (404)
    assert (await client.delete(f"/api/v1/orders/{order_id}", headers=auth_headers_user_2)).status_code == 404

    # Usuario 2 no lo ve en la lista
    list_u2 = (await client.get("/api/v1/orders/", headers=auth_headers_user_2)).json()
    assert order_id not in [it["id"] for it in list_u2["items"]]


@pytest.mark.asyncio
async def test_update_order_preserves_agreed_price_and_snapshot_for_existing_lines(
    client: AsyncClient,
    auth_headers,
):
    # Crear ingrediente y presentación con precio inicial
    ing_resp = await client.post(
        "/api/v1/ingredients/",
        headers=auth_headers,
        json={"name": "Harina Pastel 650", "base_unit": "g"},
    )
    ing_id = ing_resp.json()["id"]

    pres_resp = await client.post(
        "/api/v1/presentations/",
        headers=auth_headers,
        json={
            "ingredient_id": ing_id,
            "brand": "La Perla",
            "package_quantity": "1000",
            "price_cents": 2000,
        },
    )
    pres_id = pres_resp.json()["id"]

    # Receta 1: 500 g -> costo 1000
    rec1 = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Pastel Chocolate",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "500"}],
        },
    )).json()

    # Receta 2: 250 g
    rec2 = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={
            "name": "Galletas Mantequilla",
            "yield_quantity": "1",
            "yield_unit": "pz",
            "items": [{"kind": "ingredient", "ref_id": ing_id, "quantity": "250"}],
        },
    )).json()

    # Crear pedido acordado en 65000 centavos ($650)
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Valeria Castro",
            "delivery_at": "2026-11-20T16:00:00Z",
            "items": [
                {"recipe_id": rec1["id"], "quantity": "1", "unit_price_cents": 65000}
            ],
        },
    )
    assert order_resp.status_code == 201
    order_id = order_resp.json()["id"]
    assert order_resp.json()["items"][0]["unit_price_cents"] == 65000
    assert order_resp.json()["items"][0]["unit_cost_cents_snapshot"] == 1000
    assert order_resp.json()["cost_cents"] == 1000

    # Subir el precio del ingrediente (de 2000 a 4000)
    await client.post(
        f"/api/v1/presentations/{pres_id}/prices",
        headers=auth_headers,
        json={"price_cents": 4000},
    )

    # Editar pedido reenviando la misma línea sin precio y agregando una línea nueva
    # Receta 2 hoy cuesta: 250g de 4000/1000 = 1000 costo. Margen 40% -> suggested_price 1400.
    patch_resp = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={
            "items": [
                {"recipe_id": rec1["id"], "quantity": "1"},  # Misma línea sin precio
                {"recipe_id": rec2["id"], "quantity": "1"},  # Línea nueva sin precio
            ]
        },
    )
    assert patch_resp.status_code == 200
    patched_data = patch_resp.json()

    items_by_rec = {it["recipe_id"]: it for it in patched_data["items"]}
    line1 = items_by_rec[rec1["id"]]
    assert line1["unit_price_cents"] == 65000  # Conserva precio acordado anterior
    assert line1["unit_cost_cents_snapshot"] == 1000  # Conserva snapshot anterior

    line2 = items_by_rec[rec2["id"]]
    assert line2["unit_cost_cents_snapshot"] == 1000  # Snapshot nuevo de hoy
    assert line2["unit_price_cents"] == 1400  # Precio sugerido de hoy

    assert patched_data["total_cents"] == 65000 + 1400
    assert patched_data["cost_cents"] == 1000 + 1000


@pytest.mark.asyncio
async def test_order_cannot_reduce_total_below_paid_amount(
    client: AsyncClient,
    auth_headers,
):
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Gelatina", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # Pedido con total 65000
    order = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Mario López",
            "delivery_at": "2026-11-10T12:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 65000}],
        },
    )).json()
    order_id = order["id"]

    # Pago completo de 65000
    pay_resp = await client.post(
        f"/api/v1/orders/{order_id}/payments",
        headers=auth_headers,
        json={"amount_cents": 65000},
    )
    assert pay_resp.status_code == 201
    assert pay_resp.json()["paid_cents"] == 65000
    assert pay_resp.json()["balance_cents"] == 0

    # Intentar bajar la cantidad o el precio deja el total por debajo de lo pagado -> 422 PAYMENT_EXCEEDS_BALANCE
    patch_fail = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={
            "items": [
                {"recipe_id": rec["id"], "quantity": "0.5", "unit_price_cents": 65000}
            ]
        },
    )
    assert patch_fail.status_code == 422
    err_body = patch_fail.json()
    assert err_body["code"] == "PAYMENT_EXCEEDS_BALANCE"
    assert "El total quedaría por debajo de lo que ya te pagaron" in err_body["detail"]

    # El pedido no se modificó en base de datos
    get_resp = await client.get(f"/api/v1/orders/{order_id}", headers=auth_headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["items"][0]["quantity"] == "1"
    assert get_resp.json()["total_cents"] == 65000
    assert get_resp.json()["paid_cents"] == 65000


@pytest.mark.asyncio
async def test_order_items_cannot_be_empty(
    client: AsyncClient,
    auth_headers,
):
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Brownie", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # POST con items vacío -> 422 estándar de FastAPI
    post_empty = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Prueba Vacía",
            "delivery_at": "2026-11-10T12:00:00Z",
            "items": [],
        },
    )
    assert post_empty.status_code == 422

    # Crear pedido válido
    order = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Prueba Edición Vacía",
            "delivery_at": "2026-11-10T12:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 1000}],
        },
    )).json()
    order_id = order["id"]

    # PATCH con items vacío -> 422 estándar de FastAPI
    patch_empty = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={"items": []},
    )
    assert patch_empty.status_code == 422


@pytest.mark.asyncio
async def test_create_order_with_customer_id_copies_name_and_phone(
    client: AsyncClient,
    auth_headers,
):
    cust = (await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Laura Cruz", "phone": "5550000"},
    )).json()

    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Cheesecake", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # Creación con customer_id ignora customer_name y customer_phone enviados en el body
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": cust["id"],
            "customer_name": "Nombre Que Debe Ignorarse",
            "customer_phone": "9999999",
            "delivery_at": "2026-11-15T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 1500}],
        },
    )
    assert order_resp.status_code == 201
    order_data = order_resp.json()
    assert order_data["customer_id"] == cust["id"]
    assert order_data["customer_name"] == "Laura Cruz"
    assert order_data["customer_phone"] == "5550000"


@pytest.mark.asyncio
async def test_create_order_with_invalid_or_nonexistent_customer_id(
    client: AsyncClient,
    auth_headers,
):
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Muffin", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # ObjectId válido pero inexistente en workspace -> 422 INVALID_REFERENCE
    resp_nonexistent = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": "507f1f77bcf86cd799439011",
            "delivery_at": "2026-11-15T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 200}],
        },
    )
    assert resp_nonexistent.status_code == 422
    assert resp_nonexistent.json()["code"] == "INVALID_REFERENCE"

    # ID malformado -> 422 INVALID_REFERENCE
    resp_invalid = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": "bad-id",
            "delivery_at": "2026-11-15T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 200}],
        },
    )
    assert resp_invalid.status_code == 422
    assert resp_invalid.json()["code"] == "INVALID_REFERENCE"


@pytest.mark.asyncio
async def test_create_order_without_customer_or_name_fails_customer_required(
    client: AsyncClient,
    auth_headers,
):
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Panqué", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # Sin customer_id ni customer_name
    resp_none = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "delivery_at": "2026-11-15T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 200}],
        },
    )
    assert resp_none.status_code == 422
    assert resp_none.json()["code"] == "CUSTOMER_REQUIRED"
    assert resp_none.json()["detail"] == "Elige un cliente o escribe su nombre"

    # Con customer_name vacío o solo espacios
    resp_spaces = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "    ",
            "delivery_at": "2026-11-15T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 200}],
        },
    )
    assert resp_spaces.status_code == 422
    assert resp_spaces.json()["code"] == "CUSTOMER_REQUIRED"
    assert resp_spaces.json()["detail"] == "Elige un cliente o escribe su nombre"


@pytest.mark.asyncio
async def test_filter_orders_by_customer_id(
    client: AsyncClient,
    auth_headers,
):
    c1 = (await client.post("/api/v1/customers/", headers=auth_headers, json={"name": "Cliente 1"})).json()
    c2 = (await client.post("/api/v1/customers/", headers=auth_headers, json={"name": "Cliente 2"})).json()

    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Galletas", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # Pedido 1 con c1
    o1 = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": c1["id"],
            "delivery_at": "2026-11-15T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 100}],
        },
    )).json()

    # Pedido 2 con c2
    o2 = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": c2["id"],
            "delivery_at": "2026-11-15T11:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 100}],
        },
    )).json()

    # Pedido 3 sin cliente
    (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Sin Cliente Ligado",
            "delivery_at": "2026-11-15T12:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 100}],
        },
    )).json()

    # Filtrar por c1
    filter_c1 = await client.get(f"/api/v1/orders/?customer_id={c1['id']}", headers=auth_headers)
    assert filter_c1.status_code == 200
    items_c1 = filter_c1.json()["items"]
    assert len(items_c1) == 1
    assert items_c1[0]["id"] == o1["id"]

    # Filtrar por c2
    filter_c2 = await client.get(f"/api/v1/orders/?customer_id={c2['id']}", headers=auth_headers)
    assert filter_c2.status_code == 200
    items_c2 = filter_c2.json()["items"]
    assert len(items_c2) == 1
    assert items_c2[0]["id"] == o2["id"]


@pytest.mark.asyncio
async def test_patch_order_customer_id_null_unlinks_and_preserves_name(
    client: AsyncClient,
    auth_headers,
):
    cust = (await client.post(
        "/api/v1/customers/",
        headers=auth_headers,
        json={"name": "Pedro Picapiedra", "phone": "555-ROCA"},
    )).json()

    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Tartaleta", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    order = (await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_id": cust["id"],
            "delivery_at": "2026-11-20T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "1", "unit_price_cents": 500}],
        },
    )).json()
    order_id = order["id"]

    # Mientras esté ligado a un cliente, un PATCH con solo customer_name se ignora
    patch_ignored = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={"customer_name": "Nombre Ignorado"},
    )
    assert patch_ignored.status_code == 200
    assert patch_ignored.json()["customer_name"] == "Pedro Picapiedra"

    # PATCH con customer_id: null desliga y conserva el nombre y teléfono
    patch_unlink = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={"customer_id": None},
    )
    assert patch_unlink.status_code == 200
    unlinked_data = patch_unlink.json()
    assert unlinked_data["customer_id"] is None
    assert unlinked_data["customer_name"] == "Pedro Picapiedra"
    assert unlinked_data["customer_phone"] == "555-ROCA"

    # Ahora que no está ligado, PATCH con customer_name sí lo cambia
    patch_manual = await client.patch(
        f"/api/v1/orders/{order_id}",
        headers=auth_headers,
        json={"customer_name": "Pablo Mármol"},
    )
    assert patch_manual.status_code == 200
    assert patch_manual.json()["customer_name"] == "Pablo Mármol"


@pytest.mark.asyncio
async def test_order_without_customer_continues_working_as_before(
    client: AsyncClient,
    auth_headers,
):
    rec = (await client.post(
        "/api/v1/recipes/",
        headers=auth_headers,
        json={"name": "Cupcake", "yield_quantity": "1", "yield_unit": "pz"},
    )).json()

    # Crear sin customer_id pero con customer_name
    order_resp = await client.post(
        "/api/v1/orders/",
        headers=auth_headers,
        json={
            "customer_name": "Cliente Ocasional",
            "customer_phone": "555-0011",
            "delivery_at": "2026-11-20T10:00:00Z",
            "items": [{"recipe_id": rec["id"], "quantity": "2", "unit_price_cents": 150}],
        },
    )
    assert order_resp.status_code == 201
    order_data = order_resp.json()
    assert order_data["customer_id"] is None
    assert order_data["customer_name"] == "Cliente Ocasional"
    assert order_data["customer_phone"] == "555-0011"

    # Editar datos del pedido manual
    patch_resp = await client.patch(
        f"/api/v1/orders/{order_data['id']}",
        headers=auth_headers,
        json={"customer_name": "Cliente Ocasional VIP", "customer_phone": "555-9988"},
    )
    assert patch_resp.status_code == 200
    patched_data = patch_resp.json()
    assert patched_data["customer_id"] is None
    assert patched_data["customer_name"] == "Cliente Ocasional VIP"
    assert patched_data["customer_phone"] == "555-9988"
