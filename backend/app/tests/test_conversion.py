from decimal import Decimal

import pytest

from app.core.errors import AppError
from app.models.ingredient import Ingredient, IngredientConversion
from app.models.unit import BaseUnit, Unit
from app.services.conversion_service import (
    convert_between_base_units,
    convert_to_base,
)


@pytest.mark.asyncio
async def test_conversion_three_contract_examples():
    # Find system unit "taza"
    taza = await Unit.find_one(Unit.abbreviation == "tz", Unit.workspace_id == None)  # noqa: E711
    assert taza is not None
    taza_id = str(taza.id)

    # 1. Harina (g) con conversión propia taza = 125 g: 2 tazas -> 250 g
    harina_con_conv = Ingredient(
        workspace_id="ws_1",
        name="Harina de trigo",
        base_unit=BaseUnit.g,
        conversions=[IngredientConversion(unit_id=taza_id, quantity_in_base="125")],
    )
    res1 = await convert_to_base("ws_1", Decimal("2"), taza_id, harina_con_conv)
    assert res1 == Decimal("250")

    # 2. Leche (ml) sin conversión propia: 2 tazas -> 480 ml (vía tabla general factor 240)
    leche = Ingredient(
        workspace_id="ws_1",
        name="Leche entera",
        base_unit=BaseUnit.ml,
        conversions=[],
    )
    res2 = await convert_to_base("ws_1", Decimal("2"), taza_id, leche)
    assert res2 == Decimal("480")

    # 3. Harina sin conversión propia: 2 tazas -> UNIT_NOT_CONVERTIBLE (422)
    harina_sin_conv = Ingredient(
        workspace_id="ws_1",
        name="Harina de trigo",
        base_unit=BaseUnit.g,
        conversions=[],
    )
    with pytest.raises(AppError) as exc_info:
        await convert_to_base("ws_1", Decimal("2"), taza_id, harina_sin_conv)

    assert exc_info.value.status_code == 422
    assert exc_info.value.code == "UNIT_NOT_CONVERTIBLE"
    detail = exc_info.value.detail
    assert "taza" in detail
    assert "g" in detail
    assert "Harina de trigo" in detail


@pytest.mark.asyncio
async def test_convert_to_base_empty_unit_id():
    harina = Ingredient(
        workspace_id="ws_1",
        name="Harina",
        base_unit=BaseUnit.g,
    )
    # None unit_id
    assert await convert_to_base("ws_1", Decimal("150"), None, harina) == Decimal("150")
    # Empty string unit_id
    assert await convert_to_base("ws_1", Decimal("150"), "", harina) == Decimal("150")


@pytest.mark.asyncio
async def test_convert_to_base_invalid_reference():
    harina = Ingredient(
        workspace_id="ws_1",
        name="Harina",
        base_unit=BaseUnit.g,
    )

    # Non-existent unit id
    with pytest.raises(AppError) as exc:
        await convert_to_base("ws_1", Decimal("2"), "507f1f77bcf86cd799439011", harina)
    assert exc.value.status_code == 422
    assert exc.value.code == "INVALID_REFERENCE"

    # Unit of another workspace
    other_unit = Unit(
        workspace_id="ws_2",
        name="Jarra",
        abbreviation="jr",
        base_unit=BaseUnit.ml,
        factor_to_base=Decimal("1500"),
    )
    await other_unit.insert()

    with pytest.raises(AppError) as exc2:
        await convert_to_base("ws_1", Decimal("1"), str(other_unit.id), harina)
    assert exc2.value.status_code == 422
    assert exc2.value.code == "INVALID_REFERENCE"


@pytest.mark.asyncio
async def test_convert_between_base_units():
    kg = await Unit.find_one(Unit.abbreviation == "kg", Unit.workspace_id == None)  # noqa: E711
    tz = await Unit.find_one(Unit.abbreviation == "tz", Unit.workspace_id == None)  # noqa: E711
    doc = await Unit.find_one(Unit.abbreviation == "doc", Unit.workspace_id == None)  # noqa: E711

    # Empty unit_id returns quantity
    assert await convert_between_base_units("ws_1", Decimal("500"), None, BaseUnit.g) == Decimal("500")

    # Same base unit: 2.5 kg -> 2500 g
    res_kg = await convert_between_base_units("ws_1", Decimal("2.5"), str(kg.id), BaseUnit.g)
    assert res_kg == Decimal("2500.0")

    # Same base unit: 3 tz -> 720 ml
    res_tz = await convert_between_base_units("ws_1", Decimal("3"), str(tz.id), BaseUnit.ml)
    assert res_tz == Decimal("720")

    # Same base unit: 2 doc -> 24 pz
    res_doc = await convert_between_base_units("ws_1", Decimal("2"), str(doc.id), BaseUnit.pz)
    assert res_doc == Decimal("24")

    # Different base unit: tz (ml) to g -> UNIT_NOT_CONVERTIBLE
    with pytest.raises(AppError) as exc:
        await convert_between_base_units("ws_1", Decimal("1"), str(tz.id), BaseUnit.g)
    assert exc.value.status_code == 422
    assert exc.value.code == "UNIT_NOT_CONVERTIBLE"

    # Invalid unit reference
    with pytest.raises(AppError) as exc2:
        await convert_between_base_units("ws_1", Decimal("1"), "invalid_id", BaseUnit.g)
    assert exc2.value.status_code == 422
    assert exc2.value.code == "INVALID_REFERENCE"
