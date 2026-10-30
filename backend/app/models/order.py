import uuid
from datetime import UTC, datetime
from enum import StrEnum

from beanie import Indexed
from pydantic import BaseModel, Field
from pymongo import ASCENDING, IndexModel

from app.models.base import AyeDecimal, Cents, WorkspaceDocument


class OrderStatus(StrEnum):
    pendiente = "pendiente"
    en_proceso = "en_proceso"
    entregado = "entregado"
    cancelado = "cancelado"


class OrderItem(BaseModel):
    recipe_id: str
    quantity: AyeDecimal = Field(default=1)  # Tandas de la receta
    unit_price_cents: Cents = Field(..., ge=0)  # Lo que se cobra por tanda
    # Foto del costo al crear el pedido, para que la ganancia histórica no cambie con los precios
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
        indexes = [IndexModel([("workspace_id", ASCENDING), ("customer_id", ASCENDING)])]


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
