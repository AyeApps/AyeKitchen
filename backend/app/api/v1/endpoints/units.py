from fastapi import APIRouter, status

from app.core.deps import CurrentWorkspace
from app.models.unit import Unit
from app.schemas.unit import UnitCreate, UnitResponse, UnitUpdate
from app.services.unit_service import (
    create_unit,
    delete_unit,
    get_unit,
    list_units,
    update_unit,
)

router = APIRouter()


def _serialize_unit(unit: Unit) -> UnitResponse:
    return UnitResponse(
        id=str(unit.id),
        name=unit.name,
        abbreviation=unit.abbreviation,
        base_unit=unit.base_unit,
        factor_to_base=str(unit.factor_to_base),
        is_system=unit.workspace_id is None,
    )


@router.get("/", response_model=list[UnitResponse])
async def list_units_endpoint(workspace: CurrentWorkspace):
    units = await list_units(str(workspace.id))
    return [_serialize_unit(u) for u in units]


@router.post("/", response_model=UnitResponse, status_code=status.HTTP_201_CREATED)
async def create_unit_endpoint(data: UnitCreate, workspace: CurrentWorkspace):
    unit = await create_unit(str(workspace.id), data)
    return _serialize_unit(unit)


@router.get("/{id}", response_model=UnitResponse)
async def get_unit_endpoint(id: str, workspace: CurrentWorkspace):
    unit = await get_unit(str(workspace.id), id)
    return _serialize_unit(unit)


@router.patch("/{id}", response_model=UnitResponse)
async def update_unit_endpoint(id: str, data: UnitUpdate, workspace: CurrentWorkspace):
    unit = await update_unit(str(workspace.id), id, data)
    return _serialize_unit(unit)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_unit_endpoint(id: str, workspace: CurrentWorkspace):
    await delete_unit(str(workspace.id), id)
    return None
