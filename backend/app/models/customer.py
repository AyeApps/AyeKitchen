from pydantic import Field

from app.models.base import WorkspaceDocument


class Customer(WorkspaceDocument):
    """A quién se le vende. Los pedidos guardan una copia de su nombre y teléfono."""

    name: str = Field(..., min_length=1, max_length=120)
    phone: str | None = Field(default=None, max_length=30)
    notes: str | None = Field(default=None, max_length=500)

    class Settings:
        name = "customers"
        use_state_management = True
