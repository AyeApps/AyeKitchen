from pydantic import BaseModel, Field

from app.models.base import AyeDecimal, WorkspaceDocument
from app.models.unit import BaseUnit


class IngredientConversion(BaseModel):
    """Equivalencia propia del ingrediente: 1 <unit_id> = quantity_in_base <base_unit del ingrediente>.

    Ej: Harina (base g): 1 taza = 125 g. Gana sobre la tabla general.
    """

    unit_id: str
    quantity_in_base: AyeDecimal


class Ingredient(WorkspaceDocument):
    """La categoría genérica que pide la receta: "Harina de trigo", "Huevo"."""

    name: str = Field(..., min_length=1, max_length=100)
    base_unit: BaseUnit
    group: str | None = Field(default=None, max_length=50)  # Ej: "Lácteos", "Secos"
    conversions: list[IngredientConversion] = Field(default_factory=list)
    notes: str | None = Field(default=None, max_length=500)

    class Settings:
        name = "ingredients"
        use_state_management = True
