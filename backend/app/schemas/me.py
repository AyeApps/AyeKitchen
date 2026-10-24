from pydantic import BaseModel


class WorkspaceResponse(BaseModel):
    id: str
    name: str
    currency: str
    default_margin_percent: int
    price_stale_days: int


class MeResponse(BaseModel):
    id: str
    email: str
    name: str
    avatar_url: str | None = None
    workspace: WorkspaceResponse
