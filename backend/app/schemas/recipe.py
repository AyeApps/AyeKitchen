from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field

from app.models.base import AyeDecimal
from app.models.recipe import RecipeItemKind
from app.models.unit import BaseUnit


class RecipeItemInput(BaseModel):
    kind: RecipeItemKind
    ref_id: str
    quantity: AyeDecimal = Field(..., gt=Decimal("0"))
    unit_id: str | None = None
    pinned_presentation_id: str | None = None


class ExtraCostInput(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    cost_cents: int = Field(..., ge=0)


class RecipeCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    items: list[RecipeItemInput] = Field(default_factory=list)
    extra_costs: list[ExtraCostInput] = Field(default_factory=list)
    yield_quantity: AyeDecimal = Field(..., gt=Decimal("0"))
    yield_unit: BaseUnit
    servings: int | None = Field(default=None, ge=1)
    margin_percent: int | None = Field(default=None, ge=0, le=1000)


class RecipeUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    items: list[RecipeItemInput] | None = None
    extra_costs: list[ExtraCostInput] | None = None
    yield_quantity: AyeDecimal | None = Field(default=None, gt=Decimal("0"))
    yield_unit: BaseUnit | None = None
    servings: int | None = Field(default=None, ge=1)
    margin_percent: int | None = Field(default=None, ge=0, le=1000)


class RecipeItemResponse(BaseModel):
    kind: RecipeItemKind
    ref_id: str
    ref_name: str
    quantity: str
    unit_id: str | None = None
    unit_name: str | None = None
    pinned_presentation_id: str | None = None


class ExtraCostResponse(BaseModel):
    name: str
    cost_cents: int


class RecipeResponse(BaseModel):
    id: str
    name: str
    description: str | None = None
    items: list[RecipeItemResponse] = Field(default_factory=list)
    extra_costs: list[ExtraCostResponse] = Field(default_factory=list)
    yield_quantity: str
    yield_unit: BaseUnit
    servings: int | None = None
    margin_percent: int | None = None
    created_at: datetime
    updated_at: datetime


class RecipeListItemResponse(RecipeResponse):
    batch_cost_cents: int | None = None
    complete: bool


class UsableSubrecipeResponse(BaseModel):
    id: str
    name: str
    yield_unit: BaseUnit


class CostLineResponse(BaseModel):
    kind: RecipeItemKind
    ref_id: str
    ref_name: str
    quantity: str
    unit_name: str | None = None
    quantity_in_base: str
    base_unit: BaseUnit
    presentation_id: str | None = None
    presentation_label: str | None = None
    pinned: bool = False
    cost_cents: int
    missing_price: bool


class RecipeCostResponse(BaseModel):
    recipe_id: str
    lines: list[CostLineResponse] = Field(default_factory=list)
    ingredients_cost_cents: int
    extras_cost_cents: int
    batch_cost_cents: int
    cost_per_yield_unit: str
    cost_per_serving_cents: int | None = None
    margin_percent: int
    suggested_price_cents: int
    complete: bool
