import asyncio
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.security import decode_token
from app.models.revoked_token import RevokedToken
from app.models.user import User
from app.models.workspace import MemberRole, Workspace, WorkspaceMember

security = HTTPBearer(auto_error=True)


async def _get_auth_context(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
) -> tuple[User, Workspace]:
    token = credentials.credentials
    try:
        payload = decode_token(token)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token inválido o expirado: {e!s}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from e

    if payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Tipo de token incorrecto. Se requiere token de acceso.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Identificador de usuario (sub) ausente en el token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    jti = payload.get("jti")
    revoked_task = RevokedToken.find_one(RevokedToken.jti == jti) if jti else None
    user_task = User.get(str(user_id))
    workspace_task = Workspace.find_one(
        {"members.user_id": str(user_id), "deleted_at": None}
    )

    if revoked_task is not None:
        revoked, user, workspace = await asyncio.gather(
            revoked_task,
            user_task,
            workspace_task,
        )
    else:
        revoked = None
        user, workspace = await asyncio.gather(
            user_task,
            workspace_task,
        )

    # 1. Si el token está revocado, el mismo 401 de hoy, aunque las otras dos consultas ya hayan vuelto.
    if revoked:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="La sesión ha sido revocada. Inicia sesión nuevamente.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 2. Si el usuario no existe, se auto-aprovisiona como hoy y se vuelve a leer.
    if user:
        if not user.is_active or user.deleted_at is not None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Cuenta de usuario inactiva o eliminada.",
                headers={"WWW-Authenticate": "Bearer"},
            )
    else:
        # Transparent auto-provisioning from central identity token
        user = User(
            id=str(user_id),
            email=payload.get("email", f"{user_id}@ayeapps.com"),
            name=payload.get("name", "Usuario Aye"),
            is_active=True,
        )
        try:
            await user.insert()
        except Exception:
            # In race condition, fetch again
            user = await User.get(str(user_id))

        if not user:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Error al aprovisionar el usuario local.",
            )

    # 3. Si el workspace no existe, se crea como hoy.
    if not workspace:
        workspace = Workspace(
            name="Mi cocina",
            owner_id=str(user.id),
            members=[WorkspaceMember(user_id=str(user.id), role=MemberRole.owner)],
        )
        await workspace.insert()

    return user, workspace


async def get_current_user(
    ctx: Annotated[tuple[User, Workspace], Depends(_get_auth_context)],
) -> User:
    return ctx[0]


CurrentUser = Annotated[User, Depends(get_current_user)]


async def get_current_workspace(
    ctx: Annotated[tuple[User, Workspace], Depends(_get_auth_context)],
) -> Workspace:
    """Workspace activo del usuario. Si no tiene ninguno, se crea su cocina personal.

    Todo endpoint de negocio filtra por workspace.id; nunca por user_id directamente.
    """
    return ctx[1]


CurrentWorkspace = Annotated[Workspace, Depends(get_current_workspace)]
