import uuid
from datetime import UTC, datetime
from enum import StrEnum

from beanie import Indexed
from pydantic import BaseModel, Field
from pymongo import ASCENDING, DESCENDING, IndexModel

from app.models.base import AyeDecimal, Cents, WorkspaceDocument
from app.models.unit import BaseUnit


class OrderStatus(StrEnum):
    pendiente = "pendiente"
    en_proceso = "en_proceso"
    entregado = "entregado"
    cancelado = "cancelado"


class OrderSoldBy(StrEnum):
    """Cómo se vende la línea (B7)."""

    batch = "batch"  # Tandas completas de la receta (ej. 1 docena)
    unit = "unit"  # La unidad que rinde la receta (ej. 4 galletas de una receta que rinde 12 pz)


class OrderItem(BaseModel):
    recipe_id: str
    sold_by: OrderSoldBy = OrderSoldBy.batch  # Las líneas anteriores a B7 son por tanda
    # Foto de recipe.yield_unit cuando sold_by=unit ("4 pz"); None en tandas
    unit_label: BaseUnit | None = None
    quantity: AyeDecimal = Field(default=1)  # Tandas, o unidades de rendimiento si sold_by=unit
    unit_price_cents: Cents = Field(..., ge=0)  # Lo que se cobra por tanda o por unidad
    # Foto del costo al crear la línea (por tanda o por unidad), para que la ganancia histórica no cambie
    unit_cost_cents_snapshot: Cents = 0


class Payment(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    amount_cents: Cents = Field(..., gt=0)
    paid_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    method: str | None = Field(default=None, max_length=30)  # efectivo, transferencia...


class Order(WorkspaceDocument):
    # Liga opcional a Customer (B5); customer_name/customer_phone son la copia que se muestra
    customer_id: str | None = None
    customer_name: str = Field(..., min_length=1, max_length=120)
    customer_phone: str | None = Field(default=None, max_length=30)
    delivery_at: Indexed(datetime)
    items: list[OrderItem] = Field(default_factory=list)
    payments: list[Payment] = Field(default_factory=list)
    status: OrderStatus = OrderStatus.pendiente
    notes: str | None = Field(default=None, max_length=1000)

    class Settings:
        name = "orders"
        use_state_management = True
        # B8: /me/changes busca el updated_at más reciente por workspace
        indexes = [
            IndexModel([("workspace_id", ASCENDING), ("customer_id", ASCENDING)]),
            IndexModel([("workspace_id", ASCENDING), ("updated_at", DESCENDING)]),
        ]


class Expense(WorkspaceDocument):
    """Gastos del negocio (compras de insumos, gas, empaque al mayoreo)."""

    description: str = Field(..., min_length=1, max_length=200)
    amount_cents: Cents = Field(..., gt=0)
    spent_at: Indexed(datetime) = Field(default_factory=lambda: datetime.now(UTC))
    category: str | None = Field(default=None, max_length=50)
    supplier_id: str | None = None

    class Settings:
        name = "expenses"
        use_state_management = True
        # B8: /me/changes busca el updated_at más reciente por workspace
        indexes = [IndexModel([("workspace_id", ASCENDING), ("updated_at", DESCENDING)])]
