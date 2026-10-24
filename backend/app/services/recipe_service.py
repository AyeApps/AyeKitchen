import math
import re
from collections import defaultdict
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from bson import ObjectId

from app.core.errors import AppError
from app.models.base import parse_decimal
from app.models.ingredient import Ingredient
from app.models.presentation import Presentation
from app.models.recipe import ExtraCost, Recipe, RecipeItem, RecipeItemKind
from app.models.unit import Unit
from app.schemas.recipe import (
    ExtraCostResponse,
    RecipeCreate,
    RecipeItemResponse,
    RecipeListItemResponse,
    RecipeResponse,
    RecipeUpdate,
    UsableSubrecipeResponse,
)
from app.services.conversion_service import convert_between_base_units, convert_to_base
from app.services.costing_service import calculate_recipe_cost


async def get_recipe(workspace_id: str, recipe_id: str) -> Recipe:
    if not ObjectId.is_valid(recipe_id):
        raise AppError(status_code=404, detail="Receta no encontrada", code="NOT_FOUND")

    recipe = await Recipe.find_one(
        Recipe.id == ObjectId(recipe_id),
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
    )
    if not recipe:
        raise AppError(status_code=404, detail="Receta no encontrada", code="NOT_FOUND")

    return recipe


async def validate_recipe_items_and_yield(
    workspace_id: str,
    items: list[Any],
    yield_quantity: Decimal,
) -> None:
    """Valida los items de una receta y su rendimiento en el orden exacto requerido por el contrato:

    1. Cada ref_id apunta a un ingrediente o receta activa del workspace (INVALID_REFERENCE).
    2. pinned_presentation_id solo en kind=ingredient y debe ser activa del mismo ingrediente (INVALID_REFERENCE).
    3. unit_id, si viene, debe existir (INVALID_REFERENCE).
    4. Cada línea debe ser convertible (UNIT_NOT_CONVERTIBLE).
    5. quantity y yield_quantity mayores que cero.
    """
    for item in items:
        # Paso 1: referencia activa
        if item.kind == RecipeItemKind.ingredient:
            if not ObjectId.is_valid(item.ref_id):
                raise AppError(
                    status_code=422,
                    detail=f"Ingrediente no encontrado: {item.ref_id}",
                    code="INVALID_REFERENCE",
                )
            ing = await Ingredient.find_one(
                Ingredient.id == ObjectId(item.ref_id),
                Ingredient.workspace_id == workspace_id,
                Ingredient.deleted_at == None,  # noqa: E711
            )
            if not ing:
                raise AppError(
                    status_code=422,
                    detail=f"Ingrediente no encontrado: {item.ref_id}",
                    code="INVALID_REFERENCE",
                )
        elif item.kind == RecipeItemKind.recipe:
            if not ObjectId.is_valid(item.ref_id):
                raise AppError(
                    status_code=422,
                    detail=f"Receta no encontrada: {item.ref_id}",
                    code="INVALID_REFERENCE",
                )
            subrec = await Recipe.find_one(
                Recipe.id == ObjectId(item.ref_id),
                Recipe.workspace_id == workspace_id,
                Recipe.deleted_at == None,  # noqa: E711
            )
            if not subrec:
                raise AppError(
                    status_code=422,
                    detail=f"Receta no encontrada: {item.ref_id}",
                    code="INVALID_REFERENCE",
                )
        else:
            raise AppError(
                status_code=422,
                detail=f"Tipo de item inválido: {item.kind}",
                code="INVALID_REFERENCE",
            )

        # Paso 2: pinned_presentation_id
        if item.pinned_presentation_id:
            if item.kind != RecipeItemKind.ingredient:
                raise AppError(
                    status_code=422,
                    detail="pinned_presentation_id solo se permite en líneas de ingrediente",
                    code="INVALID_REFERENCE",
                )
            if not ObjectId.is_valid(item.pinned_presentation_id):
                raise AppError(
                    status_code=422,
                    detail="Presentación fijada no encontrada",
                    code="INVALID_REFERENCE",
                )
            pres = await Presentation.find_one(
                Presentation.id == ObjectId(item.pinned_presentation_id),
                Presentation.workspace_id == workspace_id,
                Presentation.deleted_at == None,  # noqa: E711
            )
            if not pres or str(pres.ingredient_id) != str(item.ref_id):
                raise AppError(
                    status_code=422,
                    detail="La presentación no pertenece a este ingrediente o no existe",
                    code="INVALID_REFERENCE",
                )

        # Paso 3: unit_id si viene debe existir
        if item.unit_id:
            if not ObjectId.is_valid(item.unit_id):
                raise AppError(
                    status_code=422,
                    detail=f"Unidad no encontrada: {item.unit_id}",
                    code="INVALID_REFERENCE",
                )
            unit = await Unit.find_one(
                Unit.id == ObjectId(item.unit_id),
                Unit.deleted_at == None,  # noqa: E711
                {"$or": [{"workspace_id": None}, {"workspace_id": workspace_id}]},
            )
            if not unit:
                raise AppError(
                    status_code=422,
                    detail=f"Unidad no encontrada: {item.unit_id}",
                    code="INVALID_REFERENCE",
                )

        # Paso 4: convertibilidad
        if item.kind == RecipeItemKind.ingredient:
            await convert_to_base(
                workspace_id,
                parse_decimal(item.quantity),
                item.unit_id,
                ing,
            )
        elif item.kind == RecipeItemKind.recipe:
            await convert_between_base_units(
                workspace_id,
                parse_decimal(item.quantity),
                item.unit_id,
                subrec.yield_unit,
            )

        # Paso 5: quantity > 0
        if parse_decimal(item.quantity) <= Decimal("0"):
            raise AppError(
                status_code=422,
                detail="La cantidad debe ser mayor que cero",
                code="INVALID_REFERENCE",
            )

    if yield_quantity <= Decimal("0"):
        raise AppError(
            status_code=422,
            detail="La cantidad de rendimiento debe ser mayor que cero",
            code="INVALID_REFERENCE",
        )


async def validate_cycles_and_depth(
    workspace_id: str,
    target_recipe_id: str | None,
    new_subrecipe_ids: list[str],
) -> None:
    """Verifica que el árbol de subrecetas no contenga ciclos (RECIPE_CYCLE) ni supere 10 niveles (RECIPE_TOO_DEEP)."""
    if target_recipe_id and target_recipe_id in new_subrecipe_ids:
        raise AppError(
            status_code=422,
            detail="La receta se usaría a sí misma directa o indirectamente",
            code="RECIPE_CYCLE",
        )

    active_recipes = await Recipe.find(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
    ).to_list()

    adj: dict[str, list[str]] = {}
    for r in active_recipes:
        adj[str(r.id)] = [
            it.ref_id for it in r.items if it.kind == RecipeItemKind.recipe
        ]

    if target_recipe_id:
        adj[target_recipe_id] = new_subrecipe_ids
    else:
        adj["__new__"] = new_subrecipe_ids

    def dfs_cycle(node_id: str, current_path: list[str]) -> None:
        if target_recipe_id and node_id == target_recipe_id:
            raise AppError(
                status_code=422,
                detail="La receta se usaría a sí misma directa o indirectamente",
                code="RECIPE_CYCLE",
            )
        if node_id in current_path:
            raise AppError(
                status_code=422,
                detail="Se detectó un ciclo en las subrecetas",
                code="RECIPE_CYCLE",
            )

        new_path = current_path + [node_id]
        for child in adj.get(node_id, []):
            dfs_cycle(child, new_path)

    initial_path = [target_recipe_id] if target_recipe_id else ["__new__"]
    for child in new_subrecipe_ids:
        dfs_cycle(child, initial_path)

    # Cálculo de la cadena más larga de subrecetas en todo el workspace (recorrido con memoria)
    depth_memo: dict[str, int] = {}

    def get_max_depth(node: str, current_depth: int = 1) -> int:
        if current_depth > 11:
            return 11

        if node in depth_memo:
            return depth_memo[node]

        children = adj.get(node, [])
        if not children:
            depth_memo[node] = 1
            return 1

        max_child = max(get_max_depth(child, current_depth + 1) for child in children)
        res = 1 + max_child
        depth_memo[node] = res
        return res

    for node in adj:
        if get_max_depth(node) > 10:
            raise AppError(
                status_code=422,
                detail="La receta excede la profundidad máxima permitida de 10 niveles",
                code="RECIPE_TOO_DEEP",
            )


async def serialize_recipe(
    recipe: Recipe,
    ing_map: dict[str, Ingredient] | None = None,
    rec_map: dict[str, Recipe] | None = None,
    unit_map: dict[str, Unit] | None = None,
) -> RecipeResponse:
    if ing_map is None or rec_map is None or unit_map is None:
        ing_ids = [
            ObjectId(it.ref_id)
            for it in recipe.items
            if it.kind == RecipeItemKind.ingredient and ObjectId.is_valid(it.ref_id)
        ]
        rec_ids = [
            ObjectId(it.ref_id)
            for it in recipe.items
            if it.kind == RecipeItemKind.recipe and ObjectId.is_valid(it.ref_id)
        ]
        unit_ids = [
            ObjectId(it.unit_id)
            for it in recipe.items
            if it.unit_id and ObjectId.is_valid(it.unit_id)
        ]

        ingredients = (
            await Ingredient.find({"_id": {"$in": ing_ids}}).to_list()
            if ing_ids
            else []
        )
        recipes = (
            await Recipe.find({"_id": {"$in": rec_ids}}).to_list() if rec_ids else []
        )
        units = await Unit.find({"_id": {"$in": unit_ids}}).to_list() if unit_ids else []

        ing_map = {str(i.id): i for i in ingredients}
        rec_map = {str(r.id): r for r in recipes}
        unit_map = {str(u.id): u for u in units}

    items_resp: list[RecipeItemResponse] = []
    for item in recipe.items:
        if item.kind == RecipeItemKind.ingredient:
            ing = ing_map.get(item.ref_id)
            ref_name = ing.name if ing else ""
        else:
            rec = rec_map.get(item.ref_id)
            ref_name = rec.name if rec else ""

        unit_name = None
        if item.unit_id:
            u = unit_map.get(item.unit_id)
            unit_name = u.name if u else None

        items_resp.append(
            RecipeItemResponse(
                kind=item.kind,
                ref_id=item.ref_id,
                ref_name=ref_name,
                quantity=str(item.quantity),
                unit_id=item.unit_id,
                unit_name=unit_name,
                pinned_presentation_id=item.pinned_presentation_id,
            )
        )

    extra_costs_resp = [
        ExtraCostResponse(name=e.name, cost_cents=e.cost_cents)
        for e in recipe.extra_costs
    ]

    return RecipeResponse(
        id=str(recipe.id),
        name=recipe.name,
        description=recipe.description,
        items=items_resp,
        extra_costs=extra_costs_resp,
        yield_quantity=str(recipe.yield_quantity),
        yield_unit=recipe.yield_unit,
        servings=recipe.servings,
        margin_percent=recipe.margin_percent,
        created_at=recipe.created_at,
        updated_at=recipe.updated_at,
    )


async def list_recipes(
    workspace_id: str,
    page: int = 1,
    limit: int = 20,
    q: str | None = None,
) -> tuple[list[RecipeListItemResponse], int, int]:
    limit = min(max(1, limit), 100)
    page = max(1, page)

    filters: dict[str, Any] = {
        "workspace_id": workspace_id,
        "deleted_at": None,
    }
    if q and q.strip():
        filters["name"] = {"$regex": re.escape(q.strip()), "$options": "i"}

    recipes = await Recipe.find(filters).to_list()
    recipes.sort(key=lambda r: r.name.lower())

    total = len(recipes)
    pages = math.ceil(total / limit) if total > 0 else 0
    skip = (page - 1) * limit
    page_items = recipes[skip : skip + limit]

    all_ing_ids: list[ObjectId] = []
    all_rec_ids: list[ObjectId] = []
    all_unit_ids: list[ObjectId] = []

    for r in page_items:
        for it in r.items:
            if it.kind == RecipeItemKind.ingredient and ObjectId.is_valid(it.ref_id):
                all_ing_ids.append(ObjectId(it.ref_id))
            elif it.kind == RecipeItemKind.recipe and ObjectId.is_valid(it.ref_id):
                all_rec_ids.append(ObjectId(it.ref_id))
            if it.unit_id and ObjectId.is_valid(it.unit_id):
                all_unit_ids.append(ObjectId(it.unit_id))

    ingredients = (
        await Ingredient.find({"_id": {"$in": all_ing_ids}}).to_list()
        if all_ing_ids
        else []
    )
    all_recipes = (
        await Recipe.find({"_id": {"$in": all_rec_ids}}).to_list()
        if all_rec_ids
        else []
    )
    units = (
        await Unit.find({"_id": {"$in": all_unit_ids}}).to_list()
        if all_unit_ids
        else []
    )

    ing_map = {str(i.id): i for i in ingredients}
    rec_map = {str(r.id): r for r in all_recipes}
    unit_map = {str(u.id): u for u in units}

    cost_cache: dict[str, tuple[Decimal, bool]] = {}
    items: list[RecipeListItemResponse] = []

    for r in page_items:
        serialized = await serialize_recipe(r, ing_map, rec_map, unit_map)
        try:
            cost_resp = await calculate_recipe_cost(
                workspace_id,
                r,
                cache=cost_cache,
            )
            batch_cost_cents = cost_resp.batch_cost_cents
            complete = cost_resp.complete
        except AppError:
            batch_cost_cents = None
            complete = False

        items.append(
            RecipeListItemResponse(
                id=serialized.id,
                name=serialized.name,
                description=serialized.description,
                items=serialized.items,
                extra_costs=serialized.extra_costs,
                yield_quantity=serialized.yield_quantity,
                yield_unit=serialized.yield_unit,
                servings=serialized.servings,
                margin_percent=serialized.margin_percent,
                batch_cost_cents=batch_cost_cents,
                complete=complete,
                created_at=serialized.created_at,
                updated_at=serialized.updated_at,
            )
        )

    return items, total, pages


async def create_recipe(workspace_id: str, data: RecipeCreate) -> Recipe:
    clean_name = data.name.strip()
    existing = await Recipe.find_one(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
        {"name": {"$regex": f"^{re.escape(clean_name)}$", "$options": "i"}},
    )
    if existing:
        raise AppError(
            status_code=409,
            detail="Ya existe una receta con ese nombre",
            code="DUPLICATE_NAME",
        )

    yield_qty = parse_decimal(data.yield_quantity)
    await validate_recipe_items_and_yield(workspace_id, data.items, yield_qty)

    subrecipe_ids = [
        it.ref_id for it in data.items if it.kind == RecipeItemKind.recipe
    ]
    await validate_cycles_and_depth(workspace_id, None, subrecipe_ids)

    items = [
        RecipeItem(
            kind=it.kind,
            ref_id=it.ref_id,
            quantity=parse_decimal(it.quantity),
            unit_id=it.unit_id,
            pinned_presentation_id=it.pinned_presentation_id,
        )
        for it in data.items
    ]

    extra_costs = [
        ExtraCost(name=e.name.strip(), cost_cents=e.cost_cents)
        for e in data.extra_costs
    ]

    recipe = Recipe(
        workspace_id=workspace_id,
        name=clean_name,
        description=data.description.strip() if data.description else None,
        items=items,
        extra_costs=extra_costs,
        yield_quantity=yield_qty,
        yield_unit=data.yield_unit,
        servings=data.servings,
        margin_percent=data.margin_percent,
    )
    await recipe.insert()
    return recipe


async def update_recipe(
    workspace_id: str,
    recipe_id: str,
    data: RecipeUpdate,
) -> Recipe:
    recipe = await get_recipe(workspace_id, recipe_id)

    if "name" in data.model_fields_set and data.name is not None:
        clean_name = data.name.strip()
        existing = await Recipe.find_one(
            Recipe.workspace_id == workspace_id,
            Recipe.deleted_at == None,  # noqa: E711
            Recipe.id != ObjectId(recipe_id),
            {"name": {"$regex": f"^{re.escape(clean_name)}$", "$options": "i"}},
        )
        if existing:
            raise AppError(
                status_code=409,
                detail="Ya existe una receta con ese nombre",
                code="DUPLICATE_NAME",
            )
        recipe.name = clean_name

    yield_qty = (
        parse_decimal(data.yield_quantity)
        if ("yield_quantity" in data.model_fields_set and data.yield_quantity is not None)
        else parse_decimal(recipe.yield_quantity)
    )

    if "items" in data.model_fields_set and data.items is not None:
        await validate_recipe_items_and_yield(workspace_id, data.items, yield_qty)
        subrecipe_ids = [
            it.ref_id for it in data.items if it.kind == RecipeItemKind.recipe
        ]
        await validate_cycles_and_depth(workspace_id, recipe_id, subrecipe_ids)
        recipe.items = [
            RecipeItem(
                kind=it.kind,
                ref_id=it.ref_id,
                quantity=parse_decimal(it.quantity),
                unit_id=it.unit_id,
                pinned_presentation_id=it.pinned_presentation_id,
            )
            for it in data.items
        ]
    elif "yield_quantity" in data.model_fields_set and data.yield_quantity is not None:
        if yield_qty <= Decimal("0"):
            raise AppError(
                status_code=422,
                detail="La cantidad de rendimiento debe ser mayor que cero",
                code="INVALID_REFERENCE",
            )

    if "yield_quantity" in data.model_fields_set and data.yield_quantity is not None:
        recipe.yield_quantity = yield_qty

    if "yield_unit" in data.model_fields_set and data.yield_unit is not None:
        recipe.yield_unit = data.yield_unit

    if "description" in data.model_fields_set:
        recipe.description = data.description.strip() if data.description else None

    if "servings" in data.model_fields_set:
        recipe.servings = data.servings

    if "margin_percent" in data.model_fields_set:
        recipe.margin_percent = data.margin_percent

    if "extra_costs" in data.model_fields_set and data.extra_costs is not None:
        recipe.extra_costs = [
            ExtraCost(name=e.name.strip(), cost_cents=e.cost_cents)
            for e in data.extra_costs
        ]

    recipe.updated_at = datetime.now(UTC)
    await recipe.save()
    return recipe


async def delete_recipe(workspace_id: str, recipe_id: str) -> None:
    recipe = await get_recipe(workspace_id, recipe_id)

    in_recipe = await Recipe.find_one(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
        {"items": {"$elemMatch": {"kind": RecipeItemKind.recipe.value, "ref_id": str(recipe.id)}}},
    )
    if in_recipe:
        raise AppError(
            status_code=409,
            detail="La receta está en uso como subreceta en recetas activas",
            code="IN_USE",
        )

    await recipe.soft_delete()


async def get_usable_as_subrecipe(
    workspace_id: str,
    recipe_id: str,
) -> list[UsableSubrecipeResponse]:
    """Retorna recetas activas que se pueden agregar como subreceta de recipe_id sin crear ciclo.

    Excluye recipe_id y a toda receta que directa o indirectamente contenga a recipe_id.
    """
    await get_recipe(workspace_id, recipe_id)

    active_recipes = await Recipe.find(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
    ).to_list()

    parents_map: dict[str, list[str]] = defaultdict(list)
    for r in active_recipes:
        r_id = str(r.id)
        for it in r.items:
            if it.kind == RecipeItemKind.recipe:
                parents_map[it.ref_id].append(r_id)

    excluded: set[str] = {recipe_id}
    queue: list[str] = [recipe_id]
    while queue:
        curr = queue.pop(0)
        for parent_id in parents_map.get(curr, []):
            if parent_id not in excluded:
                excluded.add(parent_id)
                queue.append(parent_id)

    usable = [
        UsableSubrecipeResponse(
            id=str(r.id),
            name=r.name,
            yield_unit=r.yield_unit,
        )
        for r in active_recipes
        if str(r.id) not in excluded
    ]
    usable.sort(key=lambda r: r.name.lower())
    return usable
