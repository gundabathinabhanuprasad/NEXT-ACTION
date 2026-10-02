"""MongoDB User Settings Service implementation."""

from typing import Any, Dict, Optional, Union
import uuid

from app.documents.user_settings import UserSettingsDocument
from app.repositories import UserRepository, UserSettingsRepository
from app.services.exceptions import UserNotFoundError


class MongoSettingsService:
    """User Settings service implementation using MongoDB collections and repositories."""

    def __init__(
        self,
        settings_repo: Optional[UserSettingsRepository] = None,
        user_repo: Optional[UserRepository] = None,
    ):
        self.settings_repo = settings_repo or UserSettingsRepository()
        self.user_repo = user_repo or UserRepository()

    def _ensure_user(self, user_id: Union[str, uuid.UUID]) -> None:
        """Verify user exists or raise UserNotFoundError."""
        user = self.user_repo.get_by_id(user_id)
        if not user:
            raise UserNotFoundError(user_id)

    def get_user_settings(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
    ) -> UserSettingsDocument:
        """Retrieve or initialize default user settings."""
        self._ensure_user(user_id)
        existing = self.settings_repo.get_by_user_id(user_id)
        if existing:
            return UserSettingsDocument.model_validate(existing)

        # Initialize default settings document
        created = self.settings_repo.upsert_for_user(user_id, {})
        return UserSettingsDocument.model_validate(created)

    def update_user_settings(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        updates: Any = None,
        settings_in: Any = None,
    ) -> UserSettingsDocument:
        """Update user preferences."""
        self._ensure_user(user_id)
        input_obj = updates if updates is not None else settings_in
        if hasattr(input_obj, "model_dump"):
            payload = input_obj.model_dump(exclude_unset=True)
        elif isinstance(input_obj, dict):
            payload = dict(input_obj)
        else:
            payload = {}

        updated = self.settings_repo.upsert_for_user(user_id, payload)
        return UserSettingsDocument.model_validate(updated)

    def reset_user_settings(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
    ) -> UserSettingsDocument:
        """Reset user preferences to factory defaults."""
        self._ensure_user(user_id)
        default_doc = UserSettingsDocument(user_id=str(user_id))
        self.settings_repo.delete_by_user_id(user_id)
        saved = self.settings_repo.upsert_for_user(user_id, default_doc.to_domain())
        return UserSettingsDocument.model_validate(saved)
