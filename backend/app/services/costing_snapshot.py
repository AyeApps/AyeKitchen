import asyncio
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import Decimal

from bson import ObjectId

from app.models.ingredient import Ingredient
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.supplier import Supplier
from app.models.unit import BaseUnit, Unit
from app.models.workspace import Workspace
from app.services.conversion_service import (
    convert_between_base_units_with_units,
    convert_to_base_with_units,
)
from app.services.presentation_service import (
    CurrentPresentation,
    compute_price_staleness,
)


def _normalize_dt(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt


def _candidate_sort_key(c: tuple[Presentation, PriceRecord]) -> tuple[datetime, datetime]:
    # Empate de fecha: el registrado más reciente; si empatan, el creado más reciente
    return (_normalize_dt(c[1].recorded_at), _normalize_dt(c[0].created_at))


@dataclass
class CostingSnapshot:
    workspace: Workspace
    units_by_id: dict[str, Unit] = field(default_factory=dict)
    ingredients_by_id: dict[str, Ingredient] = field(default_factory=dict)
    recipes_by_id: dict[str, Recipe] = field(default_factory=dict)
    presentations_by_id: dict[str, Presentation] = field(default_factory=dict)
    presentations_by_ingredient: dict[str, list[Presentation]] = field(default_factory=dict)
    latest_prices_by_presentation: dict[str, PriceRecord] = field(default_factory=dict)
    suppliers_by_id: dict[str, Supplier] = field(default_factory=dict)
    current_presentation_by_ingredient: dict[str, CurrentPresentation] = field(default_factory=dict)

    def get_latest_price(self, presentation_id: str) -> PriceRecord | None:
        return self.latest_prices_by_presentation.get(str(presentation_id))

    def get_current_presentation(self, ingredient_id: str) -> CurrentPresentation | None:
        return self.current_presentation_by_ingredient.get(str(ingredient_id))

    def convert_to_base(
        self,
        quantity: Decimal,
        unit_id: str | None,
        ingredient: Ingredient,
    ) -> Decimal:
        ws_id = str(self.workspace.id) if self.workspace.id else ""
        return convert_to_base_with_units(
            self.units_by_id,
            ws_id,
            quantity,
            unit_id,
            ingredient,
        )

    def convert_between_base_units(
        self,
        quantity: Decimal,
        unit_id: str | None,
        target_base_unit: BaseUnit,
    ) -> Decimal:
        ws_id = str(self.workspace.id) if self.workspace.id else ""
        return convert_between_base_units_with_units(
            self.units_by_id,
            ws_id,
            quantity,
            unit_id,
            target_base_unit,
        )

    def compute_price_staleness(
        self,
        price_at: datetime | None,
    ) -> tuple[int | None, bool]:
        return compute_price_staleness(self.workspace, price_at)


async def load_costing_snapshot(workspace_or_id: Workspace | str) -> CostingSnapshot:
    if isinstance(workspace_or_id, Workspace):
        workspace = workspace_or_id
        workspace_id = str(workspace.id) if workspace.id else ""
    else:
        workspace_id = str(workspace_or_id)
        ws = None
        if ObjectId.is_valid(workspace_id):
            ws = await Workspace.find_one(
                Workspace.id == ObjectId(workspace_id),
                Workspace.deleted_at == None,  # noqa: E711
            )
        if not ws:
            ws = await Workspace.find_one(
                Workspace.id == workspace_id,
                Workspace.deleted_at == None,  # noqa: E711
            )
        if not ws:
            ws = Workspace(owner_id="unknown")
        workspace = ws

    units_task = Unit.find(
        Unit.deleted_at == None,  # noqa: E711
        {"$or": [{"workspace_id": None}, {"workspace_id": workspace_id}]},
    ).to_list()

    ingredients_task = Ingredient.find(
        Ingredient.workspace_id == workspace_id,
        Ingredient.deleted_at == None,  # noqa: E711
    ).to_list()

    recipes_task = Recipe.find(
        Recipe.workspace_id == workspace_id,
        Recipe.deleted_at == None,  # noqa: E711
    ).to_list()

    presentations_task = Presentation.find(
        Presentation.workspace_id == workspace_id,
        Presentation.deleted_at == None,  # noqa: E711
    ).to_list()

    price_records_task = PriceRecord.find(
        PriceRecord.workspace_id == workspace_id,
        PriceRecord.deleted_at == None,  # noqa: E711
    ).sort("-recorded_at", "-created_at").to_list()

    suppliers_task = Supplier.find(
        Supplier.workspace_id == workspace_id,
        Supplier.deleted_at == None,  # noqa: E711
    ).to_list()

    (
        units_list,
        ingredients_list,
        recipes_list,
        presentations_list,
        price_records_list,
        suppliers_list,
    ) = await asyncio.gather(
        units_task,
        ingredients_task,
        recipes_task,
        presentations_task,
        price_records_task,
        suppliers_task,
    )

    units_by_id = {str(u.id): u for u in units_list}
    ingredients_by_id = {str(i.id): i for i in ingredients_list}
    recipes_by_id = {str(r.id): r for r in recipes_list}
    presentations_by_id = {str(p.id): p for p in presentations_list}
    suppliers_by_id = {str(s.id): s for s in suppliers_list}

    presentations_by_ingredient: dict[str, list[Presentation]] = {}
    for p in presentations_list:
        presentations_by_ingredient.setdefault(str(p.ingredient_id), []).append(p)

    latest_prices_by_presentation: dict[str, PriceRecord] = {}
    for pr in price_records_list:
        pid = str(pr.presentation_id)
        if pid not in latest_prices_by_presentation:
            latest_prices_by_presentation[pid] = pr

    current_presentation_by_ingredient: dict[str, CurrentPresentation] = {}
    for ing_id, pres_items in presentations_by_ingredient.items():
        candidates: list[tuple[Presentation, PriceRecord]] = []
        for p in pres_items:
            pr = latest_prices_by_presentation.get(str(p.id))
            if pr is not None:
                candidates.append((p, pr))
        if candidates:
            candidates.sort(key=_candidate_sort_key, reverse=True)
            winner = candidates[0]
            current_presentation_by_ingredient[ing_id] = CurrentPresentation(
                presentation=winner[0], price_record=winner[1]
            )

    return CostingSnapshot(
        workspace=workspace,
        units_by_id=units_by_id,
        ingredients_by_id=ingredients_by_id,
        recipes_by_id=recipes_by_id,
        presentations_by_id=presentations_by_id,
        presentations_by_ingredient=presentations_by_ingredient,
        latest_prices_by_presentation=latest_prices_by_presentation,
        suppliers_by_id=suppliers_by_id,
        current_presentation_by_ingredient=current_presentation_by_ingredient,
    )
