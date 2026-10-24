import math
import re
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from bson import ObjectId

from app.core.errors import AppError
from app.models.base import parse_decimal
from app.models.ingredient import Ingredient, IngredientConversion
from app.models.presentation import Presentation
from app.models.recipe import Recipe
from app.models.unit import Unit
from app.schemas.ingredient import IngredientConversionInput, IngredientCreate, IngredientUpdate


async def validate_conversions(workspace_id: str, conversions: list[IngredientConversionInput]) -> None:
    seen_units: set[str] = set()
    for c in conversions:
        if c.unit_id in seen_units:
            raise AppError(
                status_code=422,
                detail=f"Unidad duplicada en conversiones: {c.unit_id}",
                code="INVALID_REFERENCE",
            )
        seen_units.add(c.unit_id)

        if parse_decimal(c.quantity_in_base) <= Decimal("0"):
            raise AppError(
                status_code=422,
                detail="La cantidad debe ser mayor que cero",
                code="INVALID_REFERENCE",
            )

        if not ObjectId.is_valid(c.unit_id):
            raise AppError(
                status_code=422,
                detail=f"Unidad no encontrada: {c.unit_id}",
                code="INVALID_REFERENCE",
            )

        unit = await Unit.get(c.unit_id)
        if not unit or unit.deleted_at is not None:
            raise AppError(
                status_code=422,
                detail=f"Unidad no encontrada: {c.unit_id}",
                code="INVALID_REFERENCE",
            )

        if unit.workspace_id is not None and unit.workspace_id != workspace_id:
            raise AppError(
                status_code=422,
                detail=f"Unidad no encontrada: {c.unit_id}",
                code="INVALID_REFERENCE",
            )


async def list_ingredients(
    workspace_id: str,
    page: int = 1,
    limit: int = 20,
    q: str | None = None,
    group: str | None = None,
) -> tuple[list[Ingredient], int, int]:
    limit = min(max(1, limit), 100)
    page = max(1, page)

    filters: dict[str, Any] = {
        "workspace_id": workspace_id,
        "deleted_at": None,
    }

    if group:
        filters["group"] = group

    if q and q.strip():
        filters["name"] = {"$regex": re.escape(q.strip()), "$options": "i"}

    total = await Ingredient.find(filters).count()
    pages = math.ceil(total / limit) if total > 0 else 0
    skip = (page - 1) * limit

    items = await Ingredient.find(filters).sort("+name").skip(skip).limit(limit).to_list()
    return items, total, pages


async def get_ingredient(workspace_id: str, ingredient_id: str) -> Ingredient:
    if not ObjectId.is_valid(ingredient_id):
        raise AppError(status_code=404, detail="Ingrediente no encontrado", code="NOT_FOUND")

    ingredient = await Ingredient.get(ingredient_id)
    if not ingredient or ingredient.deleted_at is not None:
        raise AppError(status_code=404, detail="Ingrediente no encontrado", code="NOT_FOUND")

    if ingredient.workspace_id != workspace_id:
        raise AppError(status_code=404, detail="Ingrediente no encontrado", code="NOT_FOUND")

    return ingredient


async def create_ingredient(workspace_id: str, data: IngredientCreate) -> Ingredient:
    existing = await Ingredient.find_one(
        Ingredient.workspace_id == workspace_id,
        Ingredient.deleted_at == None,  # noqa: E711
        {"name": {"$regex": f"^{re.escape(data.name.strip())}$", "$options": "i"}},
    )
    if existing:
        raise AppError(
            status_code=409,
            detail="Ya existe un ingrediente con ese nombre",
            code="DUPLICATE_NAME",
        )

    await validate_conversions(workspace_id, data.conversions)

    ingredient = Ingredient(
        workspace_id=workspace_id,
        name=data.name.strip(),
        base_unit=data.base_unit,
        group=data.group,
        notes=data.notes,
        conversions=[
            IngredientConversion(
                unit_id=c.unit_id,
                quantity_in_base=c.quantity_in_base,
            )
            for c in data.conversions
        ],
    )
    await ingredient.insert()
    return ingredient


async def update_ingredient(workspace_id: str, ingredient_id: str, data: IngredientUpdate) -> Ingredient:
    ingredient = await get_ingredient(workspace_id, ingredient_id)

    if data.name is not None:
        existing = await Ingredient.find_one(
            Ingredient.workspace_id == workspace_id,
            Ingredient.deleted_at == None,  # noqa: E711
            Ingredient.id != ingredient.id,
            {"name": {"$regex": f"^{re.escape(data.name.strip())}$", "$options": "i"}},
        )
        if existing:
            raise AppError(
                status_code=409,
                detail="Ya existe un ingrediente con ese nombre",
                code="DUPLICATE_NAME",
            )
        ingredient.name = data.name.strip()

    if data.base_unit is not None and data.base_unit != ingredient.base_unit:
        presentation = await Presentation.find_one(
            Presentation.workspace_id == workspace_id,
            Presentation.ingredient_id == str(ingredient.id),
            Presentation.deleted_at == None,  # noqa: E711
        )
        if presentation:
            raise AppError(
                status_code=409,
                detail="No se puede cambiar la unidad base de un ingrediente con presentaciones activas",
                code="IN_USE",
            )
        in_recipe = await Recipe.find_one(
            Recipe.workspace_id == workspace_id,
            Recipe.deleted_at == None,  # noqa: E711
            {"items": {"$elemMatch": {"kind": "ingredient", "ref_id": str(ingredient.id)}}},
        )
        if in_recipe:
            raise AppError(
                status_code=409,
                detail="El ingrediente está en uso en recetas activas",
                code="IN_USE",
            )
        ingredient.base_unit = data.base_unit

    if data.conversions is not None:
        current_unit_ids = {c.unit_id for c in ingredient.conversions}
        new_unit_ids = {c.unit_id for c in data.conversions}
        removed_unit_ids = current_unit_ids - new_unit_ids
        if removed_unit_ids:
            in_recipe = await Recipe.find_one(
                Recipe.workspace_id == workspace_id,
                Recipe.deleted_at == None,  # noqa: E711
                {
                    "items": {
                        "$elemMatch": {
                            "kind": "ingredient",
                            "ref_id": str(ingredient.id),
                            "unit_id": {"$in": list(removed_unit_ids)},
                        }
                    }
                },
            )
            if in_recipe:
                raise AppError(
                    status_code=409,
                    detail="La conversión está en uso en recetas activas",
                    code="IN_USE",
                )

        await validate_conversions(workspace_id, data.conversions)
        ingredient.conversions = [
            IngredientConversion(
                unit_id=c.unit_id,
                quantity_in_base=c.quantity_in_base,
            )
            for c in data.conversions
        ]

    if "group" in data.model_fields_set:
        ingredient.group = data.group
    if "notes" in data.model_fields_set:
        ingredient.notes = data.notes

    ingredient.updated_at = datetime.now(UTC)
    await ingredient.save()
    return ingredient


async def delete_ingredient(workspace_id: str, ingredient_id: str) -> None:
    ingredient = await get_ingredient(workspace_id, ingredient_id)

    in_recipe = await Recipe.find_one(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
        {"items": {"$elemMatch": {"kind": "ingredient", "ref_id": str(ingredient.id)}}},
    )
    if in_recipe:
        raise AppError(
            status_code=409,
            detail="El ingrediente está en uso en recetas activas",
            code="IN_USE",
        )

    await ingredient.soft_delete()

    presentations = await Presentation.find(
        Presentation.workspace_id == workspace_id,
        Presentation.ingredient_id == str(ingredient.id),
        Presentation.deleted_at == None,  # noqa: E711
    ).to_list()
    for p in presentations:
        await p.soft_delete()
