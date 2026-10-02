"""Authentication service handling user registration, verification, credentials, and token lifecycle.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from datetime import datetime, timedelta, timezone
from typing import Any, Optional, Tuple, Union
import uuid

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    get_password_hash,
    hash_refresh_token,
    verify_password,
)
from app.core.google_auth import verify_google_id_token
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import (
    InactiveUserError,
    InvalidCredentialsError,
    NextActionDomainError,
    RefreshTokenExpiredError,
    RefreshTokenNotFoundError,
    RefreshTokenRevokedError,
    UserAlreadyExistsError,
    UserNotFoundError,
)


def normalize_email(email: str) -> str:
    """Normalize email address to lowercase and strip surrounding whitespace."""
    return email.strip().lower()


def get_user_by_email(db: Optional[Session] = None, email: str = "") -> Optional[Any]:
    """Retrieve user by normalized email."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        return gateway.user_service.get_user_by_email(db=db, email=email)

    normalized = normalize_email(email)
    stmt = select(User).where(func.lower(User.email) == normalized)
    return db.scalars(stmt).first() if db else None


def get_user_by_id(
    db: Optional[Session] = None,
    user_id: Union[str, uuid.UUID] = "",
    allow_inactive: bool = False,
) -> Any:
    """Retrieve active user by UUID or raise appropriate domain error."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        return gateway.user_service.get_user_by_id(
            db=db, user_id=user_id, allow_inactive=allow_inactive
        )

    parsed_id = uuid.UUID(str(user_id)) if not isinstance(user_id, uuid.UUID) else user_id
    user = db.get(User, parsed_id) if db else None
    if not user:
        raise UserNotFoundError(parsed_id)
    if not allow_inactive and not user.is_active:
        raise InactiveUserError()
    return user


def register_user(
    db: Optional[Session] = None,
    name: str = "",
    email: str = "",
    password: str = "",
) -> Any:
    """Register a new user account with hashed password and email uniqueness check."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        return gateway.user_service.register_user(
            db=db, name=name, email=email, password=password
        )

    if len(password) < 8 or len(password) > 128:
        raise NextActionDomainError("Password must be between 8 and 128 characters.")

    normalized = normalize_email(email)
    existing = get_user_by_email(db, normalized)
    if existing:
        raise UserAlreadyExistsError(normalized)

    hashed_pw = get_password_hash(password)
    user = User(
        name=name.strip(),
        email=normalized,
        password_hash=hashed_pw,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def create_refresh_token_for_user(
    db: Optional[Session] = None,
    user: Any = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> Tuple[Any, str]:
    """Generate a high-entropy refresh token, store its SHA-256 hash, and return (record, raw_token)."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        raw_token, doc = gateway._get_mongo_user().create_refresh_token_for_user(
            db=db,
            user_id=getattr(user, "id", str(user)),
            client_ip=ip_address,
            user_agent=user_agent,
        )
        return doc, raw_token

    raw_token = generate_refresh_token()
    token_hash = hash_refresh_token(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    token_record = RefreshToken(
        user_id=user.id,
        token_hash=token_hash,
        expires_at=expires_at,
        is_revoked=False,
        ip_address=ip_address,
        user_agent=user_agent[:500] if user_agent else None,
    )
    db.add(token_record)
    db.commit()
    db.refresh(token_record)
    return token_record, raw_token


def authenticate_user(
    db: Optional[Session] = None,
    email: str = "",
    password: str = "",
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> Tuple[Any, str, int, str]:
    """Authenticate user credentials and issue signed JWT access token and refresh token."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        user = gateway.user_service.authenticate_user(db=db, email=email, password=password)
        access_token, raw_refresh, _ = gateway._get_mongo_user().create_tokens(
            db=db, user=user, user_agent=user_agent, ip_address=ip_address
        )
        expires_in = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        return user, access_token, expires_in, raw_refresh

    normalized = normalize_email(email)
    user = get_user_by_email(db, normalized)
    if not user:
        verify_password(password, "$2b$12$e8YQ306bK0Jk15.1o8v0I.72F8eFv9Fq9q9q9q9q9q9q9q9q9q9q9")
        raise InvalidCredentialsError()

    if not verify_password(password, user.password_hash):
        raise InvalidCredentialsError()

    if not user.is_active:
        raise InactiveUserError()

    token, expires_in = create_access_token(subject=str(user.id))
    _, raw_refresh_token = create_refresh_token_for_user(
        db=db,
        user=user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return user, token, expires_in, raw_refresh_token


def authenticate_google_user(
    db: Optional[Session] = None,
    id_token: str = "",
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> Tuple[Any, str, int, str]:
    """Authenticate or register user via verified Google ID token and return NextAction JWT pair."""
    identity = verify_google_id_token(id_token)
    gateway = get_persistence_gateway()
    user = gateway.user_service.authenticate_or_create_google_user(
        db=db,
        google_id=identity.google_id,
        email=identity.email,
        name=identity.name,
    )
    if gateway.is_mongodb:
        access_token, raw_refresh, _ = gateway._get_mongo_user().create_tokens(
            db=db, user=user, user_agent=user_agent, ip_address=ip_address
        )
        expires_in = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        return user, access_token, expires_in, raw_refresh

    token, expires_in = create_access_token(subject=str(user.id))
    _, raw_refresh_token = create_refresh_token_for_user(
        db=db,
        user=user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return user, token, expires_in, raw_refresh_token


def rotate_refresh_token(
    db: Optional[Session] = None,
    raw_token: str = "",
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> Tuple[Any, str, int, str]:
    """Rotate an existing refresh token with replay-attack detection."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        new_raw, new_doc, user = gateway._get_mongo_user().rotate_refresh_token(
            db=db, token_str=raw_token, client_ip=ip_address, user_agent=user_agent
        )
        access_token, expires_in = create_access_token(subject=str(user.id))
        return user, access_token, expires_in, new_raw

    token_hash = hash_refresh_token(raw_token)
    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    token_record = db.scalars(stmt).first()

    if not token_record:
        raise RefreshTokenNotFoundError()

    now = datetime.now(timezone.utc)

    if token_record.is_revoked:
        revoke_all_stmt = (
            update(RefreshToken)
            .where(RefreshToken.user_id == token_record.user_id, RefreshToken.is_revoked == False)
            .values(is_revoked=True, revoked_at=now)
        )
        db.execute(revoke_all_stmt)
        db.commit()
        raise RefreshTokenRevokedError(
            "Refresh token has already been revoked. Replay detected; all sessions invalidated."
        )

    if token_record.expires_at < now:
        token_record.is_revoked = True
        token_record.revoked_at = now
        db.commit()
        raise RefreshTokenExpiredError()

    user = db.get(User, token_record.user_id)
    if not user:
        raise UserNotFoundError(token_record.user_id)
    if not user.is_active:
        raise InactiveUserError()

    new_raw = generate_refresh_token()
    new_hash = hash_refresh_token(new_raw)
    new_record = RefreshToken(
        user_id=user.id,
        token_hash=new_hash,
        expires_at=now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        is_revoked=False,
        ip_address=ip_address,
        user_agent=user_agent[:500] if user_agent else None,
    )
    db.add(new_record)
    db.flush()

    token_record.is_revoked = True
    token_record.revoked_at = now
    token_record.replaced_by_id = new_record.id

    new_access_token, expires_in = create_access_token(subject=str(user.id))

    db.commit()
    db.refresh(new_record)
    return user, new_access_token, expires_in, new_raw


def revoke_refresh_token(db: Optional[Session] = None, raw_token: str = "") -> bool:
    """Explicitly revoke a refresh token."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        gateway.user_service.revoke_refresh_token(db=db, refresh_token_str=raw_token)
        return True

    token_hash = hash_refresh_token(raw_token)
    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    token_record = db.scalars(stmt).first() if db else None

    if not token_record or token_record.is_revoked:
        return False

    token_record.is_revoked = True
    token_record.revoked_at = datetime.now(timezone.utc)
    db.commit()
    return True


def change_password(
    db: Optional[Session] = None,
    user: Any = None,
    current_password: str = "",
    new_password: str = "",
) -> Any:
    """Verify current credentials and securely update password hash."""
    gateway = get_persistence_gateway()
    if gateway.is_mongodb:
        uid = getattr(user, "id", str(user))
        gateway._get_mongo_user().change_password(
            db=db,
            user_id=uid,
            old_password=current_password,
            new_password=new_password,
        )
        return gateway.user_service.get_user_by_id(db=db, user_id=uid)

    if not verify_password(current_password, user.password_hash):
        raise InvalidCredentialsError()

    if current_password == new_password:
        raise NextActionDomainError("New password must be different from current password.")

    if len(new_password) < 8 or len(new_password) > 128:
        raise NextActionDomainError("Password must be between 8 and 128 characters.")

    user.password_hash = get_password_hash(new_password)
    db.commit()
    db.refresh(user)
    return user
