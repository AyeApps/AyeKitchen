from enum import StrEnum

from pydantic import BaseModel, Field

from app.models.base import AyeDecimal, Cents, WorkspaceDocument
from app.models.unit import BaseUnit


class RecipeItemKind(StrEnum):
    ingredient = "ingredient"
    recipe = "recipe"  # Subreceta: betún, relleno, bizcocho base


class RecipeItem(BaseModel):
    kind: RecipeItemKind
    ref_id: str  # Ingredient.id o Recipe.id según kind
    quantity: AyeDecimal  # La cantidad tal como la escribió el usuario
    unit_id: str | None = None  # None = la base_unit del ingrediente / yield_unit de la subreceta
    pinned_presentation_id: str | None = None  # Solo kind=ingredient. None = presentación más reciente


class ExtraCost(BaseModel):
    """Costos fijos por tanda: caja, base, gas, mano de obra."""

    name: str = Field(..., min_length=1, max_length=100)
    cost_cents: Cents = Field(..., ge=0)


class Recipe(WorkspaceDocument):
    name: str = Field(..., min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    items: list[RecipeItem] = Field(default_factory=list)
    extra_costs: list[ExtraCost] = Field(default_factory=list)
    # Lo que rinde una tanda. Necesario para usarla como subreceta (ej. 800 g de betún).
    yield_quantity: AyeDecimal
    yield_unit: BaseUnit
    servings: int | None = Field(default=None, ge=1)  # Porciones, solo informativo
    margin_percent: int | None = Field(default=None, ge=0, le=1000)  # None = el del workspace

    class Settings:
        name = "recipes"
        use_state_management = True
