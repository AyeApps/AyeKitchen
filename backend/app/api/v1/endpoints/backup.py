import gzip
from typing import Any

from fastapi import APIRouter, Query, Request, Response, status

from app.core.deps import CurrentWorkspace
from app.models.backup import Backup
from app.schemas.backup import BackupInfo
from app.services.backup_service import (
    get_latest_backup,
    list_backups,
    upload_backup,
)
from app.services.export_service import export_workspace_data

router = APIRouter()


def _serialize_backup_info(b: Backup) -> BackupInfo:
    return BackupInfo(
        id=str(b.id),
        schema_version=b.schema_version,
        device_id=b.device_id,
        exported_at=b.exported_at,
        created_at=b.created_at,
        size_bytes=b.size_bytes,
    )


@router.get("/latest")
async def get_latest_backup_endpoint(workspace: CurrentWorkspace) -> Response:
    backup = await get_latest_backup(str(workspace.id))
    decompressed = gzip.decompress(backup.data)
    return Response(content=decompressed, media_type="application/json")


@router.get("/export-current")
async def export_current_endpoint(workspace: CurrentWorkspace) -> dict[str, Any]:
    return await export_workspace_data(workspace)


@router.get("/", response_model=list[BackupInfo])
async def list_backups_endpoint(workspace: CurrentWorkspace) -> list[BackupInfo]:
    backups = await list_backups(str(workspace.id))
    return [_serialize_backup_info(b) for b in backups]


@router.put("/", response_model=BackupInfo, status_code=status.HTTP_201_CREATED)
async def upload_backup_endpoint(
    request: Request,
    workspace: CurrentWorkspace,
    base_backup_id: str | None = Query(None),
    force: bool = Query(False),
) -> BackupInfo:
    body = await request.body()
    backup = await upload_backup(
        str(workspace.id),
        body,
        base_backup_id=base_backup_id,
        force=force,
    )
    return _serialize_backup_info(backup)
