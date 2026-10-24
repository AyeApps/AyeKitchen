from fastapi import APIRouter

from app.core.deps import CurrentUser, CurrentWorkspace
from app.schemas.me import MeResponse, WorkspaceResponse

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
        ),
    )
