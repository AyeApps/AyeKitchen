from datetime import datetime

from beanie import Document
from pydantic import Field
from pymongo import ASCENDING, IndexModel


class RevokedToken(Document):
    jti: str = Field(..., index=True)
    user_id: str
    revoked_at: datetime
    expires_at: datetime

    class Settings:
        name = "revoked_tokens"
        indexes = [
            IndexModel([("jti", ASCENDING)], unique=True),
            IndexModel([("expires_at", ASCENDING)], expireAfterSeconds=0),
        ]
