import math
from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, NamedTuple

from bson import ObjectId

from app.core.errors import AppError
from app.models.base import parse_decimal
from app.models.ingredient import Ingredient
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.supplier import Supplier
from app.schemas.presentation import (
    PresentationCreate,
    PresentationUpdate,
    PriceRecordCreate,
)
from app.services.conversion_service import convert_to_base


class CurrentPresentation(NamedTuple):
    presentation: Presentation
    price_record: PriceRecord


def compute_cost_per_base_unit(price_cents: int | None, package_quantity: Any) -> str | None:
    if price_cents is None:
        return None
    qty = parse_decimal(package_quantity)
    if qty <= Decimal("0"):
        return None
    cost = Decimal(price_cents) / qty
    return str(cost.quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP))


async def get_latest_price(
    workspace_id: str,
    presentation_id: str,
) -> PriceRecord | None:
    records = await PriceRecord.find(
        PriceRecord.workspace_id == workspace_id,
        PriceRecord.presentation_id == presentation_id,
        PriceRecord.deleted_at == None,  # noqa: E711
    ).sort("-recorded_at", "-created_at").limit(1).to_list()
    return records[0] if records else None


async def get_current_presentation(
    workspace_id: str,
    ingredient_id: str,
) -> CurrentPresentation | None:
    presentations = await Presentation.find(
        Presentation.workspace_id == workspace_id,
        Presentation.ingredient_id == ingredient_id,
        Presentation.deleted_at == None,  # noqa: E711
    ).to_list()
    if not presentations:
        return None

    pres_ids = [str(p.id) for p in presentations]
    price_records = await PriceRecord.find(
        PriceRecord.workspace_id == workspace_id,
        PriceRecord.deleted_at == None,  # noqa: E711
        {"presentation_id": {"$in": pres_ids}},
    ).sort("-recorded_at", "-created_at").to_list()

    latest_by_pres: dict[str, PriceRecord] = {}
    for pr in price_records:
        if pr.presentation_id not in latest_by_pres:
            latest_by_pres[pr.presentation_id] = pr

    candidates: list[tuple[Presentation, PriceRecord]] = []
    for p in presentations:
        pr = latest_by_pres.get(str(p.id))
        if pr is not None:
            candidates.append((p, pr))

    if not candidates:
        return None

    candidates.sort(
        key=lambda c: (c[1].recorded_at, c[0].created_at),
        reverse=True,
    )
    winner = candidates[0]
    return CurrentPresentation(presentation=winner[0], price_record=winner[1])


async def list_presentations(
    workspace_id: str,
    page: int = 1,
    limit: int = 20,
    ingredient_id: str | None = None,
) -> tuple[list[Presentation], dict[str, PriceRecord], int, int]:
    limit = min(max(1, limit), 100)
    page = max(1, page)

    filters: dict[str, Any] = {
        "workspace_id": workspace_id,
        "deleted_at": None,
    }
    if ingredient_id:
        filters["ingredient_id"] = ingredient_id

    presentations = await Presentation.find(filters).to_list()

    price_agg = await PriceRecord.get_motor_collection().aggregate([
        {"$match": {"workspace_id": workspace_id, "deleted_at": None}},
        {"$sort": {"recorded_at": -1, "created_at": -1}},
        {"$group": {"_id": "$presentation_id", "latest_at": {"$first": "$recorded_at"}}},
    ]).to_list(length=None)
    latest_at_map = {doc["_id"]: doc["latest_at"] for doc in price_agg}

    presentations.sort(
        key=lambda p: (
            1 if str(p.id) in latest_at_map else 0,
            latest_at_map.get(str(p.id), datetime.min.replace(tzinfo=UTC)),
            p.created_at,
        ),
        reverse=True,
    )

    total = len(presentations)
    pages = math.ceil(total / limit) if total > 0 else 0
    skip = (page - 1) * limit
    page_items = presentations[skip : skip + limit]

    page_ids = [str(p.id) for p in page_items]
    price_records = await PriceRecord.find(
        PriceRecord.workspace_id == workspace_id,
        PriceRecord.deleted_at == None,  # noqa: E711
        {"presentation_id": {"$in": page_ids}},
    ).sort("-recorded_at", "-created_at").to_list()

    latest_price_map: dict[str, PriceRecord] = {}
    for pr in price_records:
        if pr.presentation_id not in latest_price_map:
            latest_price_map[pr.presentation_id] = pr

    return page_items, latest_price_map, total, pages


async def get_presentation(workspace_id: str, presentation_id: str) -> Presentation:
    if not ObjectId.is_valid(presentation_id):
        raise AppError(status_code=404, detail="Presentación no encontrada", code="NOT_FOUND")

    presentation = await Presentation.get(presentation_id)
    if not presentation or presentation.deleted_at is not None:
        raise AppError(status_code=404, detail="Presentación no encontrada", code="NOT_FOUND")

    if presentation.workspace_id != workspace_id:
        raise AppError(status_code=404, detail="Presentación no encontrada", code="NOT_FOUND")

    return presentation


async def create_presentation(workspace_id: str, data: PresentationCreate) -> Presentation:
    if not ObjectId.is_valid(data.ingredient_id):
        raise AppError(status_code=422, detail="Ingrediente no encontrado", code="INVALID_REFERENCE")

    ingredient = await Ingredient.find_one(
        Ingredient.id == ObjectId(data.ingredient_id),
        Ingredient.workspace_id == workspace_id,
        Ingredient.deleted_at == None,  # noqa: E711
    )
    if not ingredient:
        raise AppError(status_code=422, detail="Ingrediente no encontrado", code="INVALID_REFERENCE")

    if data.supplier_id is not None:
        if not ObjectId.is_valid(data.supplier_id):
            raise AppError(status_code=422, detail="Proveedor no encontrado", code="INVALID_REFERENCE")
        supplier = await Supplier.find_one(
            Supplier.id == ObjectId(data.supplier_id),
            Supplier.workspace_id == workspace_id,
            Supplier.deleted_at == None,  # noqa: E711
        )
        if not supplier:
            raise AppError(status_code=422, detail="Proveedor no encontrado", code="INVALID_REFERENCE")

    if data.package_unit_id:
        converted_qty = await convert_to_base(
            workspace_id,
            parse_decimal(data.package_quantity),
            data.package_unit_id,
            ingredient,
        )
    else:
        converted_qty = parse_decimal(data.package_quantity)

    if converted_qty <= Decimal("0"):
        raise AppError(status_code=422, detail="La cantidad debe ser mayor que cero", code="INVALID_REFERENCE")

    presentation = Presentation(
        workspace_id=workspace_id,
        ingredient_id=str(ingredient.id),
        brand=data.brand.strip(),
        supplier_id=data.supplier_id,
        package_quantity=converted_qty,
        barcode=data.barcode.strip() if data.barcode else None,
    )
    await presentation.insert()

    if data.price_cents is not None:
        record = PriceRecord(
            workspace_id=workspace_id,
            presentation_id=str(presentation.id),
            price_cents=data.price_cents,
            recorded_at=datetime.now(UTC),
        )
        await record.insert()

    return presentation


async def update_presentation(
    workspace_id: str,
    presentation_id: str,
    data: PresentationUpdate,
) -> Presentation:
    presentation = await get_presentation(workspace_id, presentation_id)

    if "brand" in data.model_fields_set and data.brand is not None:
        presentation.brand = data.brand.strip()

    if "supplier_id" in data.model_fields_set:
        if data.supplier_id is not None:
            if not ObjectId.is_valid(data.supplier_id):
                raise AppError(status_code=422, detail="Proveedor no encontrado", code="INVALID_REFERENCE")
            supplier = await Supplier.find_one(
                Supplier.id == ObjectId(data.supplier_id),
                Supplier.workspace_id == workspace_id,
                Supplier.deleted_at == None,  # noqa: E711
            )
            if not supplier:
                raise AppError(status_code=422, detail="Proveedor no encontrado", code="INVALID_REFERENCE")
            presentation.supplier_id = data.supplier_id
        else:
            presentation.supplier_id = None

    if "package_quantity" in data.model_fields_set and data.package_quantity is not None:
        if data.package_unit_id:
            ingredient = await Ingredient.find_one(
                Ingredient.id == ObjectId(presentation.ingredient_id),
                Ingredient.workspace_id == workspace_id,
                Ingredient.deleted_at == None,  # noqa: E711
            )
            if not ingredient:
                raise AppError(status_code=404, detail="Ingrediente no encontrado", code="NOT_FOUND")
            converted_qty = await convert_to_base(
                workspace_id,
                parse_decimal(data.package_quantity),
                data.package_unit_id,
                ingredient,
            )
        else:
            converted_qty = parse_decimal(data.package_quantity)

        if converted_qty <= Decimal("0"):
            raise AppError(status_code=422, detail="La cantidad debe ser mayor que cero", code="INVALID_REFERENCE")
        presentation.package_quantity = converted_qty

    if "barcode" in data.model_fields_set:
        presentation.barcode = data.barcode.strip() if data.barcode else None

    presentation.updated_at = datetime.now(UTC)
    await presentation.save()
    return presentation


async def delete_presentation(workspace_id: str, presentation_id: str) -> None:
    presentation = await get_presentation(workspace_id, presentation_id)

    in_recipe = await Recipe.find_one(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
        {"items.pinned_presentation_id": str(presentation.id)},
    )
    if in_recipe:
        raise AppError(
            status_code=409,
            detail="La presentación está en uso en recetas activas",
            code="IN_USE",
        )

    await presentation.soft_delete()


async def list_prices(workspace_id: str, presentation_id: str) -> list[PriceRecord]:
    presentation = await get_presentation(workspace_id, presentation_id)
    return await PriceRecord.find(
        PriceRecord.workspace_id == workspace_id,
        PriceRecord.presentation_id == str(presentation.id),
        PriceRecord.deleted_at == None,  # noqa: E711
    ).sort("-recorded_at", "-created_at").to_list()


async def add_price(
    workspace_id: str,
    presentation_id: str,
    data: PriceRecordCreate,
) -> PriceRecord:
    presentation = await get_presentation(workspace_id, presentation_id)

    recorded_at = data.recorded_at or datetime.now(UTC)
    if recorded_at.tzinfo is None:
        recorded_at = recorded_at.replace(tzinfo=UTC)

    record = PriceRecord(
        workspace_id=workspace_id,
        presentation_id=str(presentation.id),
        price_cents=data.price_cents,
        recorded_at=recorded_at,
        note=data.note,
    )
    await record.insert()
    return record
