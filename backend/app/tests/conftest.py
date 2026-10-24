import pytest
from beanie import init_beanie
from httpx import ASGITransport, AsyncClient
from mongomock_motor import AsyncMongoMockClient

from app.core.security import create_access_token
from app.db.mongodb import DOCUMENT_MODELS
from app.models.user import User
from main import app


@pytest.fixture(scope="session", autouse=True)
async def init_test_db():
    client = AsyncMongoMockClient()
    db = client["aye_kitchen_test_db"]

    await init_beanie(database=db, document_models=DOCUMENT_MODELS)
    yield
    client.close()


@pytest.fixture(autouse=True)
async def clear_database():
    for model in DOCUMENT_MODELS:
        await model.delete_all()
    yield


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac


@pytest.fixture
async def test_user():
    user = User(
        id="user_test_123",
        email="test@ayeapps.com",
        name="Test User",
        is_active=True,
    )
    await user.insert()
    return user


@pytest.fixture
async def test_user_2():
    user = User(
        id="user_test_456",
        email="other@ayeapps.com",
        name="Other User",
        is_active=True,
    )
    await user.insert()
    return user


@pytest.fixture
def auth_headers(test_user):
    token, _, _ = create_access_token(
        subject=str(test_user.id),
        email=test_user.email,
        name=test_user.name,
        apps_access={"kitchen": True},
    )
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers_user_2(test_user_2):
    token, _, _ = create_access_token(
        subject=str(test_user_2.id),
        email=test_user_2.email,
        name=test_user_2.name,
        apps_access={"kitchen": True},
    )
    return {"Authorization": f"Bearer {token}"}
