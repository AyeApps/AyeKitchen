from fastapi import APIRouter, Query, status

from app.core.deps import CurrentWorkspace
from app.models.customer import Customer
from app.schemas.customer import CustomerCreate, CustomerResponse, CustomerUpdate
from app.services.customer_service import (
    create_customer,
    delete_customer,
    get_customer,
    list_customers,
    update_customer,
)

router = APIRouter()


def _serialize_customer(customer: Customer) -> CustomerResponse:
    return CustomerResponse(
        id=str(customer.id),
        name=customer.name,
        phone=customer.phone,
        notes=customer.notes,
        created_at=customer.created_at,
        updated_at=customer.updated_at,
    )


@router.get("/", response_model=list[CustomerResponse])
async def list_customers_endpoint(
    workspace: CurrentWorkspace,
    q: str | None = Query(None),
):
    customers = await list_customers(str(workspace.id), q=q)
    return [_serialize_customer(c) for c in customers]


@router.post("/", response_model=CustomerResponse, status_code=status.HTTP_201_CREATED)
async def create_customer_endpoint(
    data: CustomerCreate,
    workspace: CurrentWorkspace,
):
    customer = await create_customer(str(workspace.id), data)
    return _serialize_customer(customer)


@router.get("/{id}", response_model=CustomerResponse)
async def get_customer_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    customer = await get_customer(str(workspace.id), id)
    return _serialize_customer(customer)


@router.patch("/{id}", response_model=CustomerResponse)
async def update_customer_endpoint(
    id: str,
    data: CustomerUpdate,
    workspace: CurrentWorkspace,
):
    customer = await update_customer(str(workspace.id), id, data)
    return _serialize_customer(customer)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_customer_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    await delete_customer(str(workspace.id), id)
    return None
