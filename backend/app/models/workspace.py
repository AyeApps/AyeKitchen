from enum import StrEnum

from beanie import Indexed
from pydantic import BaseModel, Field

from app.core.config import settings
from app.models.base import SoftDeleteDocument


class MemberRole(StrEnum):
    owner = "owner"
    member = "member"


class WorkspaceMember(BaseModel):
    user_id: str
    role: MemberRole = MemberRole.member


class Workspace(SoftDeleteDocument):
    """El negocio. Hoy cada usuario tiene uno personal; después puede haber ayudantes."""

    name: str = "Mi cocina"
    owner_id: Indexed(str)
    members: list[WorkspaceMember] = Field(default_factory=list)
    currency: str = settings.DEFAULT_CURRENCY
    timezone: str = "America/Mexico_City"  # Límites de mes en el resumen
    default_margin_percent: int = Field(default=settings.DEFAULT_MARGIN_PERCENT, ge=0, le=1000)

    class Settings:
        name = "workspaces"
        use_state_management = True
