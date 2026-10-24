from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field

from app.models.base import AyeDecimal
from app.models.unit import BaseUnit


class PriceRecordCreate(BaseModel):
    price_cents: int = Field(..., ge=0)
    recorded_at: datetime | None = None
    note: str | None = Field(default=None, max_length=200)


class PriceRecordResponse(BaseModel):
    id: str
    price_cents: int
    recorded_at: datetime
    note: str | None = None


class PresentationCreate(BaseModel):
    ingredient_id: str
    brand: str = Field(..., min_length=1, max_length=100)
    supplier_id: str | None = None
    package_quantity: AyeDecimal = Field(..., gt=Decimal("0"))
    package_unit_id: str | None = None
    barcode: str | None = Field(default=None, max_length=100)
    price_cents: int | None = Field(default=None, ge=0)


class PresentationUpdate(BaseModel):
    brand: str | None = Field(default=None, min_length=1, max_length=100)
    supplier_id: str | None = None
    package_quantity: AyeDecimal | None = Field(default=None, gt=Decimal("0"))
    package_unit_id: str | None = None
    barcode: str | None = Field(default=None, max_length=100)


class PresentationResponse(BaseModel):
    id: str
    ingredient_id: str
    ingredient_name: str
    brand: str
    supplier_id: str | None = None
    supplier_name: str | None = None
    package_quantity: str
    base_unit: BaseUnit
    barcode: str | None = None
    latest_price_cents: int | None = None
    latest_price_at: datetime | None = None
    cost_per_base_unit: str | None = None
    is_current: bool
    created_at: datetime
    updated_at: datetime
