import json

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # ==========================================
    # 🌍 1. CORE / GLOBALES (Idéntico en todos los servicios)
    # ==========================================
    APP_NAME: str = "AyeKitchen"
    APP_ENV: str = "development"
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # Base de Datos Global
    MONGODB_URL: str = "mongodb://localhost:27017/ayekitchen_dev"
    DATABASE_NAME: str = "ayekitchen_dev"
    MONGODB_CERT_B64: str = ""
    MONGODB_CERT_PATH: str = ""

    # Seguridad Compartida
    JWT_SECRET_KEY: str = "super_secure_secret_key_minimum_32_characters_for_ayeapps_atelier"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # CORS Compartido
    CORS_ORIGINS: list[str] | str = [
        "http://localhost:3006",
        "https://kitchen.ayeapps.com",
        "https://ayeapps.com",
    ]

    # ==========================================
    # 🚀 2. ESPECÍFICAS DEL SERVICIO
    # ==========================================
    DEFAULT_CURRENCY: str = "MXN"
    DEFAULT_MARGIN_PERCENT: int = 40

    # ==========================================
    # ⚙️ 3. CONFIGURACIÓN Y VALIDADORES ESTÁNDAR
    # ==========================================
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    @field_validator("JWT_SECRET_KEY")
    @classmethod
    def validate_jwt_secret(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("JWT_SECRET_KEY must be at least 32 characters long.")
        return v

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def parse_cors_origins(cls, v: str | list[str]) -> list[str]:
        if isinstance(v, str):
            v_stripped = v.strip()
            if v_stripped.startswith("[") and v_stripped.endswith("]"):
                try:
                    return json.loads(v_stripped)
                except Exception:
                    cleaned = v_stripped.strip("[]").replace("'", '"')
                    try:
                        return json.loads(f"[{cleaned}]")
                    except Exception:
                        return [item.strip().strip("'\"") for item in v_stripped.strip("[]").split(",") if item.strip()]
            return [item.strip().strip("'\"") for item in v.split(",") if item.strip()]
        return v

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.lower() == "production"

settings = Settings()
