import asyncio
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from bson.decimal128 import Decimal128

from app.models.cost_version import CostVersion
from app.models.customer import Customer
from app.models.ingredient import Ingredient
from app.models.order import Expense, Order
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.supplier import Supplier
from app.models.unit import Unit
from app.models.workspace import Workspace


def format_datetime(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    dt = dt.replace(tzinfo=UTC) if dt.tzinfo is None else dt.astimezone(UTC)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def format_decimal(val: Any) -> str:
    if val is None:
        return ""
    if isinstance(val, Decimal128):
        val = val.to_decimal()
    elif not isinstance(val, Decimal):
        val = Decimal(str(val))
    return format(val, "f")


async def export_workspace_data(workspace: Workspace) -> dict[str, Any]:
    workspace_id = str(workspace.id)

    # 1 consulta por colección (11 en total), ejecutadas en paralelo
    (
        system_units,
        workspace_units,
        ingredients,
        suppliers,
        presentations,
        price_records,
        recipes,
        cost_versions,
        customers,
        orders,
        expenses,
    ) = await asyncio.gather(
        Unit.find(Unit.workspace_id == None).to_list(),  # noqa: E711
        Unit.find(Unit.workspace_id == workspace_id).to_list(),
        Ingredient.find(Ingredient.workspace_id == workspace_id).to_list(),
        Supplier.find(Supplier.workspace_id == workspace_id).to_list(),
        Presentation.find(Presentation.workspace_id == workspace_id).to_list(),
        PriceRecord.find(PriceRecord.workspace_id == workspace_id).to_list(),
        Recipe.find(Recipe.workspace_id == workspace_id).to_list(),
        CostVersion.find(CostVersion.workspace_id == workspace_id).to_list(),
        Customer.find(Customer.workspace_id == workspace_id).to_list(),
        Order.find(Order.workspace_id == workspace_id).to_list(),
        Expense.find(Expense.workspace_id == workspace_id).to_list(),
    )

    # Mapa de unidades del sistema a sys.<abreviatura>
    sys_unit_map: dict[str, str] = {
        str(u.id): f"sys.{u.abbreviation.replace(' ', '_')}"
        for u in system_units
    }

    # Mapa de recetas para orders[].items[].recipe_name
    recipe_name_by_id: dict[str, str] = {str(r.id): r.name for r in recipes}

    settings = {
        "name": workspace.name,
        "currency": workspace.currency,
        "timezone": workspace.timezone,
        "default_margin_percent": workspace.default_margin_percent,
        "price_stale_days": workspace.price_stale_days,
    }

    exported_units = [
        {
            "id": str(u.id),
            "name": u.name,
            "abbreviation": u.abbreviation,
            "base_unit": str(u.base_unit),
            "factor_to_base": format_decimal(u.factor_to_base),
            "created_at": format_datetime(u.created_at),
            "updated_at": format_datetime(u.updated_at),
            "deleted_at": format_datetime(u.deleted_at),
        }
        for u in workspace_units
    ]

    exported_ingredients = [
        {
            "id": str(i.id),
            "name": i.name,
            "base_unit": str(i.base_unit),
            "group": i.group,
            "notes": i.notes,
            "conversions": [
                {
                    "unit_id": sys_unit_map.get(str(c.unit_id), str(c.unit_id)),
                    "quantity_in_base": format_decimal(c.quantity_in_base),
                }
                for c in i.conversions
            ],
            "photo_id": None,
            "created_at": format_datetime(i.created_at),
            "updated_at": format_datetime(i.updated_at),
            "deleted_at": format_datetime(i.deleted_at),
        }
        for i in ingredients
    ]

    exported_suppliers = [
        {
            "id": str(s.id),
            "name": s.name,
            "notes": s.notes,
            "created_at": format_datetime(s.created_at),
            "updated_at": format_datetime(s.updated_at),
            "deleted_at": format_datetime(s.deleted_at),
        }
        for s in suppliers
    ]

    exported_presentations = [
        {
            "id": str(p.id),
            "ingredient_id": str(p.ingredient_id),
            "brand": p.brand,
            "supplier_id": str(p.supplier_id) if p.supplier_id else None,
            "package_quantity": format_decimal(p.package_quantity),
            "barcode": p.barcode,
            "photo_id": None,
            "created_at": format_datetime(p.created_at),
            "updated_at": format_datetime(p.updated_at),
            "deleted_at": format_datetime(p.deleted_at),
        }
        for p in presentations
    ]

    exported_price_records = [
        {
            "id": str(pr.id),
            "presentation_id": str(pr.presentation_id),
            "price_cents": int(pr.price_cents),
            "recorded_at": format_datetime(pr.recorded_at),
            "note": pr.note,
            "created_at": format_datetime(pr.created_at),
            "updated_at": format_datetime(pr.updated_at),
            "deleted_at": format_datetime(pr.deleted_at),
        }
        for pr in price_records
    ]

    exported_recipes = [
        {
            "id": str(r.id),
            "name": r.name,
            "description": r.description,
            "items": [
                {
                    "kind": str(item.kind),
                    "ref_id": str(item.ref_id),
                    "quantity": format_decimal(item.quantity),
                    "unit_id": (
                        sys_unit_map.get(str(item.unit_id), str(item.unit_id))
                        if item.unit_id
                        else None
                    ),
                    "pinned_presentation_id": (
                        str(item.pinned_presentation_id)
                        if item.pinned_presentation_id
                        else None
                    ),
                }
                for item in r.items
            ],
            "extra_costs": [
                {
                    "name": ec.name,
                    "cost_cents": int(ec.cost_cents),
                }
                for ec in r.extra_costs
            ],
            "yield_quantity": format_decimal(r.yield_quantity),
            "yield_unit": str(r.yield_unit),
            "servings": r.servings,
            "margin_percent": r.margin_percent,
            "photo_id": None,
            "created_at": format_datetime(r.created_at),
            "updated_at": format_datetime(r.updated_at),
            "deleted_at": format_datetime(r.deleted_at),
        }
        for r in recipes
    ]

    exported_cost_versions = [
        {
            "id": str(cv.id),
            "recipe_id": str(cv.recipe_id),
            "name": cv.name,
            "choices": [
                {
                    "ingredient_id": str(c.ingredient_id),
                    "presentation_id": str(c.presentation_id),
                }
                for c in cv.choices
            ],
            "created_at": format_datetime(cv.created_at),
            "updated_at": format_datetime(cv.updated_at),
            "deleted_at": format_datetime(cv.deleted_at),
        }
        for cv in cost_versions
    ]

    exported_customers = [
        {
            "id": str(c.id),
            "name": c.name,
            "phone": c.phone,
            "notes": c.notes,
            "created_at": format_datetime(c.created_at),
            "updated_at": format_datetime(c.updated_at),
            "deleted_at": format_datetime(c.deleted_at),
        }
        for c in customers
    ]

    exported_orders = [
        {
            "id": str(o.id),
            "customer_id": str(o.customer_id) if o.customer_id else None,
            "customer_name": o.customer_name,
            "customer_phone": o.customer_phone,
            "delivery_at": format_datetime(o.delivery_at),
            "items": [
                {
                    "recipe_id": str(item.recipe_id),
                    "recipe_name": recipe_name_by_id.get(str(item.recipe_id), ""),
                    "sold_by": str(item.sold_by),
                    "unit_label": str(item.unit_label) if item.unit_label else None,
                    "quantity": format_decimal(item.quantity),
                    "unit_price_cents": int(item.unit_price_cents),
                    "unit_cost_cents_snapshot": int(item.unit_cost_cents_snapshot),
                }
                for item in o.items
            ],
            "payments": [
                {
                    "id": str(p.id),
                    "amount_cents": int(p.amount_cents),
                    "paid_at": format_datetime(p.paid_at),
                    "method": p.method,
                }
                for p in o.payments
            ],
            "status": str(o.status),
            "notes": o.notes,
            "created_at": format_datetime(o.created_at),
            "updated_at": format_datetime(o.updated_at),
            "deleted_at": format_datetime(o.deleted_at),
        }
        for o in orders
    ]

    exported_expenses = [
        {
            "id": str(e.id),
            "description": e.description,
            "amount_cents": int(e.amount_cents),
            "spent_at": format_datetime(e.spent_at),
            "category": e.category,
            "supplier_id": str(e.supplier_id) if e.supplier_id else None,
            "created_at": format_datetime(e.created_at),
            "updated_at": format_datetime(e.updated_at),
            "deleted_at": format_datetime(e.deleted_at),
        }
        for e in expenses
    ]

    return {
        "schema_version": 1,
        "exported_at": format_datetime(datetime.now(UTC)),
        "device_id": "server-export",
        "settings": settings,
        "units": exported_units,
        "ingredients": exported_ingredients,
        "suppliers": exported_suppliers,
        "presentations": exported_presentations,
        "price_records": exported_price_records,
        "recipes": exported_recipes,
        "cost_versions": exported_cost_versions,
        "customers": exported_customers,
        "orders": exported_orders,
        "expenses": exported_expenses,
    }
