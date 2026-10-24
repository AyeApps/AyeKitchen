from decimal import ROUND_HALF_UP, Decimal
from typing import NamedTuple

from bson import ObjectId

from app.core.config import settings
from app.models.base import parse_decimal, round_to_cents
from app.models.ingredient import Ingredient
from app.models.presentation import Presentation
from app.models.recipe import Recipe, RecipeItem, RecipeItemKind
from app.models.supplier import Supplier
from app.models.unit import Unit
from app.models.workspace import Workspace
from app.schemas.recipe import CostLineResponse, RecipeCostResponse
from app.services.conversion_service import convert_between_base_units, convert_to_base
from app.services.presentation_service import get_current_presentation, get_latest_price


class _IngredientCostResult(NamedTuple):
    quantity_in_base: Decimal
    presentation: Presentation | None
    pinned: bool
    price_cents: int | None
    unrounded_cost: Decimal


async def _get_workspace_default_margin(workspace_id: str) -> int:
    if ObjectId.is_valid(workspace_id):
        ws = await Workspace.get(ObjectId(workspace_id))
        if ws:
            return ws.default_margin_percent
    ws = await Workspace.get(workspace_id)
    if ws:
        return ws.default_margin_percent
    return settings.DEFAULT_MARGIN_PERCENT


async def _compute_ingredient_line_cost(
    workspace_id: str,
    item: RecipeItem,
    ingredient: Ingredient,
) -> _IngredientCostResult:
    """Función interna única para calcular el costo de una línea de ingrediente.

    Devuelve: (quantity_in_base, presentation, pinned, price_cents, unrounded_cost).
    Si la presentación fijada está activa pero no tiene precio, se mantiene pinned=True,
    sin usar la vigente, con costo 0 y price_cents=None.
    """
    qty_in_base = await convert_to_base(
        workspace_id,
        item.quantity,
        item.unit_id,
        ingredient,
    )

    pinned = False
    pres: Presentation | None = None
    price_cents: int | None = None

    if item.pinned_presentation_id and ObjectId.is_valid(item.pinned_presentation_id):
        pinned_p = await Presentation.find_one(
            Presentation.id == ObjectId(item.pinned_presentation_id),
            Presentation.workspace_id == workspace_id,
            Presentation.deleted_at == None,  # noqa: E711
        )
        if pinned_p and str(pinned_p.ingredient_id) == str(ingredient.id):
            pres = pinned_p
            pinned = True
            pr = await get_latest_price(workspace_id, str(pinned_p.id))
            if pr:
                price_cents = pr.price_cents

    if not pinned or pres is None:
        pinned = False
        curr = await get_current_presentation(workspace_id, str(ingredient.id))
        if curr:
            pres = curr.presentation
            price_cents = curr.price_record.price_cents
        else:
            pres = None
            price_cents = None

    if pres is not None and price_cents is not None:
        pkg_qty = parse_decimal(pres.package_quantity)
        if pkg_qty > Decimal("0"):
            unrounded_cost = (qty_in_base * Decimal(price_cents)) / pkg_qty
        else:
            unrounded_cost = Decimal("0")
    else:
        unrounded_cost = Decimal("0")

    return _IngredientCostResult(
        quantity_in_base=qty_in_base,
        presentation=pres,
        pinned=pinned,
        price_cents=price_cents,
        unrounded_cost=unrounded_cost,
    )


async def _compute_subrecipe_unrounded_cost(
    workspace_id: str,
    recipe_id: str,
    cache: dict[str, tuple[Decimal, bool]],
    depth: int = 1,
) -> tuple[Decimal, bool]:
    """Calcula recursivamente el costo total sin redondear de una subreceta y si está completa.

    Utiliza una caché dentro de la llamada para evitar recalcular la misma subreceta múltiples veces.
    Si la profundidad supera 10 niveles (defensa contra ciclos en datos corruptos), detiene la
    recursión devolviendo costo 0 y complete False.
    """
    if depth > 10:
        return Decimal("0"), False

    if recipe_id in cache:
        return cache[recipe_id]

    if not ObjectId.is_valid(recipe_id):
        cache[recipe_id] = (Decimal("0"), False)
        return Decimal("0"), False

    subrecipe = await Recipe.find_one(
        Recipe.id == ObjectId(recipe_id),
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
    )
    if not subrecipe:
        cache[recipe_id] = (Decimal("0"), False)
        return Decimal("0"), False

    is_complete = True
    lines_unrounded_cost = Decimal("0")

    for item in subrecipe.items:
        if item.kind == RecipeItemKind.ingredient:
            if not ObjectId.is_valid(item.ref_id):
                is_complete = False
                continue

            ingredient = await Ingredient.find_one(
                Ingredient.id == ObjectId(item.ref_id),
                Ingredient.workspace_id == workspace_id,
                Ingredient.deleted_at == None,  # noqa: E711
            )
            if not ingredient:
                is_complete = False
                continue

            cost_res = await _compute_ingredient_line_cost(
                workspace_id,
                item,
                ingredient,
            )
            lines_unrounded_cost += cost_res.unrounded_cost
            if cost_res.price_cents is None or cost_res.presentation is None:
                is_complete = False

        elif item.kind == RecipeItemKind.recipe:
            sub_cost, sub_comp = await _compute_subrecipe_unrounded_cost(
                workspace_id,
                item.ref_id,
                cache,
                depth=depth + 1,
            )
            if not sub_comp:
                is_complete = False

            if not ObjectId.is_valid(item.ref_id):
                is_complete = False
                continue

            nested_rec = await Recipe.find_one(
                Recipe.id == ObjectId(item.ref_id),
                Recipe.workspace_id == workspace_id,
                Recipe.deleted_at == None,  # noqa: E711
            )
            if nested_rec:
                qty_in_yield = await convert_between_base_units(
                    workspace_id,
                    item.quantity,
                    item.unit_id,
                    nested_rec.yield_unit,
                )
                yield_qty = parse_decimal(nested_rec.yield_quantity)
                if yield_qty > Decimal("0"):
                    line_cost = (qty_in_yield * sub_cost) / yield_qty
                    lines_unrounded_cost += line_cost
                else:
                    is_complete = False
            else:
                is_complete = False

    extras_cost = sum(
        (Decimal(e.cost_cents) for e in subrecipe.extra_costs),
        start=Decimal("0"),
    )
    batch_cost = lines_unrounded_cost + extras_cost
    cache[recipe_id] = (batch_cost, is_complete)
    return batch_cost, is_complete


async def calculate_recipe_cost(
    workspace_id: str,
    recipe: Recipe,
    cache: dict[str, tuple[Decimal, bool]] | None = None,
) -> RecipeCostResponse:
    """Calcula el costo detallado de una receta según el contrato de la API.

    Todo el cálculo interno se realiza en Decimal sin redondear.
    Cada campo monetario _cents se redondea una sola vez con round_to_cents desde su valor sin redondear.
    """
    if cache is None:
        cache = {}

    lines: list[CostLineResponse] = []
    unrounded_line_costs: list[Decimal] = []

    for item in recipe.items:
        unit_name: str | None = None
        if item.unit_id and ObjectId.is_valid(item.unit_id):
            unit = await Unit.get(item.unit_id)
            if unit:
                unit_name = unit.name

        if item.kind == RecipeItemKind.ingredient:
            ingredient = await Ingredient.find_one(
                Ingredient.id == ObjectId(item.ref_id),
                Ingredient.workspace_id == workspace_id,
                Ingredient.deleted_at == None,  # noqa: E711
            ) if ObjectId.is_valid(item.ref_id) else None

            if not ingredient:
                lines.append(
                    CostLineResponse(
                        kind=RecipeItemKind.ingredient,
                        ref_id=item.ref_id,
                        ref_name="",
                        quantity=str(item.quantity),
                        unit_name=unit_name,
                        quantity_in_base="0",
                        base_unit=recipe.yield_unit,
                        presentation_id=None,
                        presentation_label=None,
                        pinned=False,
                        cost_cents=0,
                        missing_price=True,
                    )
                )
                unrounded_line_costs.append(Decimal("0"))
                continue

            cost_res = await _compute_ingredient_line_cost(
                workspace_id,
                item,
                ingredient,
            )

            presentation_label: str | None = None
            presentation_id: str | None = None

            if cost_res.presentation is not None:
                presentation_id = str(cost_res.presentation.id)
                supplier_name: str | None = None
                if cost_res.presentation.supplier_id and ObjectId.is_valid(
                    cost_res.presentation.supplier_id
                ):
                    supp = await Supplier.find_one(
                        Supplier.id == ObjectId(cost_res.presentation.supplier_id),
                        Supplier.workspace_id == workspace_id,
                        Supplier.deleted_at == None,  # noqa: E711
                    )
                    if supp:
                        supplier_name = supp.name

                base_u_str = (
                    ingredient.base_unit.value
                    if hasattr(ingredient.base_unit, "value")
                    else str(ingredient.base_unit)
                )
                if supplier_name:
                    presentation_label = (
                        f"{cost_res.presentation.brand} · {supplier_name} · "
                        f"{cost_res.presentation.package_quantity} {base_u_str}"
                    )
                else:
                    presentation_label = (
                        f"{cost_res.presentation.brand} · "
                        f"{cost_res.presentation.package_quantity} {base_u_str}"
                    )

            missing_price = (
                cost_res.presentation is None or cost_res.price_cents is None
            )
            unrounded_line_costs.append(cost_res.unrounded_cost)
            lines.append(
                CostLineResponse(
                    kind=RecipeItemKind.ingredient,
                    ref_id=str(ingredient.id),
                    ref_name=ingredient.name,
                    quantity=str(item.quantity),
                    unit_name=unit_name,
                    quantity_in_base=str(cost_res.quantity_in_base),
                    base_unit=ingredient.base_unit,
                    presentation_id=presentation_id,
                    presentation_label=presentation_label,
                    pinned=cost_res.pinned,
                    cost_cents=round_to_cents(cost_res.unrounded_cost),
                    missing_price=missing_price,
                )
            )

        elif item.kind == RecipeItemKind.recipe:
            subrecipe = await Recipe.find_one(
                Recipe.id == ObjectId(item.ref_id),
                Recipe.workspace_id == workspace_id,
                Recipe.deleted_at == None,  # noqa: E711
            ) if ObjectId.is_valid(item.ref_id) else None

            if not subrecipe:
                lines.append(
                    CostLineResponse(
                        kind=RecipeItemKind.recipe,
                        ref_id=item.ref_id,
                        ref_name="",
                        quantity=str(item.quantity),
                        unit_name=unit_name,
                        quantity_in_base="0",
                        base_unit=recipe.yield_unit,
                        presentation_id=None,
                        presentation_label=None,
                        pinned=False,
                        cost_cents=0,
                        missing_price=True,
                    )
                )
                unrounded_line_costs.append(Decimal("0"))
                continue

            qty_in_yield = await convert_between_base_units(
                workspace_id,
                item.quantity,
                item.unit_id,
                subrecipe.yield_unit,
            )

            sub_batch_cost, sub_complete = await _compute_subrecipe_unrounded_cost(
                workspace_id,
                item.ref_id,
                cache,
                depth=2,
            )

            yield_qty = parse_decimal(subrecipe.yield_quantity)
            if yield_qty > Decimal("0"):
                line_unrounded_cost = (qty_in_yield * sub_batch_cost) / yield_qty
            else:
                line_unrounded_cost = Decimal("0")

            missing_price = not sub_complete
            unrounded_line_costs.append(line_unrounded_cost)

            lines.append(
                CostLineResponse(
                    kind=RecipeItemKind.recipe,
                    ref_id=str(subrecipe.id),
                    ref_name=subrecipe.name,
                    quantity=str(item.quantity),
                    unit_name=unit_name,
                    quantity_in_base=str(qty_in_yield),
                    base_unit=subrecipe.yield_unit,
                    presentation_id=None,
                    presentation_label=None,
                    pinned=False,
                    cost_cents=round_to_cents(line_unrounded_cost),
                    missing_price=missing_price,
                )
            )

    unrounded_lines_cost = sum(unrounded_line_costs, start=Decimal("0"))
    unrounded_extras_cost = sum(
        (Decimal(e.cost_cents) for e in recipe.extra_costs),
        start=Decimal("0"),
    )
    unrounded_batch_cost = unrounded_lines_cost + unrounded_extras_cost

    ingredients_cost_cents = round_to_cents(unrounded_lines_cost)
    extras_cost_cents = round_to_cents(unrounded_extras_cost)
    batch_cost_cents = round_to_cents(unrounded_batch_cost)

    yield_qty = parse_decimal(recipe.yield_quantity)
    if yield_qty > Decimal("0"):
        cost_per_yield_unit = str(
            (unrounded_batch_cost / yield_qty).quantize(
                Decimal("0.000001"),
                rounding=ROUND_HALF_UP,
            )
        )
    else:
        cost_per_yield_unit = "0.000000"

    cost_per_serving_cents: int | None = None
    if recipe.servings and recipe.servings > 0:
        cost_per_serving_cents = round_to_cents(
            unrounded_batch_cost / Decimal(recipe.servings)
        )

    default_margin = await _get_workspace_default_margin(workspace_id)
    margin_percent = (
        recipe.margin_percent if recipe.margin_percent is not None else default_margin
    )

    unrounded_suggested_price = unrounded_batch_cost * (
        Decimal("1") + Decimal(margin_percent) / Decimal("100")
    )
    suggested_price_cents = round_to_cents(unrounded_suggested_price)

    complete = all(not line.missing_price for line in lines)

    if recipe.id:
        cache[str(recipe.id)] = (unrounded_batch_cost, complete)

    return RecipeCostResponse(
        recipe_id=str(recipe.id) if recipe.id else "",
        lines=lines,
        ingredients_cost_cents=ingredients_cost_cents,
        extras_cost_cents=extras_cost_cents,
        batch_cost_cents=batch_cost_cents,
        cost_per_yield_unit=cost_per_yield_unit,
        cost_per_serving_cents=cost_per_serving_cents,
        margin_percent=margin_percent,
        suggested_price_cents=suggested_price_cents,
        complete=complete,
    )
