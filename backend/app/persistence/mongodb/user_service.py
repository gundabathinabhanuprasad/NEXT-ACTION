"""MongoDB User and Authentication Service Adapter.

Provides user management, authentication, credential validation, and refresh-token
operations backed by UserRepository, UserSettingsRepository, and RefreshTokenRepository.
"""

from datetime import datetime, timedelta, timezone
import logging
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.core.config import settings
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    get_password_hash,
    hash_refresh_token,
    verify_password,
)
from app.documents.common import utcnow
from app.documents.refresh_token import RefreshTokenDocument
from app.documents.user import UserDocument
from app.repositories.refresh_token_repository import RefreshTokenRepository
from app.repositories.user_repository import UserRepository
from app.repositories.user_settings_repository import UserSettingsRepository
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

logger = logging.getLogger("nextaction.persistence.mongodb.user")


class MongoUserService:
    """User and authentication service implementation for MongoDB."""

    def __init__(
        self,
        user_repo: Optional[UserRepository] = None,
        settings_repo: Optional[UserSettingsRepository] = None,
        token_repo: Optional[RefreshTokenRepository] = None,
    ):
        self.user_repo = user_repo or UserRepository()
        self.settings_repo = settings_repo or UserSettingsRepository()
        self.token_repo = token_repo or RefreshTokenRepository()

    def _to_doc(self, raw_data: Optional[Dict[str, Any]]) -> UserDocument:
        """Hydrate dictionary or document into strongly typed UserDocument."""
        if raw_data is None:
            raise UserNotFoundError("Unknown")
        return UserDocument.model_validate(raw_data)

    def register_user(
        self,
        db: Any = None,
        name: str = "",
        email: str = "",
        password: str = "",
    ) -> UserDocument:
        """Register a new user account with lowercase email normalization."""
        if len(password) < 8 or len(password) > 128:
            raise NextActionDomainError("Password must be between 8 and 128 characters.")

        norm_email = email.strip().lower()
        if self.user_repo.email_exists(norm_email):
            raise UserAlreadyExistsError(norm_email)

        pwd_hash = get_password_hash(password)
        user = UserDocument(
            name=name.strip(),
            email=norm_email,
            password_hash=pwd_hash,
            is_active=True,
        )
        saved = self.user_repo.create(user)
        # Create default user settings
        self.settings_repo.upsert_for_user(user.id, {})
        return self._to_doc(saved)

    def authenticate_user(
        self,
        db: Any = None,
        email: str = "",
        password: str = "",
    ) -> UserDocument:
        """Authenticate user by email and password hash."""
        norm_email = email.strip().lower()
        user_dict = self.user_repo.get_by_email(norm_email)
        if not user_dict:
            raise InvalidCredentialsError()

        user = self._to_doc(user_dict)
        if not verify_password(password, user.password_hash):
            raise InvalidCredentialsError()

        if not user.is_active:
            raise InactiveUserError(f"User account for '{norm_email}' is inactive.")

        return user

    def get_user_by_id(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        allow_inactive: bool = False,
    ) -> UserDocument:
        """Retrieve user by UUID string or raise UserNotFoundError."""
        user_dict = self.user_repo.get_by_id(user_id)
        if not user_dict:
            raise UserNotFoundError(user_id)
        user = self._to_doc(user_dict)
        if not allow_inactive and not user.is_active:
            raise InactiveUserError(f"User account '{user.id}' is inactive.")
        return user

    def get_user_by_email(
        self,
        db: Any = None,
        email: str = "",
    ) -> Optional[UserDocument]:
        """Retrieve user by lowercase email or return None."""
        norm_email = email.strip().lower()
        user_dict = self.user_repo.get_by_email(norm_email)
        if not user_dict:
            return None
        return self._to_doc(user_dict)

    def list_users(
        self,
        db: Any = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 50,
    ) -> Tuple[List[UserDocument], int]:
        """List users with optional search, active filter, and pagination."""
        query: Dict[str, Any] = {}
        if is_active is not None:
            query["is_active"] = is_active
        if search and search.strip():
            term = search.strip()
            query["$or"] = [
                {"name": {"$regex": term, "$options": "i"}},
                {"email": {"$regex": term, "$options": "i"}},
            ]

        raw_items, total = self.user_repo.paginate(
            query=query,
            page=page,
            page_size=page_size,
            sort=[("name", 1), ("created_at", 1)],
        )
        return [self._to_doc(i) for i in raw_items], total

    def change_password(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        old_password: str = "",
        new_password: str = "",
    ) -> None:
        """Change user password after verifying old password."""
        user = self.get_user_by_id(user_id=user_id)
        if not verify_password(old_password, user.password_hash):
            raise InvalidCredentialsError("Current password does not match.")

        if old_password == new_password:
            raise NextActionDomainError("New password must be different from current password.")

        if len(new_password) < 8 or len(new_password) > 128:
            raise NextActionDomainError("Password must be between 8 and 128 characters.")

        new_hash = get_password_hash(new_password)
        self.user_repo.update(user.id, {"password_hash": new_hash})

    def create_tokens(
        self,
        db: Any = None,
        user: Any = None,
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> Tuple[str, str, datetime]:
        """Create access token and refresh token pair."""
        uid_str = str(user.id if hasattr(user, "id") else user["id"])
        email_str = user.email if hasattr(user, "email") else user["email"]
        name_str = getattr(user, "name", "")

        token_res = create_access_token(
            subject=uid_str,
            claims={"email": email_str, "name": name_str},
        )
        access_token = token_res[0] if isinstance(token_res, tuple) else token_res
        raw_refresh_token, token_doc = self.create_refresh_token_for_user(
            user_id=uid_str,
            client_ip=ip_address,
            user_agent=user_agent,
        )
        return access_token, raw_refresh_token, token_doc.expires_at

    def create_refresh_token_for_user(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        client_ip: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> Tuple[str, RefreshTokenDocument]:
        """Generate high-entropy refresh token and store SHA-256 hash."""
        raw_token = generate_refresh_token()
        token_hash = hash_refresh_token(raw_token)
        expires_at = utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

        doc = RefreshTokenDocument(
            user_id=str(user_id),
            token_hash=token_hash,
            expires_at=expires_at,
            ip_address=client_ip,
            user_agent=user_agent[:512] if user_agent else None,
        )
        saved = self.token_repo.create(doc)
        return raw_token, RefreshTokenDocument.model_validate(saved)

    def refresh_user_tokens(
        self,
        db: Any = None,
        refresh_token_str: str = "",
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> Tuple[str, str, datetime]:
        """Rotate a refresh token and return access_token, new_refresh_token, expires_at."""
        new_raw_token, new_doc, user = self.rotate_refresh_token(
            token_str=refresh_token_str,
            client_ip=ip_address,
            user_agent=user_agent,
        )
        token_res = create_access_token(
            subject=str(user.id),
            claims={"email": user.email, "name": user.name},
        )
        access_token = token_res[0] if isinstance(token_res, tuple) else token_res
        return access_token, new_raw_token, new_doc.expires_at

    def rotate_refresh_token(
        self,
        db: Any = None,
        token_str: str = "",
        client_ip: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> Tuple[str, RefreshTokenDocument, UserDocument]:
        """Rotate an active refresh token with one-time use revocation and replay protection."""
        token_hash = hash_refresh_token(token_str)
        token_dict = self.token_repo.get_by_token_hash(token_hash)
        if not token_dict:
            raise RefreshTokenNotFoundError()

        old_token = RefreshTokenDocument.model_validate(token_dict)
        if old_token.is_revoked:
            # Replay detected: invalidate all sessions for user
            self.revoke_all_user_tokens(user_id=old_token.user_id)
            raise RefreshTokenRevokedError(
                "Refresh token has already been revoked. Replay detected; all sessions invalidated."
            )

        if old_token.expires_at <= utcnow():
            self.token_repo.revoke_token(token_hash)
            raise RefreshTokenExpiredError()

        user = self.get_user_by_id(user_id=old_token.user_id)
        if not user.is_active:
            raise InactiveUserError(f"User {user.id} is inactive.")

        # Create replacement token
        new_raw_token, new_token_doc = self.create_refresh_token_for_user(
            user_id=user.id,
            client_ip=client_ip,
            user_agent=user_agent,
        )

        # Revoke old token linking replacement ID
        self.token_repo.revoke_token(token_hash, replaced_by_id=new_token_doc.id)
        return new_raw_token, new_token_doc, user

    def revoke_refresh_token(
        self,
        db: Any = None,
        refresh_token_str: str = "",
    ) -> None:
        """Explicitly revoke a single refresh token."""
        token_hash = hash_refresh_token(refresh_token_str)
        self.token_repo.revoke_token(token_hash)

    def revoke_all_user_tokens(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
    ) -> int:
        """Revoke all active sessions for a user."""
        return self.token_repo.revoke_all_for_user(user_id)
