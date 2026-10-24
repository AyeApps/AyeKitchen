from datetime import datetime

from fastapi import APIRouter, Query, status

from app.core.deps import CurrentWorkspace
from app.models.order import OrderStatus
from app.schemas.order import (
    OrderCreate,
    OrderResponse,
    OrderUpdate,
    PaymentCreate,
)
from app.schemas.pagination import PaginatedResponse
from app.services.order_service import (
    add_payment,
    create_order,
    delete_order,
    delete_payment,
    get_order,
    list_orders,
    serialize_order,
    update_order,
)

router = APIRouter()


@router.get("/", response_model=PaginatedResponse[OrderResponse])
async def list_orders_endpoint(
    workspace: CurrentWorkspace,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    status: OrderStatus | None = None,
    from_date: datetime | None = Query(None, alias="from"),
    to_date: datetime | None = Query(None, alias="to"),
):
    ws_id = str(workspace.id)
    orders, recipe_map, total, pages = await list_orders(
        ws_id,
        page=page,
        limit=limit,
        status=status,
        from_dt=from_date,
        to_dt=to_date,
    )
    items = [await serialize_order(o, recipe_map) for o in orders]
    return PaginatedResponse(
        items=items,
        total=total,
        page=page,
        limit=limit,
        pages=pages,
    )


@router.post("/", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order_endpoint(
    data: OrderCreate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    order = await create_order(ws_id, data)
    return await serialize_order(order)


@router.get("/{id}", response_model=OrderResponse)
async def get_order_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    order = await get_order(ws_id, id)
    return await serialize_order(order)


@router.patch("/{id}", response_model=OrderResponse)
async def update_order_endpoint(
    id: str,
    data: OrderUpdate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    order = await update_order(ws_id, id, data)
    return await serialize_order(order)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_order_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    await delete_order(ws_id, id)
    return None


@router.post("/{id}/payments", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def add_payment_endpoint(
    id: str,
    data: PaymentCreate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    order = await add_payment(ws_id, id, data)
    return await serialize_order(order)


@router.delete("/{id}/payments/{payment_id}", response_model=OrderResponse)
async def delete_payment_endpoint(
    id: str,
    payment_id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    order = await delete_payment(ws_id, id, payment_id)
    return await serialize_order(order)
