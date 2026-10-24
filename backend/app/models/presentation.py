from datetime import UTC, datetime

from beanie import Indexed
from pydantic import Field
from pymongo import ASCENDING, IndexModel

from app.models.base import AyeDecimal, Cents, WorkspaceDocument


class Presentation(WorkspaceDocument):
    """Lo que se compra: Harina marca X, Walmart, bolsa de 1000 g.

    package_quantity va en la base_unit del ingrediente. El precio vive en PriceRecord.
    """

    ingredient_id: Indexed(str)
    brand: str = Field(..., min_length=1, max_length=100)
    supplier_id: str | None = None
    package_quantity: AyeDecimal
    barcode: str | None = None  # Reservado para el escáner futuro

    class Settings:
        name = "presentations"
        use_state_management = True
        # Indexed(...) | None no crea índice en Beanie: se declara aquí
        indexes = [IndexModel([("workspace_id", ASCENDING), ("barcode", ASCENDING)])]


class PriceRecord(WorkspaceDocument):
    """Historial de precios. El precio vigente de una presentación es su registro más reciente."""

    presentation_id: Indexed(str)
    price_cents: Cents = Field(..., ge=0)
    recorded_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    note: str | None = Field(default=None, max_length=200)

    class Settings:
        name = "price_records"
        use_state_management = True
