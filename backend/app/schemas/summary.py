from pydantic import BaseModel


class MonthlySummaryResponse(BaseModel):
    year: int
    month: int
    income_cents: int
    expenses_cents: int
    net_cents: int
    orders_delivered: int
    orders_pending: int
    sales_cents: int
    estimated_profit_cents: int
    receivable_cents: int
