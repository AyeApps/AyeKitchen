from beanie import Indexed
from pydantic import BaseModel, Field

from app.models.base import WorkspaceDocument


class CostVersionChoice(BaseModel):
    """En esta versión, el ingrediente se costea con esta marca."""

    ingredient_id: str
    presentation_id: str


class CostVersion(WorkspaceDocument):
    """Versión de costeo de una receta: "Con Selecta", "Con Tres Estrellas".

    Solo guarda qué marca usar por ingrediente. Ingredientes, cantidades y extras
    son siempre los de la receta, así que editar la receta actualiza todas sus versiones.
    La versión base es la receta misma (sus marcas fijadas o la vigente) y no se guarda aquí.
    """

    recipe_id: Indexed(str)
    name: str = Field(..., min_length=1, max_length=60)
    choices: list[CostVersionChoice] = Field(default_factory=list)

    class Settings:
        name = "cost_versions"
        use_state_management = True
