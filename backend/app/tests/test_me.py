import pytest
from httpx import AsyncClient

from app.core.security import create_access_token


@pytest.mark.asyncio
async def test_health(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["app"] == "AyeKitchen"


@pytest.mark.asyncio
async def test_me_requires_token(client: AsyncClient):
    resp = await client.get("/api/v1/me/")
    assert resp.status_code in (401, 403)


@pytest.mark.asyncio
async def test_me_creates_personal_workspace_once(client: AsyncClient, auth_headers):
    first = await client.get("/api/v1/me/", headers=auth_headers)
    assert first.status_code == 200
    body = first.json()
    assert body["email"] == "test@ayeapps.com"
    assert body["workspace"]["currency"] == "MXN"

    second = await client.get("/api/v1/me/", headers=auth_headers)
    assert second.json()["workspace"]["id"] == body["workspace"]["id"]


@pytest.mark.asyncio
async def test_me_auto_provisions_user_from_aye_auth_token(client: AsyncClient):
    token, _, _ = create_access_token(
        subject="sso_user_789", email="mama@ayeapps.com", name="Mamá", apps_access={"kitchen": True}
    )
    resp = await client.get("/api/v1/me/", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    assert resp.json()["id"] == "sso_user_789"
    assert resp.json()["name"] == "Mamá"


@pytest.mark.asyncio
async def test_workspaces_are_isolated(client: AsyncClient, auth_headers, auth_headers_user_2):
    ws1 = (await client.get("/api/v1/me/", headers=auth_headers)).json()["workspace"]["id"]
    ws2 = (await client.get("/api/v1/me/", headers=auth_headers_user_2)).json()["workspace"]["id"]
    assert ws1 != ws2
