from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Any, TypeVar

from beanie import Document, Indexed
from bson.decimal128 import Decimal128
from pydantic import BeforeValidator, Field, PlainSerializer

T = TypeVar("T", bound="SoftDeleteDocument")


def parse_decimal(v: Any) -> Decimal:
    if isinstance(v, Decimal128):
        return v.to_decimal()
    if isinstance(v, (int, float, str)):
        return Decimal(str(v))
    if isinstance(v, Decimal):
        return v
    return Decimal(str(v))


# Cantidades (gramos, ml, piezas, tazas). Nunca float: se guardan como Decimal128.
AyeDecimal = Annotated[
    Decimal,
    BeforeValidator(parse_decimal),
    PlainSerializer(lambda x: str(x), return_type=str),
]

# Dinero: siempre centavos enteros (int). 2350 = $23.50.
Cents = int


def round_to_cents(amount: Decimal) -> Cents:
    """Único punto de redondeo de dinero: se aplica una sola vez, al total que se muestra."""
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


class SoftDeleteDocument(Document):
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    deleted_at: datetime | None = None

    async def soft_delete(self):
        self.deleted_at = datetime.now(UTC)
        self.updated_at = datetime.now(UTC)
        await self.save()

    @classmethod
    def active_query(cls: type[T]):
        return cls.find(cls.deleted_at == None)  # noqa: E711


class WorkspaceDocument(SoftDeleteDocument):
    """Todo dato del negocio pertenece a un workspace. Cada query filtra por workspace_id."""

    workspace_id: Indexed(str)
