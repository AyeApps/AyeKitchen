from enum import StrEnum

from pydantic import Field
from pymongo import ASCENDING, IndexModel

from app.models.base import AyeDecimal, SoftDeleteDocument


class BaseUnit(StrEnum):
    """Unidades atómicas. Todo se guarda y se calcula en una de estas."""

    g = "g"
    ml = "ml"
    pz = "pz"


class Unit(SoftDeleteDocument):
    """Tabla general de conversiones: 1 <name> = factor_to_base <base_unit>.

    Ej: taza = 240 ml, cda = 15 ml, kg = 1000 g, docena = 12 pz.
    workspace_id None = unidad del sistema (sembrada, no editable por el usuario).
    """

    workspace_id: str | None = None
    name: str = Field(..., min_length=1, max_length=50)
    abbreviation: str = Field(..., min_length=1, max_length=12)
    base_unit: BaseUnit
    factor_to_base: AyeDecimal

    class Settings:
        name = "units"
        use_state_management = True
        # Indexed(...) | None no crea índice en Beanie: se declara aquí
        indexes = [IndexModel([("workspace_id", ASCENDING)])]
