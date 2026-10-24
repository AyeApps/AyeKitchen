import re
from datetime import UTC, datetime

from bson import ObjectId

from app.core.errors import AppError
from app.models.presentation import Presentation
from app.models.supplier import Supplier
from app.schemas.supplier import SupplierCreate, SupplierUpdate


async def list_suppliers(workspace_id: str) -> list[Supplier]:
    return await Supplier.find(
        Supplier.workspace_id == workspace_id,
        Supplier.deleted_at == None,  # noqa: E711
    ).sort("+name").to_list()


async def get_supplier(workspace_id: str, supplier_id: str) -> Supplier:
    if not ObjectId.is_valid(supplier_id):
        raise AppError(status_code=404, detail="Proveedor no encontrado", code="NOT_FOUND")

    supplier = await Supplier.get(supplier_id)
    if not supplier or supplier.deleted_at is not None:
        raise AppError(status_code=404, detail="Proveedor no encontrado", code="NOT_FOUND")

    if supplier.workspace_id != workspace_id:
        raise AppError(status_code=404, detail="Proveedor no encontrado", code="NOT_FOUND")

    return supplier


async def create_supplier(workspace_id: str, data: SupplierCreate) -> Supplier:
    existing = await Supplier.find_one(
        Supplier.workspace_id == workspace_id,
        Supplier.deleted_at == None,  # noqa: E711
        {"name": {"$regex": f"^{re.escape(data.name.strip())}$", "$options": "i"}},
    )
    if existing:
        raise AppError(
            status_code=409,
            detail="Ya existe un proveedor con ese nombre",
            code="DUPLICATE_NAME",
        )

    supplier = Supplier(
        workspace_id=workspace_id,
        name=data.name.strip(),
        notes=data.notes,
    )
    await supplier.insert()
    return supplier


async def update_supplier(workspace_id: str, supplier_id: str, data: SupplierUpdate) -> Supplier:
    supplier = await get_supplier(workspace_id, supplier_id)

    if data.name is not None:
        existing = await Supplier.find_one(
            Supplier.workspace_id == workspace_id,
            Supplier.deleted_at == None,  # noqa: E711
            Supplier.id != supplier.id,
            {"name": {"$regex": f"^{re.escape(data.name.strip())}$", "$options": "i"}},
        )
        if existing:
            raise AppError(
                status_code=409,
                detail="Ya existe un proveedor con ese nombre",
                code="DUPLICATE_NAME",
            )
        supplier.name = data.name.strip()

    if "notes" in data.model_fields_set:
        supplier.notes = data.notes

    supplier.updated_at = datetime.now(UTC)
    await supplier.save()
    return supplier


async def delete_supplier(workspace_id: str, supplier_id: str) -> None:
    supplier = await get_supplier(workspace_id, supplier_id)

    presentations = await Presentation.find(
        Presentation.workspace_id == workspace_id,
        Presentation.supplier_id == str(supplier.id),
        Presentation.deleted_at == None,  # noqa: E711
    ).to_list()
    for p in presentations:
        p.supplier_id = None
        p.updated_at = datetime.now(UTC)
        await p.save()

    await supplier.soft_delete()
