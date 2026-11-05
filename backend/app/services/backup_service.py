import gzip
import json
from datetime import UTC, datetime

from app.core.errors import AppError
from app.models.backup import Backup

MAX_BACKUP_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


async def list_backups(workspace_id: str) -> list[Backup]:
    return await Backup.find(
        Backup.workspace_id == workspace_id,
    ).sort(-Backup.created_at).limit(5).to_list()


async def get_latest_backup(workspace_id: str) -> Backup:
    latest = await Backup.find(
        Backup.workspace_id == workspace_id,
    ).sort(-Backup.created_at).first_or_none()
    if latest is None:
        raise AppError(
            status_code=404,
            detail="No se encontraron respaldos para este negocio",
            code="NOT_FOUND",
        )
    return latest


async def upload_backup(
    workspace_id: str,
    raw_body: bytes,
    base_backup_id: str | None = None,
    force: bool = False,
) -> Backup:
    if len(raw_body) > MAX_BACKUP_SIZE_BYTES:
        raise AppError(
            status_code=413,
            detail="El respaldo excede el límite de 10 MB",
            code="BACKUP_TOO_LARGE",
        )

    try:
        payload = json.loads(raw_body)
    except Exception as err:
        raise AppError(
            status_code=422,
            detail="El cuerpo no es un documento JSON válido",
            code="INVALID_BACKUP",
        ) from err

    if not isinstance(payload, dict):
        raise AppError(
            status_code=422,
            detail="El cuerpo del respaldo debe ser un objeto JSON",
            code="INVALID_BACKUP",
        )

    schema_version = payload.get("schema_version")
    if (
        schema_version is None
        or isinstance(schema_version, bool)
        or not isinstance(schema_version, int)
        or schema_version > 1
    ):
        raise AppError(
            status_code=422,
            detail="schema_version es inválido o mayor a la versión soportada",
            code="INVALID_BACKUP",
        )

    device_id = payload.get("device_id")
    if not isinstance(device_id, str) or not device_id.strip():
        raise AppError(
            status_code=422,
            detail="device_id es requerido y no puede estar vacío",
            code="INVALID_BACKUP",
        )
    device_id = device_id.strip()

    exported_at_raw = payload.get("exported_at")
    if not isinstance(exported_at_raw, str) or not exported_at_raw.strip():
        raise AppError(
            status_code=422,
            detail="exported_at es requerido",
            code="INVALID_BACKUP",
        )

    try:
        dt_str = exported_at_raw.strip()
        if dt_str.endswith("Z"):
            dt_str = dt_str[:-1] + "+00:00"
        exported_at = datetime.fromisoformat(dt_str)
        if exported_at.tzinfo is None:
            exported_at = exported_at.replace(tzinfo=UTC)
        else:
            exported_at = exported_at.astimezone(UTC)
    except Exception as err:
        raise AppError(
            status_code=422,
            detail="exported_at debe ser una fecha ISO 8601 válida",
            code="INVALID_BACKUP",
        ) from err

    base_id = base_backup_id.strip() if base_backup_id and base_backup_id.strip() else None

    # Regla de conflicto
    latest = await Backup.find(
        Backup.workspace_id == workspace_id,
    ).sort(-Backup.created_at).first_or_none()

    if (
        latest is not None
        and not force
        and str(latest.id) != base_id
        and latest.device_id != device_id
    ):
        exported_str = latest.exported_at.isoformat()
        raise AppError(
            status_code=409,
            detail=f"Hay un respaldo más reciente del {exported_str} realizado por otro dispositivo",
            code="BACKUP_CONFLICT",
        )

    compressed_data = gzip.compress(raw_body)

    backup = Backup(
        workspace_id=workspace_id,
        schema_version=schema_version,
        device_id=device_id,
        exported_at=exported_at,
        size_bytes=len(raw_body),
        data=compressed_data,
    )
    await backup.insert()

    # Conserva solo los 5 más recientes físicamente
    old_backups = await Backup.find(
        Backup.workspace_id == workspace_id,
    ).sort(-Backup.created_at).skip(5).to_list()

    for old in old_backups:
        await old.delete()

    return backup
