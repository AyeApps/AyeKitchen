from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.security import decode_token
from app.models.revoked_token import RevokedToken
from app.models.user import User
from app.models.workspace import MemberRole, Workspace, WorkspaceMember

security = HTTPBearer(auto_error=True)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
) -> User:
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

    # 1. Check token revocation
    jti = payload.get("jti")
    if jti:
        revoked = await RevokedToken.find_one(RevokedToken.jti == jti)
        if revoked:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="La sesión ha sido revocada. Inicia sesión nuevamente.",
                headers={"WWW-Authenticate": "Bearer"},
            )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Identificador de usuario (sub) ausente en el token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 2. Lookup user in local database
    user = await User.get(str(user_id))
    if user:
        if not user.is_active or user.deleted_at is not None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Cuenta de usuario inactiva o eliminada.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return user

    # 3. Transparent auto-provisioning from central identity token
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

    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


async def get_current_workspace(current_user: CurrentUser) -> Workspace:
    """Workspace activo del usuario. Si no tiene ninguno, se crea su cocina personal.

    Todo endpoint de negocio filtra por workspace.id; nunca por user_id directamente.
    """
    workspace = await Workspace.find_one(
        {"members.user_id": str(current_user.id), "deleted_at": None},
    )
    if workspace:
        return workspace

    workspace = Workspace(
        name="Mi cocina",
        owner_id=str(current_user.id),
        members=[WorkspaceMember(user_id=str(current_user.id), role=MemberRole.owner)],
    )
    await workspace.insert()
    return workspace


CurrentWorkspace = Annotated[Workspace, Depends(get_current_workspace)]
