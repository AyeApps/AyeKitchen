from fastapi import APIRouter

from app.core.deps import CurrentUser, CurrentWorkspace
from app.schemas.me import ChangesResponse, MeResponse, WorkspaceResponse
from app.services.changes_service import get_workspace_changes

router = APIRouter()


@router.get("/", response_model=MeResponse)
async def get_me(current_user: CurrentUser, workspace: CurrentWorkspace):
    return MeResponse(
        id=str(current_user.id),
        email=current_user.email,
        name=current_user.name,
        avatar_url=current_user.avatar_url,
        workspace=WorkspaceResponse(
            id=str(workspace.id),
            name=workspace.name,
            currency=workspace.currency,
            default_margin_percent=workspace.default_margin_percent,
            price_stale_days=workspace.price_stale_days,
        ),
    )


@router.get("/changes", response_model=ChangesResponse)
async def get_changes(workspace: CurrentWorkspace):
    return await get_workspace_changes(str(workspace.id))

