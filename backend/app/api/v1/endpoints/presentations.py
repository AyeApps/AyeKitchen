from bson import ObjectId
from fastapi import APIRouter, Query, status

from app.core.deps import CurrentWorkspace
from app.core.errors import AppError
from app.models.ingredient import Ingredient
from app.models.presentation import Presentation, PriceRecord
from app.models.supplier import Supplier
from app.schemas.pagination import PaginatedResponse
from app.schemas.presentation import (
    PresentationCreate,
    PresentationResponse,
    PresentationUpdate,
    PriceRecordCreate,
    PriceRecordResponse,
)
from app.services.presentation_service import (
    add_price,
    compute_cost_per_base_unit,
    create_presentation,
    delete_presentation,
    get_current_presentation,
    get_latest_price,
    get_presentation,
    list_presentations,
    list_prices,
    update_presentation,
)

router = APIRouter()


def _serialize_presentation(
    presentation: Presentation,
    ingredient: Ingredient,
    supplier_name: str | None,
    latest_price: PriceRecord | None,
    is_current: bool,
) -> PresentationResponse:
    latest_cents = latest_price.price_cents if latest_price else None
    latest_at = latest_price.recorded_at if latest_price else None
    cost = compute_cost_per_base_unit(latest_cents, presentation.package_quantity)

    return PresentationResponse(
        id=str(presentation.id),
        ingredient_id=str(presentation.ingredient_id),
        ingredient_name=ingredient.name,
        brand=presentation.brand,
        supplier_id=presentation.supplier_id,
        supplier_name=supplier_name,
        package_quantity=str(presentation.package_quantity),
        base_unit=ingredient.base_unit,
        barcode=presentation.barcode,
        latest_price_cents=latest_cents,
        latest_price_at=latest_at,
        cost_per_base_unit=cost,
        is_current=is_current,
        created_at=presentation.created_at,
        updated_at=presentation.updated_at,
    )


async def _build_single_presentation_response(
    workspace_id: str,
    presentation: Presentation,
) -> PresentationResponse:
    ingredient = await Ingredient.get(presentation.ingredient_id)
    if not ingredient:
        raise AppError(status_code=404, detail="Ingrediente no encontrado", code="NOT_FOUND")

    supplier_name: str | None = None
    if presentation.supplier_id:
        supplier = await Supplier.get(presentation.supplier_id)
        if supplier and supplier.deleted_at is None and supplier.workspace_id == workspace_id:
            supplier_name = supplier.name

    latest_price = await get_latest_price(workspace_id, str(presentation.id))
    current_pres = await get_current_presentation(workspace_id, presentation.ingredient_id)
    is_current = current_pres is not None and str(current_pres.presentation.id) == str(presentation.id)

    return _serialize_presentation(
        presentation,
        ingredient,
        supplier_name,
        latest_price,
        is_current,
    )


@router.get("/", response_model=PaginatedResponse[PresentationResponse])
async def list_presentations_endpoint(
    workspace: CurrentWorkspace,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    ingredient_id: str | None = None,
):
    ws_id = str(workspace.id)
    items, latest_price_map, total, pages = await list_presentations(
        ws_id,
        page=page,
        limit=limit,
        ingredient_id=ingredient_id,
    )

    ing_ids = [ObjectId(p.ingredient_id) for p in items if ObjectId.is_valid(p.ingredient_id)]
    ingredients = await Ingredient.find({"_id": {"$in": ing_ids}}).to_list() if ing_ids else []
    ing_map = {str(i.id): i for i in ingredients}

    supp_ids = [ObjectId(p.supplier_id) for p in items if p.supplier_id and ObjectId.is_valid(p.supplier_id)]
    suppliers = await Supplier.find({"_id": {"$in": supp_ids}}).to_list() if supp_ids else []
    supp_map = {str(s.id): s.name for s in suppliers if s.deleted_at is None and s.workspace_id == ws_id}

    unique_ing_ids = {p.ingredient_id for p in items}
    current_pres_map: dict[str, str | None] = {}
    for i_id in unique_ing_ids:
        curr = await get_current_presentation(ws_id, i_id)
        current_pres_map[i_id] = str(curr.presentation.id) if curr else None

    serialized: list[PresentationResponse] = []
    for p in items:
        ing = ing_map.get(p.ingredient_id)
        if not ing:
            continue
        supp_name = supp_map.get(p.supplier_id) if p.supplier_id else None
        latest_pr = latest_price_map.get(str(p.id))
        is_curr = current_pres_map.get(p.ingredient_id) == str(p.id)
        serialized.append(
            _serialize_presentation(
                p,
                ing,
                supp_name,
                latest_pr,
                is_curr,
            )
        )

    return PaginatedResponse(
        items=serialized,
        total=total,
        page=page,
        limit=limit,
        pages=pages,
    )


@router.post("/", response_model=PresentationResponse, status_code=status.HTTP_201_CREATED)
async def create_presentation_endpoint(
    data: PresentationCreate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    presentation = await create_presentation(ws_id, data)
    return await _build_single_presentation_response(ws_id, presentation)


@router.get("/{id}", response_model=PresentationResponse)
async def get_presentation_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    presentation = await get_presentation(ws_id, id)
    return await _build_single_presentation_response(ws_id, presentation)


@router.patch("/{id}", response_model=PresentationResponse)
async def update_presentation_endpoint(
    id: str,
    data: PresentationUpdate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    presentation = await update_presentation(ws_id, id, data)
    return await _build_single_presentation_response(ws_id, presentation)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_presentation_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    await delete_presentation(ws_id, id)
    return None


@router.get("/{id}/prices", response_model=list[PriceRecordResponse])
async def list_prices_endpoint(
    id: str,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    records = await list_prices(ws_id, id)
    return [
        PriceRecordResponse(
            id=str(r.id),
            price_cents=r.price_cents,
            recorded_at=r.recorded_at,
            note=r.note,
        )
        for r in records
    ]


@router.post("/{id}/prices", response_model=PriceRecordResponse, status_code=status.HTTP_201_CREATED)
async def add_price_endpoint(
    id: str,
    data: PriceRecordCreate,
    workspace: CurrentWorkspace,
):
    ws_id = str(workspace.id)
    record = await add_price(ws_id, id, data)
    return PriceRecordResponse(
        id=str(record.id),
        price_cents=record.price_cents,
        recorded_at=record.recorded_at,
        note=record.note,
    )
