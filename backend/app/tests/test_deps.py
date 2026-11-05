from datetime import UTC, datetime

import pytest
from httpx import AsyncClient

from app.core.security import create_access_token
from app.models.revoked_token import RevokedToken
from app.models.user import User
from app.models.workspace import Workspace


@pytest.mark.asyncio
async def test_revoked_token_returns_401(client: AsyncClient, test_user: User):
    token, jti, expire = create_access_token(
        subject=str(test_user.id),
        email=test_user.email,
        name=test_user.name,
    )
    revoked = RevokedToken(
        jti=jti,
        user_id=str(test_user.id),
        revoked_at=datetime.now(UTC),
        expires_at=expire,
    )
    await revoked.insert()

    resp = await client.get(
        "/api/v1/me/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401
    assert "revocada" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_new_user_auto_provisions_and_creates_workspace(client: AsyncClient):
    new_sub = "user_brand_new_999"
    token, _, _ = create_access_token(
        subject=new_sub,
        email="brand_new@ayeapps.com",
        name="Chef Nuevo",
    )

    assert await User.get(new_sub) is None
    assert await Workspace.find_one({"members.user_id": new_sub}) is None

    resp = await client.get(
        "/api/v1/me/",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == new_sub
    assert data["email"] == "brand_new@ayeapps.com"
    assert data["name"] == "Chef Nuevo"
    assert data["workspace"]["name"] == "Mi cocina"

    db_user = await User.get(new_sub)
    assert db_user is not None
    assert db_user.email == "brand_new@ayeapps.com"
    assert db_user.is_active is True

    db_ws = await Workspace.find_one({"members.user_id": new_sub})
    assert db_ws is not None
    assert db_ws.owner_id == new_sub
    assert any(m.user_id == new_sub and m.role == "owner" for m in db_ws.members)


@pytest.mark.asyncio
async def test_get_me_queries_in_parallel_single_round(
    client: AsyncClient,
    auth_headers,
    monkeypatch,
):
    # Asegurar que el usuario y su workspace ya existan en la BD
    warmup_resp = await client.get("/api/v1/me/", headers=auth_headers)
    assert warmup_resp.status_code == 200

    revoked_calls = 0
    user_calls = 0
    workspace_calls = 0

    orig_revoked_find_one = RevokedToken.find_one
    orig_user_get = User.get
    orig_workspace_find_one = Workspace.find_one

    async def counted_revoked_find_one(*args, **kwargs):
        nonlocal revoked_calls
        revoked_calls += 1
        return await orig_revoked_find_one(*args, **kwargs)

    async def counted_user_get(*args, **kwargs):
        nonlocal user_calls
        user_calls += 1
        return await orig_user_get(*args, **kwargs)

    async def counted_workspace_find_one(*args, **kwargs):
        nonlocal workspace_calls
        workspace_calls += 1
        return await orig_workspace_find_one(*args, **kwargs)

    monkeypatch.setattr(RevokedToken, "find_one", counted_revoked_find_one)
    monkeypatch.setattr(User, "get", counted_user_get)
    monkeypatch.setattr(Workspace, "find_one", counted_workspace_find_one)

    resp = await client.get("/api/v1/me/", headers=auth_headers)
    assert resp.status_code == 200

    assert revoked_calls == 1
    assert user_calls == 1
    assert workspace_calls == 1
