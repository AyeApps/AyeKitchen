from datetime import datetime

from pydantic import BaseModel, Field


class CostVersionChoiceInput(BaseModel):
    ingredient_id: str
    presentation_id: str


class CostVersionCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=60)
    choices: list[CostVersionChoiceInput] = Field(default_factory=list)


class CostVersionUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=60)
    choices: list[CostVersionChoiceInput] | None = None


class CostVersionChoiceResponse(BaseModel):
    ingredient_id: str
    ingredient_name: str
    presentation_id: str
    brand: str


class CostVersionResponse(BaseModel):
    id: str
    recipe_id: str
    name: str
    choices: list[CostVersionChoiceResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class CostVersionCompareResponse(BaseModel):
    version_id: str | None = None
    name: str
    batch_cost_cents: int
    cost_per_serving_cents: int | None = None
    suggested_price_cents: int
    complete: bool
    has_stale_prices: bool = False
