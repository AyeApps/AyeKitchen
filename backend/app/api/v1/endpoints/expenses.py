from datetime import datetime

from fastapi import APIRouter, Query, status

from app.core.deps import CurrentWorkspace
from app.schemas.expense import (
    ExpenseCreate,
    ExpenseResponse,
    ExpenseUpdate,
)
from app.schemas.pagination import PaginatedResponse
from app.services.expense_service import (
    create_expense,
    delete_expense,
    list_expenses,
    serialize_expense,
    update_expense,
)

router = APIRouter()


@router.get("/", response_model=PaginatedResponse[ExpenseResponse])
async def list_expenses_endpoint(
    workspace: CurrentWorkspace,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    from_date: datetime | None = Query(None, alias="from"),
    to_date: datetime | None = Query(None, alias="to"),
    category: str | None = None,
):
    ws_id = str(workspace.id)
    expenses, total, pages = await list_expenses(
        ws_id,
        page=page,
        limit=limit,
        from_dt=from_date,
        to_dt=to_date,
        category=category,
    )
    items = [serialize_expense(e) for e in expenses]
    return PaginatedResponse(
        items=items,
        total=total,
        page=page,
        limit=limit,
        pages=pages,
    )


@router.post("/", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
async def create_expense_endpoint(
    data: ExpenseCreate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    expense = await create_expense(ws_id, data)
    return serialize_expense(expense)


@router.patch("/{id}", response_model=ExpenseResponse)
async def update_expense_endpoint(
    id: str,
    data: ExpenseUpdate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    expense = await update_expense(ws_id, id, data)
    return serialize_expense(expense)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_expense_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    await delete_expense(ws_id, id)
    return None
