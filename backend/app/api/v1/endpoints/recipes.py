from fastapi import APIRouter, Query, status

from app.core.deps import CurrentWorkspace
from app.schemas.cost_version import (
    CostVersionCompareResponse,
    CostVersionCreate,
    CostVersionResponse,
    CostVersionUpdate,
)
from app.schemas.pagination import PaginatedResponse
from app.schemas.recipe import (
    RecipeCostResponse,
    RecipeCreate,
    RecipeListItemResponse,
    RecipeResponse,
    RecipeUpdate,
    UsableSubrecipeResponse,
)
from app.services.cost_version_service import (
    compare_cost_versions,
    create_cost_version,
    delete_cost_version,
    get_cost_version,
    list_cost_versions,
    update_cost_version,
)
from app.services.costing_service import calculate_recipe_cost
from app.services.recipe_service import (
    create_recipe,
    delete_recipe,
    get_recipe,
    get_usable_as_subrecipe,
    list_recipes,
    serialize_recipe,
    update_recipe,
)

router = APIRouter()


@router.get("/", response_model=PaginatedResponse[RecipeListItemResponse])
async def list_recipes_endpoint(
    workspace: CurrentWorkspace,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    q: str | None = None,
):
    ws_id = str(workspace.id)
    items, total, pages = await list_recipes(
        ws_id,
        page=page,
        limit=limit,
        q=q,
    )
    return PaginatedResponse(
        items=items,
        total=total,
        page=page,
        limit=limit,
        pages=pages,
    )


@router.post("/", response_model=RecipeResponse, status_code=status.HTTP_201_CREATED)
async def create_recipe_endpoint(
    data: RecipeCreate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    recipe = await create_recipe(ws_id, data)
    return await serialize_recipe(recipe)


@router.get("/{id}/usable-as-subrecipe", response_model=list[UsableSubrecipeResponse])
async def usable_as_subrecipe_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    return await get_usable_as_subrecipe(ws_id, id)


@router.get("/{id}/cost", response_model=RecipeCostResponse)
async def get_recipe_cost_endpoint(
    id: str,
    workspace: CurrentWorkspace,
    version_id: str | None = None,
):
    ws_id = str(workspace.id)
    recipe = await get_recipe(ws_id, id)
    version = None
    if version_id is not None:
        version = await get_cost_version(ws_id, id, version_id)
    return await calculate_recipe_cost(ws_id, recipe, version=version)


@router.get("/{id}/versions/", response_model=list[CostVersionResponse])
async def list_cost_versions_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    return await list_cost_versions(ws_id, id)


@router.post(
    "/{id}/versions/",
    response_model=CostVersionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_cost_version_endpoint(
    id: str,
    data: CostVersionCreate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    return await create_cost_version(ws_id, id, data)


@router.get("/{id}/versions/compare", response_model=list[CostVersionCompareResponse])
async def compare_cost_versions_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    return await compare_cost_versions(ws_id, id)


@router.patch("/{id}/versions/{version_id}", response_model=CostVersionResponse)
async def update_cost_version_endpoint(
    id: str,
    version_id: str,
    data: CostVersionUpdate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    return await update_cost_version(ws_id, id, version_id, data)


@router.delete("/{id}/versions/{version_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_cost_version_endpoint(
    id: str,
    version_id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    await delete_cost_version(ws_id, id, version_id)
    return None


@router.get("/{id}", response_model=RecipeResponse)
async def get_recipe_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    recipe = await get_recipe(ws_id, id)
    return await serialize_recipe(recipe)


@router.patch("/{id}", response_model=RecipeResponse)
async def update_recipe_endpoint(
    id: str,
    data: RecipeUpdate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    recipe = await update_recipe(ws_id, id, data)
    return await serialize_recipe(recipe)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_recipe_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    await delete_recipe(ws_id, id)
    return None
