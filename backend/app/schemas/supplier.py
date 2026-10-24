from datetime import datetime

from pydantic import BaseModel, Field


class SupplierCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    notes: str | None = Field(default=None, max_length=500)


class SupplierUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    notes: str | None = Field(default=None, max_length=500)


class SupplierResponse(BaseModel):
    id: str
    name: str
    notes: str | None = None
    created_at: datetime
    updated_at: datetime
