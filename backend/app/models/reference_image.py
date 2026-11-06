from datetime import UTC, datetime

from beanie import Document
from pydantic import Field
from pymongo import ASCENDING, IndexModel


class ReferenceImage(Document):
    """Imagen de referencia guardada en el servidor (B12, docs/backup-format.md).

    El servidor no interpreta los bytes. Se guarda un documento por workspace_id + ref_id.
    """

    workspace_id: str
    ref_id: str
    content_type: str
    sha256: str
    size_bytes: int
    data: bytes = b""
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    class Settings:
        name = "reference_images"
        indexes = [
            IndexModel(
                [("workspace_id", ASCENDING), ("ref_id", ASCENDING)],
                unique=True,
            ),
        ]
