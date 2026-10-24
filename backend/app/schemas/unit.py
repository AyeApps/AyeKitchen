from decimal import Decimal

from pydantic import BaseModel, Field

from app.models.base import AyeDecimal
from app.models.unit import BaseUnit


class UnitCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    abbreviation: str = Field(..., min_length=1, max_length=12)
    base_unit: BaseUnit
    factor_to_base: AyeDecimal = Field(..., gt=Decimal("0"))


class UnitUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=50)
    abbreviation: str | None = Field(default=None, min_length=1, max_length=12)
    base_unit: BaseUnit | None = None
    factor_to_base: AyeDecimal | None = Field(default=None, gt=Decimal("0"))


class UnitResponse(BaseModel):
    id: str
    name: str
    abbreviation: str
    base_unit: BaseUnit
    factor_to_base: str
    is_system: bool
