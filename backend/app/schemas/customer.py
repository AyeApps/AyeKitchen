from datetime import datetime

from pydantic import BaseModel, Field


class CustomerCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    phone: str | None = Field(default=None, max_length=30)
    notes: str | None = Field(default=None, max_length=500)


class CustomerUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    phone: str | None = Field(default=None, max_length=30)
    notes: str | None = Field(default=None, max_length=500)


class CustomerResponse(BaseModel):
    id: str
    name: str
    phone: str | None = None
    notes: str | None = None
    created_at: datetime
    updated_at: datetime
