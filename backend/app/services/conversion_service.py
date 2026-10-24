from decimal import Decimal

from bson import ObjectId

from app.core.errors import AppError
from app.models.base import parse_decimal
from app.models.ingredient import Ingredient
from app.models.unit import BaseUnit, Unit


async def convert_to_base(
    workspace_id: str,
    quantity: Decimal,
    unit_id: str | None,
    ingredient: Ingredient,
) -> Decimal:
    """Convierte una cantidad en unit_id a la unidad base del ingrediente según las 4 reglas del contrato.

    1. unit_id vacío -> la cantidad ya está en la unidad base.
    2. El ingrediente tiene una conversión propia para ese unit_id -> quantity * quantity_in_base.
    3. La unidad tiene la misma base_unit que el ingrediente -> quantity * factor_to_base.
    4. Si no -> UNIT_NOT_CONVERTIBLE (422) con detail que nombre la unidad, la unidad base y el ingrediente.
    """
    qty = parse_decimal(quantity)

    # 1. unit_id vacío
    if not unit_id:
        return qty

    # 2. Conversión propia del ingrediente
    for c in ingredient.conversions:
        if c.unit_id == unit_id:
            return qty * parse_decimal(c.quantity_in_base)

    # 3 y 4. Buscar en tabla general de conversiones
    if not ObjectId.is_valid(unit_id):
        raise AppError(
            status_code=422,
            detail=f"Unidad no encontrada: {unit_id}",
            code="INVALID_REFERENCE",
        )

    unit = await Unit.get(unit_id)
    if not unit or unit.deleted_at is not None:
        raise AppError(
            status_code=422,
            detail=f"Unidad no encontrada: {unit_id}",
            code="INVALID_REFERENCE",
        )

    if unit.workspace_id is not None and unit.workspace_id != workspace_id:
        raise AppError(
            status_code=422,
            detail=f"Unidad no encontrada: {unit_id}",
            code="INVALID_REFERENCE",
        )

    # 3. Misma base_unit
    if unit.base_unit == ingredient.base_unit:
        return qty * parse_decimal(unit.factor_to_base)

    # 4. No convertible
    base_unit_str = ingredient.base_unit.value if hasattr(ingredient.base_unit, "value") else str(ingredient.base_unit)
    raise AppError(
        status_code=422,
        detail=f"Define cuántos {base_unit_str} tiene 1 {unit.name} de {ingredient.name}",
        code="UNIT_NOT_CONVERTIBLE",
    )


async def convert_between_base_units(
    workspace_id: str,
    quantity: Decimal,
    unit_id: str | None,
    target_base_unit: BaseUnit,
) -> Decimal:
    """Convierte una cantidad en unit_id a una BaseUnit destino usando solo la tabla general.

    Mismo base_unit multiplica por factor_to_base, distinto lanza UNIT_NOT_CONVERTIBLE,
    unit_id vacío devuelve la cantidad tal cual. Sin redondeos.
    """
    qty = parse_decimal(quantity)

    if not unit_id:
        return qty

    if not ObjectId.is_valid(unit_id):
        raise AppError(
            status_code=422,
            detail=f"Unidad no encontrada: {unit_id}",
            code="INVALID_REFERENCE",
        )

    unit = await Unit.get(unit_id)
    if not unit or unit.deleted_at is not None:
        raise AppError(
            status_code=422,
            detail=f"Unidad no encontrada: {unit_id}",
            code="INVALID_REFERENCE",
        )

    if unit.workspace_id is not None and unit.workspace_id != workspace_id:
        raise AppError(
            status_code=422,
            detail=f"Unidad no encontrada: {unit_id}",
            code="INVALID_REFERENCE",
        )

    if unit.base_unit == target_base_unit:
        return qty * parse_decimal(unit.factor_to_base)

    target_str = target_base_unit.value if hasattr(target_base_unit, "value") else str(target_base_unit)
    unit_base_str = unit.base_unit.value if hasattr(unit.base_unit, "value") else str(unit.base_unit)
    raise AppError(
        status_code=422,
        detail=f"No se puede convertir '{unit.name}' ({unit_base_str}) a '{target_str}'",
        code="UNIT_NOT_CONVERTIBLE",
    )
