import math
from datetime import UTC, datetime
from typing import Any

from bson import ObjectId

from app.core.errors import AppError
from app.models.order import Expense
from app.models.supplier import Supplier
from app.schemas.expense import ExpenseCreate, ExpenseResponse, ExpenseUpdate


def serialize_expense(expense: Expense) -> ExpenseResponse:
    return ExpenseResponse(
        id=str(expense.id),
        description=expense.description,
        amount_cents=expense.amount_cents,
        spent_at=expense.spent_at,
        category=expense.category,
        supplier_id=expense.supplier_id,
        created_at=expense.created_at,
    )


async def get_expense(workspace_id: str, expense_id: str) -> Expense:
    if not ObjectId.is_valid(expense_id):
        raise AppError(status_code=404, detail="Gasto no encontrado", code="NOT_FOUND")

    expense = await Expense.find_one(
        Expense.id == ObjectId(expense_id),
        Expense.workspace_id == workspace_id,
        Expense.deleted_at == None,  # noqa: E711
    )
    if not expense:
        raise AppError(status_code=404, detail="Gasto no encontrado", code="NOT_FOUND")

    return expense


async def list_expenses(
    workspace_id: str,
    page: int = 1,
    limit: int = 20,
    from_dt: datetime | None = None,
    to_dt: datetime | None = None,
    category: str | None = None,
) -> tuple[list[Expense], int, int]:
    limit = min(max(1, limit), 100)
    page = max(1, page)

    filters: dict[str, Any] = {
        "workspace_id": workspace_id,
        "deleted_at": None,
    }
    if category is not None and category.strip():
        filters["category"] = category.strip()

    spent_filter: dict[str, Any] = {}
    if from_dt is not None:
        if from_dt.tzinfo is None:
            from_dt = from_dt.replace(tzinfo=UTC)
        spent_filter["$gte"] = from_dt
    if to_dt is not None:
        if to_dt.tzinfo is None:
            to_dt = to_dt.replace(tzinfo=UTC)
        spent_filter["$lte"] = to_dt
    if spent_filter:
        filters["spent_at"] = spent_filter

    expenses = await Expense.find(filters).sort("-spent_at").to_list()

    total = len(expenses)
    pages = math.ceil(total / limit) if total > 0 else 0
    skip = (page - 1) * limit
    page_items = expenses[skip : skip + limit]

    return page_items, total, pages


async def create_expense(workspace_id: str, data: ExpenseCreate) -> Expense:
    if data.supplier_id:
        if not ObjectId.is_valid(data.supplier_id):
            raise AppError(
                status_code=422,
                detail=f"Proveedor no encontrado: {data.supplier_id}",
                code="INVALID_REFERENCE",
            )
        supplier = await Supplier.find_one(
            Supplier.id == ObjectId(data.supplier_id),
            Supplier.workspace_id == workspace_id,
            Supplier.deleted_at == None,  # noqa: E711
        )
        if not supplier:
            raise AppError(
                status_code=422,
                detail=f"Proveedor no encontrado: {data.supplier_id}",
                code="INVALID_REFERENCE",
            )

    spent_at = data.spent_at or datetime.now(UTC)
    if spent_at.tzinfo is None:
        spent_at = spent_at.replace(tzinfo=UTC)

    expense = Expense(
        workspace_id=workspace_id,
        description=data.description.strip(),
        amount_cents=data.amount_cents,
        spent_at=spent_at,
        category=data.category.strip() if data.category else None,
        supplier_id=data.supplier_id,
    )
    await expense.insert()
    return expense


async def update_expense(
    workspace_id: str,
    expense_id: str,
    data: ExpenseUpdate,
) -> Expense:
    expense = await get_expense(workspace_id, expense_id)

    if "description" in data.model_fields_set and data.description is not None:
        expense.description = data.description.strip()

    if "amount_cents" in data.model_fields_set and data.amount_cents is not None:
        expense.amount_cents = data.amount_cents

    if "spent_at" in data.model_fields_set and data.spent_at is not None:
        spent_at = data.spent_at
        if spent_at.tzinfo is None:
            spent_at = spent_at.replace(tzinfo=UTC)
        expense.spent_at = spent_at

    if "category" in data.model_fields_set:
        expense.category = data.category.strip() if data.category else None

    if "supplier_id" in data.model_fields_set:
        if data.supplier_id is not None:
            if not ObjectId.is_valid(data.supplier_id):
                raise AppError(
                    status_code=422,
                    detail=f"Proveedor no encontrado: {data.supplier_id}",
                    code="INVALID_REFERENCE",
                )
            supplier = await Supplier.find_one(
                Supplier.id == ObjectId(data.supplier_id),
                Supplier.workspace_id == workspace_id,
                Supplier.deleted_at == None,  # noqa: E711
            )
            if not supplier:
                raise AppError(
                    status_code=422,
                    detail=f"Proveedor no encontrado: {data.supplier_id}",
                    code="INVALID_REFERENCE",
                )
            expense.supplier_id = data.supplier_id
        else:
            expense.supplier_id = None

    expense.updated_at = datetime.now(UTC)
    await expense.save()
    return expense


async def delete_expense(workspace_id: str, expense_id: str) -> None:
    expense = await get_expense(workspace_id, expense_id)
    await expense.soft_delete()
