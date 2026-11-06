import gzip
from typing import Any

from fastapi import APIRouter, Query, Request, Response, status

from app.core.deps import CurrentWorkspace
from app.models.backup import Backup
from app.models.reference_image import ReferenceImage
from app.schemas.backup import BackupInfo, ReferenceImageInfo
from app.services.backup_service import (
    get_latest_backup,
    list_backups,
    upload_backup,
)
from app.services.export_service import export_workspace_data
from app.services.reference_service import (
    ReferenceProjection,
    delete_reference_image,
    get_reference_image,
    list_reference_images,
    save_reference_image,
)

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


def _serialize_reference_image_info(
    img: ReferenceImage | ReferenceProjection,
) -> ReferenceImageInfo:
    return ReferenceImageInfo(
        id=img.ref_id,
        sha256=img.sha256,
        size_bytes=img.size_bytes,
        content_type=img.content_type,
        updated_at=img.updated_at,
    )


@router.get("/references/", response_model=list[ReferenceImageInfo])
@router.get("/references", response_model=list[ReferenceImageInfo], include_in_schema=False)
async def list_references_endpoint(
    workspace: CurrentWorkspace,
) -> list[ReferenceImageInfo]:
    images = await list_reference_images(str(workspace.id))
    return [_serialize_reference_image_info(img) for img in images]


@router.put("/references/{id}", response_model=ReferenceImageInfo)
async def upload_reference_endpoint(
    id: str,
    request: Request,
    workspace: CurrentWorkspace,
    response: Response,
    sha256: str | None = Query(None),
) -> ReferenceImageInfo:
    content_type = request.headers.get("content-type")
    body = await request.body()
    image, created = await save_reference_image(
        workspace_id=str(workspace.id),
        ref_id=id,
        content_type=content_type,
        raw_body=body,
        sha256=sha256,
    )
    if created:
        response.status_code = status.HTTP_201_CREATED
    else:
        response.status_code = status.HTTP_200_OK
    return _serialize_reference_image_info(image)


@router.get("/references/{id}")
async def get_reference_endpoint(
    id: str,
    workspace: CurrentWorkspace,
) -> Response:
    image = await get_reference_image(str(workspace.id), id)
    return Response(content=image.data, media_type=image.content_type)


@router.delete("/references/{id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reference_endpoint(
    id: str,
    workspace: CurrentWorkspace,
) -> Response:
    await delete_reference_image(str(workspace.id), id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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
