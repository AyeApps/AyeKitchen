from fastapi import APIRouter, Query, status

from app.core.deps import CurrentWorkspace
from app.models.ingredient import Ingredient
from app.schemas.ingredient import (
    IngredientConversionResponse,
    IngredientCreate,
    IngredientResponse,
    IngredientUpdate,
)
from app.schemas.pagination import PaginatedResponse
from app.services.ingredient_service import (
    create_ingredient,
    delete_ingredient,
    get_ingredient,
    list_ingredients,
    update_ingredient,
)
from app.services.unit_service import get_units_map

router = APIRouter()


def _serialize_ingredient(ing: Ingredient, unit_map: dict[str, str]) -> IngredientResponse:
    conversions = [
        IngredientConversionResponse(
            unit_id=c.unit_id,
            unit_name=unit_map.get(c.unit_id, ""),
            quantity_in_base=str(c.quantity_in_base),
        )
        for c in ing.conversions
    ]
    return IngredientResponse(
        id=str(ing.id),
        name=ing.name,
        base_unit=ing.base_unit,
        group=ing.group,
        notes=ing.notes,
        conversions=conversions,
        created_at=ing.created_at,
        updated_at=ing.updated_at,
    )


@router.get("/", response_model=PaginatedResponse[IngredientResponse])
async def list_ingredients_endpoint(
    workspace: CurrentWorkspace,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    q: str | None = None,
    group: str | None = None,
):
    items, total, pages = await list_ingredients(
        str(workspace.id),
        page=page,
        limit=limit,
        q=q,
        group=group,
    )
    unit_ids = {c.unit_id for ing in items for c in ing.conversions}
    unit_map = await get_units_map(unit_ids)
    serialized = [_serialize_ingredient(ing, unit_map) for ing in items]
    return PaginatedResponse(
        items=serialized,
        total=total,
        page=page,
        limit=limit,
        pages=pages,
    )


@router.post("/", response_model=IngredientResponse, status_code=status.HTTP_201_CREATED)
async def create_ingredient_endpoint(data: IngredientCreate, workspace: CurrentWorkspace):
    ing = await create_ingredient(str(workspace.id), data)
    unit_map = await get_units_map({c.unit_id for c in ing.conversions})
    return _serialize_ingredient(ing, unit_map)


@router.get("/{id}", response_model=IngredientResponse)
async def get_ingredient_endpoint(id: str, workspace: CurrentWorkspace):
    ing = await get_ingredient(str(workspace.id), id)
    unit_map = await get_units_map({c.unit_id for c in ing.conversions})
    return _serialize_ingredient(ing, unit_map)


@router.patch("/{id}", response_model=IngredientResponse)
async def update_ingredient_endpoint(id: str, data: IngredientUpdate, workspace: CurrentWorkspace):
    ing = await update_ingredient(str(workspace.id), id, data)
    unit_map = await get_units_map({c.unit_id for c in ing.conversions})
    return _serialize_ingredient(ing, unit_map)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_ingredient_endpoint(id: str, workspace: CurrentWorkspace):
    await delete_ingredient(str(workspace.id), id)
    return None
