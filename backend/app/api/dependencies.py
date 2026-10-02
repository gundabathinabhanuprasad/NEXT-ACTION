"""FastAPI endpoint dependencies including database sessions and JWT authentication."""

from typing import Annotated, Generator, Optional
import uuid
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import jwt
from sqlalchemy.orm import Session
from app.core.security import decode_access_token
from app.db.session import get_db
from app.models.user import User
from app.services.auth_service import get_user_by_id
from app.services.exceptions import (
    AuthenticationRequiredError,
    InactiveUserError,
    InvalidTokenError,
    UserNotFoundError,
)

# HTTP Bearer scheme for Swagger UI & Authorization header parsing
http_bearer_scheme = HTTPBearer(auto_error=False)

DatabaseDep = Annotated[Session, Depends(get_db)]


def get_current_user(
    db: DatabaseDep,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(http_bearer_scheme),
) -> User:
    """Validate JWT bearer token and retrieve the authenticated active user."""
    if not credentials or not credentials.credentials:
        raise AuthenticationRequiredError()

    token = credentials.credentials
    try:
        payload = decode_access_token(token)
    except jwt.ExpiredSignatureError:
        raise InvalidTokenError("Authentication token has expired.")
    except jwt.PyJWTError:
        raise InvalidTokenError("Invalid authentication token signature or payload.")

    sub = payload.get("sub")
    if not sub:
        raise InvalidTokenError("Token missing subject identifier.")

    try:
        user_id_val = uuid.UUID(sub)
    except (ValueError, AttributeError):
        user_id_val = str(sub)

    try:
        user = get_user_by_id(db, user_id_val)
    except UserNotFoundError:
        raise InvalidTokenError("Authenticated user account no longer exists.")

    return user


CurrentUserDep = Annotated[User, Depends(get_current_user)]
