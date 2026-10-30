import base64
import os

from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient

from app.core.config import settings
from app.core.logging import logger
from app.models.customer import Customer
from app.models.ingredient import Ingredient
from app.models.order import Expense, Order
from app.models.presentation import Presentation, PriceRecord
from app.models.recipe import Recipe
from app.models.revoked_token import RevokedToken
from app.models.supplier import Supplier
from app.models.unit import Unit
from app.models.user import User
from app.models.workspace import Workspace

client: AsyncIOMotorClient = None

# Única lista de modelos: la usan init_db y los tests (app/tests/conftest.py)
DOCUMENT_MODELS = [
    User,
    RevokedToken,
    Workspace,
    Unit,
    Ingredient,
    Supplier,
    Presentation,
    PriceRecord,
    Recipe,
    Customer,
    Order,
    Expense,
]


async def init_db():
    global client
    cert_path = settings.MONGODB_CERT_PATH
    if settings.MONGODB_CERT_B64 and settings.MONGODB_CERT_B64.strip():
        temp_cert = "/tmp/aye_kitchen_cert.pem"
        try:
            cert_bytes = base64.b64decode(settings.MONGODB_CERT_B64.strip())
            with open(temp_cert, "wb") as f:
                f.write(cert_bytes)
            cert_path = temp_cert
            logger.info("Decoded X.509 certificate from MONGODB_CERT_B64 successfully.")
        except Exception as e:
            logger.error(f"Error decoding MONGODB_CERT_B64: {e}")

    client_kwargs = {
        "serverSelectionTimeoutMS": 5000,
    }

    if cert_path and os.path.exists(cert_path):
        client_kwargs["tls"] = True
        client_kwargs["tlsCertificateKeyFile"] = cert_path
        client_kwargs["authMechanism"] = "MONGODB-X509"
        client_kwargs["authSource"] = "$external"
        logger.info(f"Connecting to MongoDB with X.509 Certificate ({cert_path})...")
    else:
        logger.info(f"Connecting to MongoDB at {settings.MONGODB_URL.split('@')[-1]}...")

    client = AsyncIOMotorClient(settings.MONGODB_URL, **client_kwargs)
    db = client[settings.DATABASE_NAME]

    await init_beanie(database=db, document_models=DOCUMENT_MODELS)
    logger.info(f"Beanie initialized successfully with database: {settings.DATABASE_NAME}")


async def close_db():
    global client
    if client:
        client.close()
        logger.info("MongoDB connection closed.")
