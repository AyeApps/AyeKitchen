from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field

from app.models.base import AyeDecimal
from app.models.unit import BaseUnit


class IngredientConversionInput(BaseModel):
    unit_id: str
    quantity_in_base: AyeDecimal = Field(..., gt=Decimal("0"))


class IngredientConversionResponse(BaseModel):
    unit_id: str
    unit_name: str
    quantity_in_base: str


class IngredientCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    base_unit: BaseUnit
    group: str | None = Field(default=None, max_length=50)
    notes: str | None = Field(default=None, max_length=500)
    conversions: list[IngredientConversionInput] = Field(default_factory=list)


class IngredientUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    base_unit: BaseUnit | None = None
    group: str | None = Field(default=None, max_length=50)
    notes: str | None = Field(default=None, max_length=500)
    conversions: list[IngredientConversionInput] | None = None


class IngredientResponse(BaseModel):
    id: str
    name: str
    base_unit: BaseUnit
    group: str | None = None
    notes: str | None = None
    conversions: list[IngredientConversionResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
