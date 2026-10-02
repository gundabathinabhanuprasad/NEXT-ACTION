"""Security and cryptographic utilities for NextAction."""

from datetime import datetime, timedelta, timezone
import hashlib
import secrets
from typing import Any, Dict, Optional
import uuid
import bcrypt
import jwt
from app.core.config import settings


def generate_refresh_token() -> str:
    """Generate a cryptographically secure high-entropy random string for refresh tokens."""
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    """Compute deterministic SHA-256 hash of a refresh token for safe server-side storage."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def get_password_hash(password: str) -> str:
    """Hash a plaintext password using bcrypt with a salt."""
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode("utf-8"), salt)
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plaintext password against a stored bcrypt hash in constant time."""
    try:
        return bcrypt.checkpw(
            plain_password.encode("utf-8"),
            hashed_password.encode("utf-8"),
        )
    except Exception:
        return False


def create_access_token(
    subject: str,
    expires_delta: Optional[timedelta] = None,
    extra_claims: Optional[Dict[str, Any]] = None,
    claims: Optional[Dict[str, Any]] = None,
) -> tuple[str, int]:
    """Create a signed JWT access token.

    Returns a tuple of (token_string, expires_in_seconds).
    """
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
        expires_in = int(expires_delta.total_seconds())
    else:
        expires_in = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        expire = now + timedelta(seconds=expires_in)

    to_encode: Dict[str, Any] = {
        "sub": str(subject),
        "jti": str(uuid.uuid4()),
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
        "type": "access",
    }
    merged_claims = {**(extra_claims or {}), **(claims or {})}
    if merged_claims:
        to_encode.update(merged_claims)

    encoded_jwt = jwt.encode(
        to_encode,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )
    return encoded_jwt, expires_in


def decode_access_token(token: str) -> Dict[str, Any]:
    """Decode and validate a signed JWT token.

    Raises jwt.PyJWTError (e.g. ExpiredSignatureError, InvalidTokenError) on failure.
    """
    payload = jwt.decode(
        token,
        settings.JWT_SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM],
        options={"require": ["sub", "iat", "exp"]},
    )
    token_type = payload.get("type")
    if token_type is not None and token_type != "access":
        raise jwt.InvalidTokenError(f"Invalid token type: expected 'access', got '{token_type}'")
    return payload
