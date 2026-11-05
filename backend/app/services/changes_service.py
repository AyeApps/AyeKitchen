import asyncio
from datetime import UTC, datetime

from beanie import Document

from app.models.cost_version import CostVersion
from app.models.customer import Customer
from app.models.ingredient import Ingredient
from app.models.order import Expense, Order
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.supplier import Supplier
from app.models.unit import Unit
from app.schemas.me import ChangesResponse


def _max_dt(*dts: datetime | None) -> datetime | None:
    valid = [d for d in dts if d is not None]
    return max(valid) if valid else None


async def _get_latest_updated_at(model: type[Document], workspace_id: str) -> datetime | None:
    doc = (
        await model.find({"workspace_id": workspace_id})
        .sort("-updated_at")
        .first_or_none()
    )
    if doc and doc.updated_at:
        dt = doc.updated_at
        if dt.tzinfo is None:
            return dt.replace(tzinfo=UTC)
        return dt
    return None


async def get_workspace_changes(workspace_id: str) -> ChangesResponse:
    (
        t_ingredients,
        t_presentations,
        t_price_records,
        t_suppliers,
        t_units,
        t_recipes,
        t_cost_versions,
        t_customers,
        t_orders,
        t_expenses,
    ) = await asyncio.gather(
        _get_latest_updated_at(Ingredient, workspace_id),
        _get_latest_updated_at(Presentation, workspace_id),
        _get_latest_updated_at(PriceRecord, workspace_id),
        _get_latest_updated_at(Supplier, workspace_id),
        _get_latest_updated_at(Unit, workspace_id),
        _get_latest_updated_at(Recipe, workspace_id),
        _get_latest_updated_at(CostVersion, workspace_id),
        _get_latest_updated_at(Customer, workspace_id),
        _get_latest_updated_at(Order, workspace_id),
        _get_latest_updated_at(Expense, workspace_id),
    )

    catalog = _max_dt(
        t_ingredients,
        t_presentations,
        t_price_records,
        t_suppliers,
        t_units,
    )
    recipes = _max_dt(
        t_recipes,
        t_cost_versions,
        catalog,
    )
    customers = _max_dt(
        t_customers,
        t_orders,
    )
    orders = _max_dt(
        t_orders,
        t_customers,
        t_recipes,
    )
    home = _max_dt(
        catalog,
        recipes,
        customers,
        orders,
        t_expenses,
    )

    return ChangesResponse(
        home=home,
        orders=orders,
        recipes=recipes,
        catalog=catalog,
        customers=customers,
    )
