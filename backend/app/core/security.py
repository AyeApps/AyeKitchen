import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import bcrypt
from jose import JWTError, jwt

from app.core.config import settings


def hash_password(password: str) -> str:
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode("utf-8"), salt).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
    except Exception:
        return False


def create_access_token(
    subject: str,
    email: str = "",
    name: str = "",
    apps_access: dict[str, bool] | None = None,
    expires_delta: timedelta | None = None,
) -> tuple[str, str, datetime]:
    if expires_delta:
        expire = datetime.now(UTC) + expires_delta
    else:
        expire = datetime.now(UTC) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    jti = str(uuid.uuid4())
    to_encode: dict[str, Any] = {
        "sub": str(subject),
        "email": email,
        "name": name,
        "type": "access",
        "jti": jti,
        "exp": expire,
        "iat": datetime.now(UTC),
        "apps_access": apps_access or {"kitchen": True},
    }
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt, jti, expire


def create_refresh_token(
    subject: str,
    expires_delta: timedelta | None = None,
) -> tuple[str, str, datetime]:
    if expires_delta:
        expire = datetime.now(UTC) + expires_delta
    else:
        expire = datetime.now(UTC) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    jti = str(uuid.uuid4())
    to_encode: dict[str, Any] = {
        "sub": str(subject),
        "type": "refresh",
        "jti": jti,
        "exp": expire,
        "iat": datetime.now(UTC),
    }
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt, jti, expire


def decode_token(token: str) -> dict[str, Any]:
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
        return payload
    except JWTError as e:
        raise ValueError(f"Invalid token signature or expired: {e!s}") from e
