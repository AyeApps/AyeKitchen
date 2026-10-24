from datetime import UTC, datetime
from decimal import Decimal

from bson import ObjectId

from app.core.errors import AppError
from app.models.base import parse_decimal
from app.models.ingredient import Ingredient
from app.models.recipe import Recipe
from app.models.unit import BaseUnit, Unit
from app.schemas.unit import UnitCreate, UnitUpdate

SYSTEM_UNITS: list[dict] = [
    {"name": "gramo", "abbreviation": "g", "base_unit": BaseUnit.g, "factor_to_base": Decimal("1")},
    {"name": "kilogramo", "abbreviation": "kg", "base_unit": BaseUnit.g, "factor_to_base": Decimal("1000")},
    {"name": "libra", "abbreviation": "lb", "base_unit": BaseUnit.g, "factor_to_base": Decimal("453.592")},
    {"name": "onza", "abbreviation": "oz", "base_unit": BaseUnit.g, "factor_to_base": Decimal("28.3495")},
    {"name": "mililitro", "abbreviation": "ml", "base_unit": BaseUnit.ml, "factor_to_base": Decimal("1")},
    {"name": "litro", "abbreviation": "l", "base_unit": BaseUnit.ml, "factor_to_base": Decimal("1000")},
    {"name": "taza", "abbreviation": "tz", "base_unit": BaseUnit.ml, "factor_to_base": Decimal("240")},
    {"name": "cucharada", "abbreviation": "cda", "base_unit": BaseUnit.ml, "factor_to_base": Decimal("15")},
    {"name": "cucharadita", "abbreviation": "cdta", "base_unit": BaseUnit.ml, "factor_to_base": Decimal("5")},
    {"name": "onza líquida", "abbreviation": "fl oz", "base_unit": BaseUnit.ml, "factor_to_base": Decimal("29.5735")},
    {"name": "pieza", "abbreviation": "pz", "base_unit": BaseUnit.pz, "factor_to_base": Decimal("1")},
    {"name": "docena", "abbreviation": "doc", "base_unit": BaseUnit.pz, "factor_to_base": Decimal("12")},
]


async def seed_system_units() -> None:
    for item in SYSTEM_UNITS:
        existing = await Unit.find_one(
            Unit.workspace_id == None,  # noqa: E711
            Unit.abbreviation == item["abbreviation"],
        )
        if existing is None:
            unit = Unit(
                workspace_id=None,
                name=item["name"],
                abbreviation=item["abbreviation"],
                base_unit=item["base_unit"],
                factor_to_base=item["factor_to_base"],
            )
            await unit.insert()


async def list_units(workspace_id: str) -> list[Unit]:
    units = await Unit.find(
        {
            "$or": [{"workspace_id": None}, {"workspace_id": workspace_id}],
            "deleted_at": None,
        }
    ).to_list()
    units.sort(key=lambda u: (str(u.base_unit.value if hasattr(u.base_unit, "value") else u.base_unit), parse_decimal(u.factor_to_base)))
    return units


async def get_unit(workspace_id: str, unit_id: str) -> Unit:
    if not ObjectId.is_valid(unit_id):
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    unit = await Unit.get(unit_id)
    if not unit or unit.deleted_at is not None:
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    if unit.workspace_id is not None and unit.workspace_id != workspace_id:
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    return unit


async def get_units_map(unit_ids: set[str]) -> dict[str, str]:
    if not unit_ids:
        return {}
    valid_ids = [ObjectId(uid) for uid in unit_ids if ObjectId.is_valid(uid)]
    if not valid_ids:
        return {}
    units = await Unit.find({"_id": {"$in": valid_ids}}).to_list()
    return {str(u.id): u.name for u in units}


async def create_unit(workspace_id: str, data: UnitCreate) -> Unit:
    active_units = await list_units(workspace_id)
    name_clean = data.name.strip().lower()
    abbr_clean = data.abbreviation.strip().lower()

    for u in active_units:
        if u.name.strip().lower() == name_clean or u.abbreviation.strip().lower() == abbr_clean:
            raise AppError(
                status_code=409,
                detail="Ya existe una unidad con ese nombre o abreviatura",
                code="DUPLICATE_NAME",
            )

    unit = Unit(
        workspace_id=workspace_id,
        name=data.name.strip(),
        abbreviation=data.abbreviation.strip(),
        base_unit=data.base_unit,
        factor_to_base=data.factor_to_base,
    )
    await unit.insert()
    return unit


async def update_unit(workspace_id: str, unit_id: str, data: UnitUpdate) -> Unit:
    if not ObjectId.is_valid(unit_id):
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    unit = await Unit.get(unit_id)
    if not unit or unit.deleted_at is not None:
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    if unit.workspace_id is None:
        raise AppError(
            status_code=403,
            detail="No se pueden editar unidades del sistema",
            code="SYSTEM_UNIT_READONLY",
        )

    if unit.workspace_id != workspace_id:
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    if data.name is not None or data.abbreviation is not None:
        active_units = await list_units(workspace_id)
        name_clean = data.name.strip().lower() if data.name is not None else unit.name.strip().lower()
        abbr_clean = data.abbreviation.strip().lower() if data.abbreviation is not None else unit.abbreviation.strip().lower()

        for u in active_units:
            if str(u.id) != str(unit.id) and (
                u.name.strip().lower() == name_clean or u.abbreviation.strip().lower() == abbr_clean
            ):
                raise AppError(
                    status_code=409,
                    detail="Ya existe una unidad con ese nombre o abreviatura",
                    code="DUPLICATE_NAME",
                )

    if data.base_unit is not None and data.base_unit != unit.base_unit:
        await _check_unit_not_in_use(workspace_id, str(unit.id))

    if data.name is not None:
        unit.name = data.name.strip()
    if data.abbreviation is not None:
        unit.abbreviation = data.abbreviation.strip()
    if data.base_unit is not None:
        unit.base_unit = data.base_unit
    if data.factor_to_base is not None:
        unit.factor_to_base = data.factor_to_base

    unit.updated_at = datetime.now(UTC)
    await unit.save()
    return unit


async def _check_unit_not_in_use(workspace_id: str, unit_id: str) -> None:
    in_ingredient = await Ingredient.find_one(
        Ingredient.workspace_id == workspace_id,
        Ingredient.deleted_at == None,  # noqa: E711
        {"conversions.unit_id": unit_id},
    )
    if in_ingredient:
        raise AppError(
            status_code=409,
            detail="La unidad está en uso en ingredientes",
            code="IN_USE",
        )

    in_recipe = await Recipe.find_one(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
        {"items.unit_id": unit_id},
    )
    if in_recipe:
        raise AppError(
            status_code=409,
            detail="La unidad está en uso en recetas",
            code="IN_USE",
        )


async def delete_unit(workspace_id: str, unit_id: str) -> None:
    if not ObjectId.is_valid(unit_id):
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    unit = await Unit.get(unit_id)
    if not unit or unit.deleted_at is not None:
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    if unit.workspace_id is None:
        raise AppError(
            status_code=403,
            detail="No se pueden eliminar unidades del sistema",
            code="SYSTEM_UNIT_READONLY",
        )

    if unit.workspace_id != workspace_id:
        raise AppError(status_code=404, detail="Unidad no encontrada", code="NOT_FOUND")

    await _check_unit_not_in_use(workspace_id, str(unit.id))

    await unit.soft_delete()
