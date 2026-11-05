from datetime import UTC, datetime

from beanie import Document, Indexed
from pydantic import Field
from pymongo import ASCENDING, DESCENDING, IndexModel


class Backup(Document):
    """Respaldo del teléfono (B11, docs/backup-format.md). El servidor no interpreta los datos.

    `data` es el JSON tal cual lo subió el teléfono, comprimido con gzip. Se conservan los 5 más
    recientes por workspace y los demás se borran físicamente: son copias, no historial.
    """

    workspace_id: Indexed(str)
    schema_version: int
    device_id: str
    exported_at: datetime
    size_bytes: int  # JSON sin comprimir
    data: bytes  # gzip del JSON
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    class Settings:
        name = "backups"
        indexes = [IndexModel([("workspace_id", ASCENDING), ("created_at", DESCENDING)])]
