from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field

from app.models.base import AyeDecimal
from app.models.order import OrderStatus


class OrderItemInput(BaseModel):
    recipe_id: str
    quantity: AyeDecimal = Field(default=Decimal("1"), gt=Decimal("0"))
    unit_price_cents: int | None = Field(default=None, ge=0)


class OrderCreate(BaseModel):
    customer_name: str = Field(..., min_length=1, max_length=120)
    customer_phone: str | None = Field(default=None, max_length=30)
    delivery_at: datetime
    items: list[OrderItemInput] = Field(..., min_length=1)
    notes: str | None = Field(default=None, max_length=1000)


class OrderUpdate(BaseModel):
    customer_name: str | None = Field(default=None, min_length=1, max_length=120)
    customer_phone: str | None = Field(default=None, max_length=30)
    delivery_at: datetime | None = None
    status: OrderStatus | None = None
    notes: str | None = Field(default=None, max_length=1000)
    items: list[OrderItemInput] | None = Field(default=None, min_length=1)


class PaymentCreate(BaseModel):
    amount_cents: int = Field(..., gt=0)
    paid_at: datetime | None = None
    method: str | None = Field(default=None, max_length=30)


class PaymentResponse(BaseModel):
    id: str
    amount_cents: int
    paid_at: datetime
    method: str | None = None


class OrderItemResponse(BaseModel):
    recipe_id: str
    recipe_name: str
    quantity: str
    unit_price_cents: int
    unit_cost_cents_snapshot: int


class OrderResponse(BaseModel):
    id: str
    customer_name: str
    customer_phone: str | None = None
    delivery_at: datetime
    status: OrderStatus
    notes: str | None = None
    items: list[OrderItemResponse] = Field(default_factory=list)
    payments: list[PaymentResponse] = Field(default_factory=list)
    total_cents: int
    paid_cents: int
    balance_cents: int
    cost_cents: int
    profit_cents: int
    created_at: datetime
    updated_at: datetime
