import hashlib
import re
from datetime import UTC, datetime

from pydantic import BaseModel

from app.core.errors import AppError
from app.models.reference_image import ReferenceImage

MAX_REFERENCE_SIZE_BYTES = 2 * 1024 * 1024  # 2 MB
REF_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/heic"}


class ReferenceProjection(BaseModel):
    ref_id: str
    content_type: str
    sha256: str
    size_bytes: int
    updated_at: datetime


async def list_reference_images(workspace_id: str) -> list[ReferenceProjection]:
    return await ReferenceImage.find(
        ReferenceImage.workspace_id == workspace_id,
    ).project(ReferenceProjection).to_list()


async def get_reference_image(workspace_id: str, ref_id: str) -> ReferenceImage:
    image = await ReferenceImage.find_one(
        ReferenceImage.workspace_id == workspace_id,
        ReferenceImage.ref_id == ref_id,
    )
    if image is None:
        raise AppError(
            status_code=404,
            detail="No se encontró la imagen de referencia",
            code="NOT_FOUND",
        )
    return image


async def save_reference_image(
    workspace_id: str,
    ref_id: str,
    content_type: str | None,
    raw_body: bytes,
    sha256: str | None,
) -> tuple[ReferenceImage, bool]:
    # 1. Tamaño (≤ 2 MB → si no BACKUP_TOO_LARGE)
    if len(raw_body) > MAX_REFERENCE_SIZE_BYTES:
        raise AppError(
            status_code=413,
            detail="La imagen de referencia excede el límite de 2 MB",
            code="BACKUP_TOO_LARGE",
        )

    # 2. Content-Type (image/jpeg o image/heic → si no INVALID_BACKUP)
    if not content_type:
        raise AppError(
            status_code=422,
            detail="Content-Type es requerido",
            code="INVALID_BACKUP",
        )
    media_type = content_type.split(";")[0].strip().lower()
    if media_type not in ALLOWED_CONTENT_TYPES:
        raise AppError(
            status_code=422,
            detail="Content-Type debe ser image/jpeg o image/heic",
            code="INVALID_BACKUP",
        )

    # 3. ID (1–64 caracteres [A-Za-z0-9_-] → si no INVALID_BACKUP)
    if not ref_id or not REF_ID_PATTERN.match(ref_id):
        raise AppError(
            status_code=422,
            detail="El id de referencia debe tener entre 1 y 64 caracteres válidos ([A-Za-z0-9_-])",
            code="INVALID_BACKUP",
        )

    # 4. SHA-256 coincida con el SHA-256 hex de los bytes (→ si no INVALID_BACKUP)
    computed_sha256 = hashlib.sha256(raw_body).hexdigest()
    if not sha256 or sha256.strip().lower() != computed_sha256:
        raise AppError(
            status_code=422,
            detail="La huella sha256 no coincide con los bytes recibidos",
            code="INVALID_BACKUP",
        )

    # 5. Crea o reemplaza (un documento por workspace_id + ref_id)
    existing = await ReferenceImage.find_one(
        ReferenceImage.workspace_id == workspace_id,
        ReferenceImage.ref_id == ref_id,
    )
    if existing is not None:
        existing.content_type = media_type
        existing.sha256 = computed_sha256
        existing.size_bytes = len(raw_body)
        existing.data = raw_body
        existing.updated_at = datetime.now(UTC)
        await existing.save()
        return existing, False

    image = ReferenceImage(
        workspace_id=workspace_id,
        ref_id=ref_id,
        content_type=media_type,
        sha256=computed_sha256,
        size_bytes=len(raw_body),
        data=raw_body,
        updated_at=datetime.now(UTC),
    )
    await image.insert()
    return image, True


async def delete_reference_image(workspace_id: str, ref_id: str) -> None:
    image = await ReferenceImage.find_one(
        ReferenceImage.workspace_id == workspace_id,
        ReferenceImage.ref_id == ref_id,
    )
    if image is not None:
        await image.delete()
