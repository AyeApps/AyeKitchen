import re
from datetime import UTC, datetime
from typing import Any

from bson import ObjectId

from app.core.errors import AppError
from app.models.customer import Customer
from app.models.order import Order
from app.schemas.customer import CustomerCreate, CustomerUpdate


async def list_customers(workspace_id: str, q: str | None = None) -> list[Customer]:
    query_filters: list[Any] = [
        Customer.workspace_id == workspace_id,
        Customer.deleted_at == None,  # noqa: E711
    ]
    if q and q.strip():
        pattern = re.escape(q.strip())
        query_filters.append(
            {
                "$or": [
                    {"name": {"$regex": pattern, "$options": "i"}},
                    {"phone": {"$regex": pattern, "$options": "i"}},
                ]
            }
        )

    return await Customer.find(*query_filters).sort("+name").to_list()


async def get_customer(workspace_id: str, customer_id: str) -> Customer:
    if not ObjectId.is_valid(customer_id):
        raise AppError(status_code=404, detail="Cliente no encontrado", code="NOT_FOUND")

    customer = await Customer.get(customer_id)
    if not customer or customer.deleted_at is not None or customer.workspace_id != workspace_id:
        raise AppError(status_code=404, detail="Cliente no encontrado", code="NOT_FOUND")

    return customer


async def create_customer(workspace_id: str, data: CustomerCreate) -> Customer:
    trimmed_name = data.name.strip()
    existing = await Customer.find_one(
        Customer.workspace_id == workspace_id,
        Customer.deleted_at == None,  # noqa: E711
        {"name": {"$regex": f"^{re.escape(trimmed_name)}$", "$options": "i"}},
    )
    if existing:
        raise AppError(
            status_code=409,
            detail="Ya existe un cliente con ese nombre",
            code="DUPLICATE_NAME",
        )

    phone = data.phone.strip() if data.phone and data.phone.strip() else None
    notes = data.notes.strip() if data.notes and data.notes.strip() else None

    customer = Customer(
        workspace_id=workspace_id,
        name=trimmed_name,
        phone=phone,
        notes=notes,
    )
    await customer.insert()
    return customer


async def update_customer(workspace_id: str, customer_id: str, data: CustomerUpdate) -> Customer:
    customer = await get_customer(workspace_id, customer_id)

    name_changed = False
    phone_changed = False

    if data.name is not None:
        trimmed_name = data.name.strip()
        existing = await Customer.find_one(
            Customer.workspace_id == workspace_id,
            Customer.deleted_at == None,  # noqa: E711
            Customer.id != customer.id,
            {"name": {"$regex": f"^{re.escape(trimmed_name)}$", "$options": "i"}},
        )
        if existing:
            raise AppError(
                status_code=409,
                detail="Ya existe un cliente con ese nombre",
                code="DUPLICATE_NAME",
            )
        if customer.name != trimmed_name:
            customer.name = trimmed_name
            name_changed = True

    if "phone" in data.model_fields_set:
        new_phone = data.phone.strip() if data.phone and data.phone.strip() else None
        if customer.phone != new_phone:
            customer.phone = new_phone
            phone_changed = True

    if "notes" in data.model_fields_set:
        customer.notes = data.notes.strip() if data.notes and data.notes.strip() else None

    customer.updated_at = datetime.now(UTC)
    await customer.save()

    if name_changed or phone_changed:
        now = datetime.now(UTC)
        await Order.find(
            Order.workspace_id == workspace_id,
            Order.customer_id == str(customer.id),
            Order.deleted_at == None,  # noqa: E711
        ).update_many(
            {
                "$set": {
                    "customer_name": customer.name,
                    "customer_phone": customer.phone,
                    "updated_at": now,
                }
            }
        )

    return customer


async def delete_customer(workspace_id: str, customer_id: str) -> None:
    customer = await get_customer(workspace_id, customer_id)

    await customer.soft_delete()

    now = datetime.now(UTC)
    await Order.find(
        Order.workspace_id == workspace_id,
        Order.customer_id == str(customer.id),
        Order.deleted_at == None,  # noqa: E711
    ).update_many(
        {
            "$set": {
                "customer_id": None,
                "updated_at": now,
            }
        }
    )
