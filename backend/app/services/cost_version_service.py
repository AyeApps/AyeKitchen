import re
from datetime import UTC, datetime
from typing import Any

from bson import ObjectId

from app.core.errors import AppError
from app.models.cost_version import CostVersion, CostVersionChoice
from app.models.ingredient import Ingredient
from app.models.presentation import Presentation
from app.models.recipe import Recipe, RecipeItemKind
from app.schemas.cost_version import (
    CostVersionChoiceInput,
    CostVersionChoiceResponse,
    CostVersionCompareResponse,
    CostVersionCreate,
    CostVersionResponse,
    CostVersionUpdate,
)
from app.services.costing_service import calculate_recipe_cost
from app.services.costing_snapshot import load_costing_snapshot
from app.services.recipe_service import get_recipe


def _clean_name(name: str) -> str:
    clean = name.strip()
    if clean.lower() == "base":
        raise AppError(
            status_code=409,
            detail="Ya tienes una versión con ese nombre",
            code="DUPLICATE_NAME",
        )
    return clean


async def _validate_choices(
    workspace_id: str,
    recipe: Recipe,
    choices: list[CostVersionChoiceInput],
) -> None:
    recipe_ingredient_ids = {
        it.ref_id for it in recipe.items if it.kind == RecipeItemKind.ingredient
    }
    seen_ingredients: set[str] = set()

    for ch in choices:
        if ch.ingredient_id in seen_ingredients:
            raise AppError(
                status_code=422,
                detail="Ingrediente repetido en las elecciones",
                code="INVALID_REFERENCE",
            )
        seen_ingredients.add(ch.ingredient_id)

        if ch.ingredient_id not in recipe_ingredient_ids:
            raise AppError(
                status_code=422,
                detail="El ingrediente no pertenece a la receta",
                code="INVALID_REFERENCE",
            )

        if not ObjectId.is_valid(ch.presentation_id):
            raise AppError(
                status_code=422,
                detail="Presentación no encontrada",
                code="INVALID_REFERENCE",
            )

        pres = await Presentation.find_one(
            Presentation.id == ObjectId(ch.presentation_id),
            Presentation.workspace_id == workspace_id,
            Presentation.deleted_at == None,  # noqa: E711
        )
        if not pres:
            raise AppError(
                status_code=422,
                detail="Presentación no encontrada",
                code="INVALID_REFERENCE",
            )

        if str(pres.ingredient_id) != str(ch.ingredient_id):
            ing = (
                await Ingredient.find_one(
                    Ingredient.id == ObjectId(ch.ingredient_id),
                    Ingredient.workspace_id == workspace_id,
                    Ingredient.deleted_at == None,  # noqa: E711
                )
                if ObjectId.is_valid(ch.ingredient_id)
                else None
            )

            detail = (
                f"Esa marca no es de {ing.name}"
                if ing
                else "Esa marca no es de este ingrediente"
            )

            raise AppError(
                status_code=422,
                detail=detail,
                code="INVALID_REFERENCE",
            )


async def serialize_cost_version(
    version: CostVersion,
    workspace_id: str,
) -> CostVersionResponse:
    ing_ids = [
        ObjectId(c.ingredient_id)
        for c in version.choices
        if ObjectId.is_valid(c.ingredient_id)
    ]
    pres_ids = [
        ObjectId(c.presentation_id)
        for c in version.choices
        if ObjectId.is_valid(c.presentation_id)
    ]

    ingredients = (
        await Ingredient.find(
            {"_id": {"$in": ing_ids}},
            Ingredient.workspace_id == workspace_id,
        ).to_list()
        if ing_ids
        else []
    )
    presentations = (
        await Presentation.find(
            {"_id": {"$in": pres_ids}},
            Presentation.workspace_id == workspace_id,
        ).to_list()
        if pres_ids
        else []
    )

    ing_map = {str(i.id): i.name for i in ingredients}
    pres_map = {str(p.id): p.brand for p in presentations}

    choice_responses = [
        CostVersionChoiceResponse(
            ingredient_id=c.ingredient_id,
            ingredient_name=ing_map.get(c.ingredient_id, ""),
            presentation_id=c.presentation_id,
            brand=pres_map.get(c.presentation_id, ""),
        )
        for c in version.choices
    ]

    return CostVersionResponse(
        id=str(version.id),
        recipe_id=str(version.recipe_id),
        name=version.name,
        choices=choice_responses,
        created_at=version.created_at,
        updated_at=version.updated_at,
    )


async def get_cost_version(
    workspace_id: str,
    recipe_id: str,
    version_id: str,
) -> CostVersion:
    await get_recipe(workspace_id, recipe_id)

    if not ObjectId.is_valid(version_id):
        raise AppError(
            status_code=404,
            detail="Versión no encontrada",
            code="NOT_FOUND",
        )

    version = await CostVersion.find_one(
        CostVersion.id == ObjectId(version_id),
        CostVersion.workspace_id == workspace_id,
        CostVersion.recipe_id == recipe_id,
        CostVersion.deleted_at == None,  # noqa: E711
    )
    if not version:
        raise AppError(
            status_code=404,
            detail="Versión no encontrada",
            code="NOT_FOUND",
        )

    return version


async def list_cost_versions(
    workspace_id: str,
    recipe_id: str,
) -> list[CostVersionResponse]:
    await get_recipe(workspace_id, recipe_id)

    versions = await CostVersion.find(
        CostVersion.workspace_id == workspace_id,
        CostVersion.recipe_id == recipe_id,
        CostVersion.deleted_at == None,  # noqa: E711
    ).sort("+created_at").to_list()

    if not versions:
        return []

    all_ing_ids: list[ObjectId] = []
    all_pres_ids: list[ObjectId] = []
    for v in versions:
        for c in v.choices:
            if ObjectId.is_valid(c.ingredient_id):
                all_ing_ids.append(ObjectId(c.ingredient_id))
            if ObjectId.is_valid(c.presentation_id):
                all_pres_ids.append(ObjectId(c.presentation_id))

    ingredients = (
        await Ingredient.find(
            {"_id": {"$in": all_ing_ids}},
            Ingredient.workspace_id == workspace_id,
        ).to_list()
        if all_ing_ids
        else []
    )
    presentations = (
        await Presentation.find(
            {"_id": {"$in": all_pres_ids}},
            Presentation.workspace_id == workspace_id,
        ).to_list()
        if all_pres_ids
        else []
    )
    ing_map = {str(i.id): i.name for i in ingredients}
    pres_map = {str(p.id): p.brand for p in presentations}

    responses: list[CostVersionResponse] = []
    for v in versions:
        choices = [
            CostVersionChoiceResponse(
                ingredient_id=c.ingredient_id,
                ingredient_name=ing_map.get(c.ingredient_id, ""),
                presentation_id=c.presentation_id,
                brand=pres_map.get(c.presentation_id, ""),
            )
            for c in v.choices
        ]
        responses.append(
            CostVersionResponse(
                id=str(v.id),
                recipe_id=str(v.recipe_id),
                name=v.name,
                choices=choices,
                created_at=v.created_at,
                updated_at=v.updated_at,
            )
        )
    return responses


async def create_cost_version(
    workspace_id: str,
    recipe_id: str,
    data: CostVersionCreate,
) -> CostVersionResponse:
    recipe = await get_recipe(workspace_id, recipe_id)
    clean_name = _clean_name(data.name)

    existing = await CostVersion.find_one(
        CostVersion.workspace_id == workspace_id,
        CostVersion.recipe_id == recipe_id,
        CostVersion.deleted_at == None,  # noqa: E711
        {"name": {"$regex": f"^{re.escape(clean_name)}$", "$options": "i"}},
    )
    if existing:
        raise AppError(
            status_code=409,
            detail="Ya tienes una versión con ese nombre",
            code="DUPLICATE_NAME",
        )

    if data.choices:
        await _validate_choices(workspace_id, recipe, data.choices)

    choices = [
        CostVersionChoice(
            ingredient_id=ch.ingredient_id,
            presentation_id=ch.presentation_id,
        )
        for ch in data.choices
    ]

    version = CostVersion(
        workspace_id=workspace_id,
        recipe_id=recipe_id,
        name=clean_name,
        choices=choices,
    )
    await version.insert()
    return await serialize_cost_version(version, workspace_id)


async def update_cost_version(
    workspace_id: str,
    recipe_id: str,
    version_id: str,
    data: CostVersionUpdate,
) -> CostVersionResponse:
    version = await get_cost_version(workspace_id, recipe_id, version_id)
    recipe = await get_recipe(workspace_id, recipe_id)

    if "name" in data.model_fields_set and data.name is not None:
        clean_name = _clean_name(data.name)
        existing = await CostVersion.find_one(
            CostVersion.workspace_id == workspace_id,
            CostVersion.recipe_id == recipe_id,
            CostVersion.deleted_at == None,  # noqa: E711
            CostVersion.id != version.id,
            {"name": {"$regex": f"^{re.escape(clean_name)}$", "$options": "i"}},
        )
        if existing:
            raise AppError(
                status_code=409,
                detail="Ya tienes una versión con ese nombre",
                code="DUPLICATE_NAME",
            )
        version.name = clean_name

    if "choices" in data.model_fields_set and data.choices is not None:
        await _validate_choices(workspace_id, recipe, data.choices)
        version.choices = [
            CostVersionChoice(
                ingredient_id=ch.ingredient_id,
                presentation_id=ch.presentation_id,
            )
            for ch in data.choices
        ]

    version.updated_at = datetime.now(UTC)
    await version.save()
    return await serialize_cost_version(version, workspace_id)


async def delete_cost_version(
    workspace_id: str,
    recipe_id: str,
    version_id: str,
) -> None:
    version = await get_cost_version(workspace_id, recipe_id, version_id)
    await version.soft_delete()


async def compare_cost_versions(
    workspace_id: str,
    recipe_id: str,
) -> list[CostVersionCompareResponse]:
    recipe = await get_recipe(workspace_id, recipe_id)
    snapshot = await load_costing_snapshot(workspace_id)
    cache: dict[str, Any] = {}

    base_cost = await calculate_recipe_cost(
        workspace_id,
        recipe,
        cache=cache,
        version=None,
        snapshot=snapshot,
    )

    results: list[CostVersionCompareResponse] = [
        CostVersionCompareResponse(
            version_id=None,
            name="Base",
            batch_cost_cents=base_cost.batch_cost_cents,
            cost_per_serving_cents=base_cost.cost_per_serving_cents,
            suggested_price_cents=base_cost.suggested_price_cents,
            complete=base_cost.complete,
            has_stale_prices=base_cost.has_stale_prices,
        )
    ]

    versions = await CostVersion.find(
        CostVersion.workspace_id == workspace_id,
        CostVersion.recipe_id == recipe_id,
        CostVersion.deleted_at == None,  # noqa: E711
    ).sort("+created_at").to_list()

    for v in versions:
        v_cost = await calculate_recipe_cost(
            workspace_id,
            recipe,
            cache=cache,
            version=v,
            snapshot=snapshot,
        )
        results.append(
            CostVersionCompareResponse(
                version_id=str(v.id),
                name=v.name,
                batch_cost_cents=v_cost.batch_cost_cents,
                cost_per_serving_cents=v_cost.cost_per_serving_cents,
                suggested_price_cents=v_cost.suggested_price_cents,
                complete=v_cost.complete,
                has_stale_prices=v_cost.has_stale_prices,
            )
        )

    return results
