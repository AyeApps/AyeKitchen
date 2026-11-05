from datetime import datetime

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


class ChangesResponse(BaseModel):
    home: datetime | None = None
    orders: datetime | None = None
    recipes: datetime | None = None
    catalog: datetime | None = None
    customers: datetime | None = None

