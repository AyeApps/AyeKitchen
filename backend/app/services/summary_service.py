from datetime import UTC, datetime
from zoneinfo import ZoneInfo

from bson import ObjectId

from app.models.order import Expense, Order, OrderStatus
from app.models.workspace import Workspace
from app.schemas.summary import MonthlySummaryResponse
from app.services.order_service import compute_order_totals


def _ensure_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


async def get_monthly_summary(
    workspace_or_id: Workspace | str,
    year: int,
    month: int,
) -> MonthlySummaryResponse:
    if isinstance(workspace_or_id, Workspace):
        workspace_id = str(workspace_or_id.id)
        tz_name = workspace_or_id.timezone or "America/Mexico_City"
    else:
        workspace_id = str(workspace_or_id)
        tz_name = "America/Mexico_City"
        ws = None
        if ObjectId.is_valid(workspace_id):
            ws = await Workspace.get(ObjectId(workspace_id))
        if not ws:
            ws = await Workspace.get(workspace_id)
        if ws and ws.timezone:
            tz_name = ws.timezone

    tz = ZoneInfo(tz_name)
    dt_start_local = datetime(year, month, 1, 0, 0, 0, tzinfo=tz)
    if month == 12:
        dt_end_local = datetime(year + 1, 1, 1, 0, 0, 0, tzinfo=tz)
    else:
        dt_end_local = datetime(year, month + 1, 1, 0, 0, 0, tzinfo=tz)

    start_utc = dt_start_local.astimezone(UTC)
    end_utc = dt_end_local.astimezone(UTC)

    orders = await Order.find(
        Order.workspace_id == workspace_id,
        Order.deleted_at == None,  # noqa: E711
    ).to_list()

    expenses = await Expense.find(
        Expense.workspace_id == workspace_id,
        Expense.deleted_at == None,  # noqa: E711
    ).to_list()

    income_cents = 0
    for o in orders:
        if o.status != OrderStatus.cancelado:
            for p in o.payments:
                if start_utc <= _ensure_utc(p.paid_at) < end_utc:
                    income_cents += p.amount_cents

    expenses_cents = 0
    for e in expenses:
        if start_utc <= _ensure_utc(e.spent_at) < end_utc:
            expenses_cents += e.amount_cents

    net_cents = income_cents - expenses_cents

    orders_delivered = 0
    sales_cents = 0
    estimated_profit_cents = 0
    orders_pending = 0
    receivable_cents = 0

    for o in orders:
        deliv_utc = _ensure_utc(o.delivery_at)
        if start_utc <= deliv_utc < end_utc:
            total_c, _, balance_c, _, profit_c = compute_order_totals(o)
            if o.status == OrderStatus.entregado:
                orders_delivered += 1
                sales_cents += total_c
                estimated_profit_cents += profit_c
            elif o.status in (OrderStatus.pendiente, OrderStatus.en_proceso):
                orders_pending += 1

            if o.status != OrderStatus.cancelado:
                receivable_cents += balance_c

    return MonthlySummaryResponse(
        year=year,
        month=month,
        income_cents=income_cents,
        expenses_cents=expenses_cents,
        net_cents=net_cents,
        orders_delivered=orders_delivered,
        orders_pending=orders_pending,
        sales_cents=sales_cents,
        estimated_profit_cents=estimated_profit_cents,
        receivable_cents=receivable_cents,
    )
