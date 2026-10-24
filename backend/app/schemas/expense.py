from datetime import datetime

from pydantic import BaseModel, Field


class ExpenseCreate(BaseModel):
    description: str = Field(..., min_length=1, max_length=200)
    amount_cents: int = Field(..., gt=0)
    spent_at: datetime | None = None
    category: str | None = Field(default=None, max_length=50)
    supplier_id: str | None = None


class ExpenseUpdate(BaseModel):
    description: str | None = Field(default=None, min_length=1, max_length=200)
    amount_cents: int | None = Field(default=None, gt=0)
    spent_at: datetime | None = None
    category: str | None = Field(default=None, max_length=50)
    supplier_id: str | None = None


class ExpenseResponse(BaseModel):
    id: str
    description: str
    amount_cents: int
    spent_at: datetime
    category: str | None = None
    supplier_id: str | None = None
    created_at: datetime
