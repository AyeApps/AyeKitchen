import math
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from bson import ObjectId

from app.core.errors import AppError
from app.models.base import parse_decimal, round_to_cents
from app.models.order import Order, OrderItem, OrderStatus, Payment
from app.models.recipe import Recipe
from app.schemas.order import (
    OrderCreate,
    OrderItemResponse,
    OrderResponse,
    OrderUpdate,
    PaymentCreate,
    PaymentResponse,
)
from app.services.costing_service import calculate_recipe_cost
from app.services.customer_service import get_customer


def compute_order_totals(
    order: Order,
) -> tuple[int, int, int, int, int]:
    """Calcula (total_cents, paid_cents, balance_cents, cost_cents, profit_cents) con precisión Decimal."""
    unrounded_total = sum(
        (parse_decimal(it.quantity) * Decimal(it.unit_price_cents) for it in order.items),
        start=Decimal("0"),
    )
    unrounded_cost = sum(
        (parse_decimal(it.quantity) * Decimal(it.unit_cost_cents_snapshot) for it in order.items),
        start=Decimal("0"),
    )
    unrounded_profit = unrounded_total - unrounded_cost

    total_cents = round_to_cents(unrounded_total)
    cost_cents = round_to_cents(unrounded_cost)
    profit_cents = round_to_cents(unrounded_profit)

    paid_cents = sum(p.amount_cents for p in order.payments)
    balance_cents = total_cents - paid_cents

    return total_cents, paid_cents, balance_cents, cost_cents, profit_cents


async def serialize_order(
    order: Order,
    recipe_map: dict[str, str] | None = None,
) -> OrderResponse:
    if recipe_map is None:
        rec_ids = [
            ObjectId(it.recipe_id)
            for it in order.items
            if ObjectId.is_valid(it.recipe_id)
        ]
        recipes = (
            await Recipe.find({"_id": {"$in": rec_ids}}).to_list()
            if rec_ids
            else []
        )
        recipe_map = {str(r.id): r.name for r in recipes}

    total_cents, paid_cents, balance_cents, cost_cents, profit_cents = compute_order_totals(order)

    items_resp = [
        OrderItemResponse(
            recipe_id=it.recipe_id,
            recipe_name=recipe_map.get(it.recipe_id, ""),
            quantity=str(it.quantity),
            unit_price_cents=it.unit_price_cents,
            unit_cost_cents_snapshot=it.unit_cost_cents_snapshot,
        )
        for it in order.items
    ]

    payments_resp = [
        PaymentResponse(
            id=p.id,
            amount_cents=p.amount_cents,
            paid_at=p.paid_at,
            method=p.method,
        )
        for p in order.payments
    ]

    return OrderResponse(
        id=str(order.id),
        customer_id=order.customer_id,
        customer_name=order.customer_name,
        customer_phone=order.customer_phone,
        delivery_at=order.delivery_at,
        status=order.status,
        notes=order.notes,
        items=items_resp,
        payments=payments_resp,
        total_cents=total_cents,
        paid_cents=paid_cents,
        balance_cents=balance_cents,
        cost_cents=cost_cents,
        profit_cents=profit_cents,
        created_at=order.created_at,
        updated_at=order.updated_at,
    )


async def get_order(workspace_id: str, order_id: str) -> Order:
    if not ObjectId.is_valid(order_id):
        raise AppError(status_code=404, detail="Pedido no encontrado", code="NOT_FOUND")

    order = await Order.find_one(
        Order.id == ObjectId(order_id),
        Order.workspace_id == workspace_id,
        Order.deleted_at == None,  # noqa: E711
    )
    if not order:
        raise AppError(status_code=404, detail="Pedido no encontrado", code="NOT_FOUND")

    return order


async def list_orders(
    workspace_id: str,
    page: int = 1,
    limit: int = 20,
    status: OrderStatus | None = None,
    from_dt: datetime | None = None,
    to_dt: datetime | None = None,
    customer_id: str | None = None,
) -> tuple[list[Order], dict[str, str], int, int]:
    limit = min(max(1, limit), 100)
    page = max(1, page)

    filters: dict[str, Any] = {
        "workspace_id": workspace_id,
        "deleted_at": None,
    }
    if customer_id is not None:
        filters["customer_id"] = customer_id
    if status is not None:
        filters["status"] = status

    delivery_filter: dict[str, Any] = {}
    if from_dt is not None:
        if from_dt.tzinfo is None:
            from_dt = from_dt.replace(tzinfo=UTC)
        delivery_filter["$gte"] = from_dt
    if to_dt is not None:
        if to_dt.tzinfo is None:
            to_dt = to_dt.replace(tzinfo=UTC)
        delivery_filter["$lte"] = to_dt
    if delivery_filter:
        filters["delivery_at"] = delivery_filter

    orders = await Order.find(filters).sort("+delivery_at").to_list()

    total = len(orders)
    pages = math.ceil(total / limit) if total > 0 else 0
    skip = (page - 1) * limit
    page_orders = orders[skip : skip + limit]

    all_rec_ids = [
        ObjectId(it.recipe_id)
        for o in page_orders
        for it in o.items
        if ObjectId.is_valid(it.recipe_id)
    ]
    recipes = (
        await Recipe.find({"_id": {"$in": all_rec_ids}}).to_list()
        if all_rec_ids
        else []
    )
    recipe_map = {str(r.id): r.name for r in recipes}

    return page_orders, recipe_map, total, pages


async def create_order(workspace_id: str, data: OrderCreate) -> Order:
    recipe_cache: dict[str, Recipe] = {}
    cost_cache: dict[str, Any] = {}

    for it in data.items:
        if parse_decimal(it.quantity) <= Decimal("0"):
            raise AppError(
                status_code=422,
                detail="La cantidad debe ser mayor que cero",
                code="INVALID_REFERENCE",
            )
        if not ObjectId.is_valid(it.recipe_id):
            raise AppError(
                status_code=422,
                detail=f"Receta no encontrada: {it.recipe_id}",
                code="INVALID_REFERENCE",
            )
        if it.recipe_id not in recipe_cache:
            rec = await Recipe.find_one(
                Recipe.id == ObjectId(it.recipe_id),
                Recipe.workspace_id == workspace_id,
                Recipe.deleted_at == None,  # noqa: E711
            )
            if not rec:
                raise AppError(
                    status_code=422,
                    detail=f"Receta no encontrada: {it.recipe_id}",
                    code="INVALID_REFERENCE",
                )
            recipe_cache[it.recipe_id] = rec

    order_items: list[OrderItem] = []
    for it in data.items:
        rec = recipe_cache[it.recipe_id]
        if it.recipe_id not in cost_cache:
            cost_info = await calculate_recipe_cost(workspace_id, rec)
            cost_cache[it.recipe_id] = cost_info
        else:
            cost_info = cost_cache[it.recipe_id]

        unit_cost_snapshot = cost_info.batch_cost_cents
        unit_price = (
            it.unit_price_cents
            if it.unit_price_cents is not None
            else cost_info.suggested_price_cents
        )

        order_items.append(
            OrderItem(
                recipe_id=it.recipe_id,
                quantity=parse_decimal(it.quantity),
                unit_price_cents=unit_price,
                unit_cost_cents_snapshot=unit_cost_snapshot,
            )
        )

    delivery_at = data.delivery_at
    if delivery_at.tzinfo is None:
        delivery_at = delivery_at.replace(tzinfo=UTC)

    if data.customer_id is not None:
        try:
            customer = await get_customer(workspace_id, data.customer_id)
        except AppError:
            raise AppError(
                status_code=422,
                detail="Cliente no encontrado",
                code="INVALID_REFERENCE",
            ) from None
        order_customer_id = str(customer.id)
        order_customer_name = customer.name
        order_customer_phone = customer.phone
    else:
        if not data.customer_name or not data.customer_name.strip():
            raise AppError(
                status_code=422,
                detail="Elige un cliente o escribe su nombre",
                code="CUSTOMER_REQUIRED",
            )
        order_customer_id = None
        order_customer_name = data.customer_name.strip()
        order_customer_phone = data.customer_phone.strip() if data.customer_phone else None

    order = Order(
        workspace_id=workspace_id,
        customer_id=order_customer_id,
        customer_name=order_customer_name,
        customer_phone=order_customer_phone,
        delivery_at=delivery_at,
        items=order_items,
        notes=data.notes.strip() if data.notes else None,
        status=OrderStatus.pendiente,
    )
    await order.insert()
    return order


async def update_order(
    workspace_id: str,
    order_id: str,
    data: OrderUpdate,
) -> Order:
    order = await get_order(workspace_id, order_id)

    if "customer_id" in data.model_fields_set:
        if data.customer_id is not None:
            try:
                customer = await get_customer(workspace_id, data.customer_id)
            except AppError:
                raise AppError(
                    status_code=422,
                    detail="Cliente no encontrado",
                    code="INVALID_REFERENCE",
                ) from None
            order.customer_id = str(customer.id)
            order.customer_name = customer.name
            order.customer_phone = customer.phone
        else:
            order.customer_id = None
            if "customer_name" in data.model_fields_set and data.customer_name is not None:
                order.customer_name = data.customer_name.strip()
            if "customer_phone" in data.model_fields_set:
                order.customer_phone = data.customer_phone.strip() if data.customer_phone else None
    else:
        if order.customer_id is None:
            if "customer_name" in data.model_fields_set and data.customer_name is not None:
                order.customer_name = data.customer_name.strip()
            if "customer_phone" in data.model_fields_set:
                order.customer_phone = data.customer_phone.strip() if data.customer_phone else None

    if "delivery_at" in data.model_fields_set and data.delivery_at is not None:
        delivery_at = data.delivery_at
        if delivery_at.tzinfo is None:
            delivery_at = delivery_at.replace(tzinfo=UTC)
        order.delivery_at = delivery_at

    if "status" in data.model_fields_set and data.status is not None:
        order.status = data.status

    if "notes" in data.model_fields_set:
        order.notes = data.notes.strip() if data.notes else None

    if "items" in data.model_fields_set and data.items is not None:
        existing_lines: dict[str, OrderItem] = {}
        for item in order.items:
            if item.recipe_id not in existing_lines:
                existing_lines[item.recipe_id] = item

        recipe_cache: dict[str, Recipe] = {}
        cost_cache: dict[str, Any] = {}

        for it in data.items:
            if parse_decimal(it.quantity) <= Decimal("0"):
                raise AppError(
                    status_code=422,
                    detail="La cantidad debe ser mayor que cero",
                    code="INVALID_REFERENCE",
                )
            if not ObjectId.is_valid(it.recipe_id):
                raise AppError(
                    status_code=422,
                    detail=f"Receta no encontrada: {it.recipe_id}",
                    code="INVALID_REFERENCE",
                )
            if it.recipe_id not in recipe_cache:
                rec = await Recipe.find_one(
                    Recipe.id == ObjectId(it.recipe_id),
                    Recipe.workspace_id == workspace_id,
                    Recipe.deleted_at == None,  # noqa: E711
                )
                if not rec:
                    raise AppError(
                        status_code=422,
                        detail=f"Receta no encontrada: {it.recipe_id}",
                        code="INVALID_REFERENCE",
                    )
                recipe_cache[it.recipe_id] = rec

        new_items: list[OrderItem] = []
        for it in data.items:
            rec = recipe_cache[it.recipe_id]
            if it.recipe_id in existing_lines:
                prev_line = existing_lines[it.recipe_id]
                snapshot = prev_line.unit_cost_cents_snapshot
                unit_price = (
                    it.unit_price_cents
                    if it.unit_price_cents is not None
                    else prev_line.unit_price_cents
                )
            else:
                if it.recipe_id not in cost_cache:
                    cost_cache[it.recipe_id] = await calculate_recipe_cost(workspace_id, rec)
                cost_info = cost_cache[it.recipe_id]
                snapshot = cost_info.batch_cost_cents
                unit_price = (
                    it.unit_price_cents
                    if it.unit_price_cents is not None
                    else cost_info.suggested_price_cents
                )

            new_items.append(
                OrderItem(
                    recipe_id=it.recipe_id,
                    quantity=parse_decimal(it.quantity),
                    unit_price_cents=unit_price,
                    unit_cost_cents_snapshot=snapshot,
                )
            )
        order.items = new_items

    total_cents, paid_cents, _, _, _ = compute_order_totals(order)
    if total_cents < paid_cents:
        raise AppError(
            status_code=422,
            detail="El total quedaría por debajo de lo que ya te pagaron",
            code="PAYMENT_EXCEEDS_BALANCE",
        )

    order.updated_at = datetime.now(UTC)
    await order.save()
    return order


async def delete_order(workspace_id: str, order_id: str) -> None:
    order = await get_order(workspace_id, order_id)
    await order.soft_delete()


async def add_payment(
    workspace_id: str,
    order_id: str,
    data: PaymentCreate,
) -> Order:
    order = await get_order(workspace_id, order_id)

    total_cents, paid_cents, _, _, _ = compute_order_totals(order)
    new_paid = paid_cents + data.amount_cents
    if new_paid > total_cents:
        raise AppError(
            status_code=422,
            detail="El pago excede el saldo pendiente",
            code="PAYMENT_EXCEEDS_BALANCE",
        )

    paid_at = data.paid_at or datetime.now(UTC)
    if paid_at.tzinfo is None:
        paid_at = paid_at.replace(tzinfo=UTC)

    payment = Payment(
        amount_cents=data.amount_cents,
        paid_at=paid_at,
        method=data.method.strip() if data.method else None,
    )
    order.payments.append(payment)
    order.updated_at = datetime.now(UTC)
    await order.save()
    return order


async def delete_payment(
    workspace_id: str,
    order_id: str,
    payment_id: str,
) -> Order:
    order = await get_order(workspace_id, order_id)

    target_payment = next((p for p in order.payments if p.id == payment_id), None)
    if not target_payment:
        raise AppError(
            status_code=404,
            detail="Pago no encontrado",
            code="NOT_FOUND",
        )

    order.payments.remove(target_payment)
    order.updated_at = datetime.now(UTC)
    await order.save()
    return order
