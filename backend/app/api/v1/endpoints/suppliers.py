from fastapi import APIRouter, status

from app.core.deps import CurrentWorkspace
from app.models.supplier import Supplier
from app.schemas.supplier import SupplierCreate, SupplierResponse, SupplierUpdate
from app.services.supplier_service import (
    create_supplier,
    delete_supplier,
    get_supplier,
    list_suppliers,
    update_supplier,
)

router = APIRouter()


def _serialize_supplier(sup: Supplier) -> SupplierResponse:
    return SupplierResponse(
        id=str(sup.id),
        name=sup.name,
        notes=sup.notes,
        created_at=sup.created_at,
        updated_at=sup.updated_at,
    )


@router.get("/", response_model=list[SupplierResponse])
async def list_suppliers_endpoint(workspace: CurrentWorkspace):
    suppliers = await list_suppliers(str(workspace.id))
    return [_serialize_supplier(s) for s in suppliers]


@router.post("/", response_model=SupplierResponse, status_code=status.HTTP_201_CREATED)
async def create_supplier_endpoint(data: SupplierCreate, workspace: CurrentWorkspace):
    supplier = await create_supplier(str(workspace.id), data)
    return _serialize_supplier(supplier)


@router.get("/{id}", response_model=SupplierResponse)
async def get_supplier_endpoint(id: str, workspace: CurrentWorkspace):
    supplier = await get_supplier(str(workspace.id), id)
    return _serialize_supplier(supplier)


@router.patch("/{id}", response_model=SupplierResponse)
async def update_supplier_endpoint(id: str, data: SupplierUpdate, workspace: CurrentWorkspace):
    supplier = await update_supplier(str(workspace.id), id, data)
    return _serialize_supplier(supplier)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_supplier_endpoint(id: str, workspace: CurrentWorkspace):
    await delete_supplier(str(workspace.id), id)
    return None
