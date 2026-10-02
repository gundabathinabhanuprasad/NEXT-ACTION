"""PostgreSQL / SQLAlchemy User and Auth Service Adapter.

Preserves exact user registration, authentication, token rotation, and team listing logic.
"""

from datetime import datetime, timedelta, timezone
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import func, or_, select, update
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    get_password_hash,
    hash_refresh_token,
    verify_password,
)
from app.db.session import SessionLocal
from app.models.refresh_token import RefreshToken
from app.models.user import User
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
    """Normalize email address to lowercase and strip whitespace."""
    return email.strip().lower()


class PostgresUserService:
    """PostgreSQL user and authentication service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def get_user_by_id(
        self,
        db: Optional[Session] = None,
        user_id: Union[str, uuid.UUID] = "",
        allow_inactive: bool = False,
    ) -> User:
        """Retrieve user by UUID."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(user_id))
            user = session.get(User, parsed_id)
            if not user:
                raise UserNotFoundError(parsed_id)
            if not allow_inactive and not user.is_active:
                raise InactiveUserError()
            return user
        finally:
            if close_needed:
                session.close()

    def get_user_by_email(
        self,
        db: Optional[Session] = None,
        email: str = "",
    ) -> Optional[User]:
        """Retrieve user by normalized email."""
        session, close_needed = self._ensure_session(db)
        try:
            normalized = normalize_email(email)
            stmt = select(User).where(func.lower(User.email) == normalized)
            return session.scalars(stmt).first()
        finally:
            if close_needed:
                session.close()

    def register_user(
        self,
        db: Optional[Session] = None,
        name: str = "",
        email: str = "",
        password: str = "",
    ) -> User:
        """Register a new user account with hashed password."""
        if len(password) < 8 or len(password) > 128:
            raise NextActionDomainError("Password must be between 8 and 128 characters.")

        session, close_needed = self._ensure_session(db)
        try:
            existing = self.get_user_by_email(session, email)
            if existing:
                raise UserAlreadyExistsError(email)

            user = User(
                name=name.strip(),
                email=normalize_email(email),
                password_hash=get_password_hash(password),
                is_active=True,
            )
            session.add(user)
            session.commit()
            session.refresh(user)

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_user(user, DualWriteOperation.CREATE)

            return user
        finally:
            if close_needed:
                session.close()

    def authenticate_user(
        self,
        db: Optional[Session] = None,
        email: str = "",
        password: str = "",
    ) -> User:
        """Authenticate user by email and password."""
        session, close_needed = self._ensure_session(db)
        try:
            user = self.get_user_by_email(session, email)
            if not user:
                raise InvalidCredentialsError()

            if not verify_password(password, user.password_hash):
                raise InvalidCredentialsError()

            if not user.is_active:
                raise InactiveUserError()

            return user
        finally:
            if close_needed:
                session.close()

    def authenticate_or_create_google_user(
        self,
        db: Optional[Session] = None,
        google_id: str = "",
        email: str = "",
        name: str = "",
    ) -> User:
        """Authenticate existing Google user, link existing email account, or create new user."""
        session, close_needed = self._ensure_session(db)
        try:
            norm_email = normalize_email(email)

            # Lookup by email (safe account linking policy)
            user = self.get_user_by_email(session, norm_email)
            if user:
                if not user.is_active:
                    raise InactiveUserError(f"User account '{user.email}' is inactive.")
                return user

            # Create new user with verified Google identity
            display_name = name.strip() if name and name.strip() else norm_email.split("@")[0]
            new_user = User(
                name=display_name,
                email=norm_email,
                password_hash="",
                is_active=True,
            )
            session.add(new_user)
            session.commit()
            session.refresh(new_user)
            return new_user
        finally:
            if close_needed:
                session.close()

    def list_users(
        self,
        db: Optional[Session] = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 50,
    ) -> Tuple[List[User], int]:
        """Retrieve filtered and paginated list of users."""
        session, close_needed = self._ensure_session(db)
        try:
            stmt = select(User)
            count_stmt = select(func.count(User.id))

            if search and search.strip():
                term = f"%{search.strip().lower()}%"
                search_filter = or_(
                    func.lower(User.name).like(term),
                    func.lower(User.email).like(term),
                )
                stmt = stmt.where(search_filter)
                count_stmt = count_stmt.where(search_filter)

            if is_active is not None:
                stmt = stmt.where(User.is_active == is_active)
                count_stmt = count_stmt.where(User.is_active == is_active)

            total = session.scalar(count_stmt) or 0
            offset = max(0, (page - 1) * page_size)
            stmt = stmt.order_by(User.name.asc(), User.created_at.asc()).offset(offset).limit(page_size)
            items = list(session.scalars(stmt).all())

            return items, total
        finally:
            if close_needed:
                session.close()

    def create_tokens(
        self,
        db: Optional[Session] = None,
        user: Any = None,
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> Tuple[str, str, datetime]:
        """Create access and refresh token pair."""
        session, close_needed = self._ensure_session(db)
        try:
            user_id = user.id if hasattr(user, "id") else uuid.UUID(str(user["id"]))
            user_email = user.email if hasattr(user, "email") else user["email"]

            token_res = create_access_token(
                subject=str(user_id),
                claims={"email": user_email, "name": getattr(user, "name", "")},
            )
            access_token = token_res[0] if isinstance(token_res, tuple) else token_res

            raw_refresh_token = generate_refresh_token()
            token_hash = hash_refresh_token(raw_refresh_token)
            expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

            record = RefreshToken(
                user_id=user_id,
                token_hash=token_hash,
                expires_at=expires_at,
                user_agent=user_agent[:512] if user_agent else None,
                ip_address=ip_address[:45] if ip_address else None,
            )
            session.add(record)
            session.commit()

            return access_token, raw_refresh_token, expires_at
        finally:
            if close_needed:
                session.close()

    def refresh_user_tokens(
        self,
        db: Optional[Session] = None,
        refresh_token_str: str = "",
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> Tuple[str, str, datetime]:
        """Rotate a refresh token and return a new token pair."""
        session, close_needed = self._ensure_session(db)
        try:
            token_hash = hash_refresh_token(refresh_token_str)
            stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
            record = session.scalars(stmt).first()

            if not record:
                raise RefreshTokenNotFoundError()

            if record.is_revoked:
                raise RefreshTokenRevokedError()

            now = datetime.now(timezone.utc)
            if record.expires_at <= now:
                raise RefreshTokenExpiredError()

            user = session.get(User, record.user_id)
            if not user or not user.is_active:
                raise InactiveUserError()

            new_raw_token = generate_refresh_token()
            new_hash = hash_refresh_token(new_raw_token)
            new_expires = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

            record.is_revoked = True
            record.revoked_at = now
            record.replaced_by = new_hash

            new_record = RefreshToken(
                user_id=user.id,
                token_hash=new_hash,
                expires_at=new_expires,
                user_agent=user_agent[:512] if user_agent else None,
                ip_address=ip_address[:45] if ip_address else None,
            )
            session.add(new_record)
            session.commit()

            token_res = create_access_token(
                subject=str(user.id),
                claims={"email": user.email, "name": user.name},
            )
            access_token = token_res[0] if isinstance(token_res, tuple) else token_res
            return access_token, new_raw_token, new_expires
        finally:
            if close_needed:
                session.close()

    def revoke_refresh_token(
        self,
        db: Optional[Session] = None,
        refresh_token_str: str = "",
    ) -> None:
        """Revoke a single refresh token."""
        session, close_needed = self._ensure_session(db)
        try:
            token_hash = hash_refresh_token(refresh_token_str)
            stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
            record = session.scalars(stmt).first()

            if record and not record.is_revoked:
                record.is_revoked = True
                record.revoked_at = datetime.now(timezone.utc)
                session.commit()
        finally:
            if close_needed:
                session.close()

    def revoke_all_user_tokens(
        self,
        db: Optional[Session] = None,
        user_id: Union[str, uuid.UUID] = "",
    ) -> int:
        """Revoke all active refresh tokens for a user."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(user_id))
            now = datetime.now(timezone.utc)
            stmt = (
                update(RefreshToken)
                .where(
                    RefreshToken.user_id == parsed_id,
                    RefreshToken.is_revoked.is_(False),
                )
                .values(is_revoked=True, revoked_at=now)
            )
            result = session.execute(stmt)
            session.commit()
            return result.rowcount or 0
        finally:
            if close_needed:
                session.close()
