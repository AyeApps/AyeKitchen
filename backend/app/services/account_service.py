from datetime import UTC, datetime

from app.models.backup import Backup
from app.models.cost_version import CostVersion
from app.models.customer import Customer
from app.models.ingredient import Ingredient
from app.models.order import Expense, Order
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.reference_image import ReferenceImage
from app.models.supplier import Supplier
from app.models.unit import Unit
from app.models.user import User
from app.models.workspace import Workspace

# Modelos de negocio con datos pertenecientes a un workspace específico
BUSINESS_MODELS = [
    Unit,
    Ingredient,
    Supplier,
    Presentation,
    PriceRecord,
    Recipe,
    CostVersion,
    Customer,
    Order,
    Expense,
    Backup,
    ReferenceImage,
]


async def erase_workspace_data(workspace_id: str | Workspace) -> None:
    """Borra físicamente todos los documentos de negocio asociados a un workspace

    y restablece los ajustes del Workspace a sus valores de fábrica.
    """
    ws_id = str(workspace_id.id) if isinstance(workspace_id, Workspace) else str(workspace_id)
    if not ws_id:
        return

    for model in BUSINESS_MODELS:
        await model.find(model.workspace_id == ws_id).delete()

    ws = workspace_id if isinstance(workspace_id, Workspace) else await Workspace.get(ws_id)
    if ws is not None:
        ws.name = Workspace.model_fields["name"].default
        ws.currency = Workspace.model_fields["currency"].default
        ws.timezone = Workspace.model_fields["timezone"].default
        ws.default_margin_percent = Workspace.model_fields["default_margin_percent"].default
        ws.price_stale_days = Workspace.model_fields["price_stale_days"].default
        ws.updated_at = datetime.now(UTC)
        await ws.save()


async def delete_account(user: User | str, workspace: Workspace | str) -> None:
    """Borra físicamente todos los datos del workspace y elimina el Workspace y User de Kitchen."""
    ws_id = str(workspace.id) if isinstance(workspace, Workspace) else str(workspace)
    ws = workspace if isinstance(workspace, Workspace) else await Workspace.get(ws_id)
    u_id = str(user.id) if isinstance(user, User) else str(user)
    u = user if isinstance(user, User) else await User.get(u_id)

    await erase_workspace_data(ws_id)

    if ws is not None:
        await ws.delete()
    if u is not None:
        await u.delete()
