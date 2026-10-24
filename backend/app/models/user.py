from datetime import UTC, datetime

from beanie import Document
from pydantic import EmailStr, Field


class User(Document):
    id: str = Field(default=..., alias="_id")  # Matches sub from central aye-auth
    email: EmailStr
    name: str = "Usuario Aye"
    avatar_url: str | None = None
    is_active: bool = True
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    deleted_at: datetime | None = None

    class Settings:
        name = "users"
        use_state_management = True
