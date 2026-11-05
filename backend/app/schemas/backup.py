from datetime import datetime

from pydantic import BaseModel


class BackupInfo(BaseModel):
    id: str
    schema_version: int
    device_id: str
    exported_at: datetime
    created_at: datetime
    size_bytes: int
