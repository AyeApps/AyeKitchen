from pydantic import Field
from pymongo import ASCENDING, DESCENDING, IndexModel

from app.models.base import WorkspaceDocument


class Supplier(WorkspaceDocument):
    """Dónde se compra: Walmart, Costco, el mercado."""

    name: str = Field(..., min_length=1, max_length=100)
    notes: str | None = Field(default=None, max_length=500)

    class Settings:
        name = "suppliers"
        use_state_management = True
        # B8: /me/changes busca el updated_at más reciente por workspace
        indexes = [IndexModel([("workspace_id", ASCENDING), ("updated_at", DESCENDING)])]
