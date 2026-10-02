"""MongoDB Notification Service implementation."""

from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.documents.notification import NotificationDocument
from app.repositories import NotificationRepository, UserSettingsRepository
from app.services.exceptions import NotificationNotFoundError


class MongoNotificationService:
    """Notification service implementation using MongoDB collections and repositories."""

    def __init__(
        self,
        notif_repo: Optional[NotificationRepository] = None,
        settings_repo: Optional[UserSettingsRepository] = None,
    ):
        self.notif_repo = notif_repo or NotificationRepository()
        self.settings_repo = settings_repo or UserSettingsRepository()

    def _to_doc(self, raw_data: Optional[Dict[str, Any]]) -> NotificationDocument:
        if raw_data is None:
            raise NotificationNotFoundError("Unknown")
        return NotificationDocument.model_validate(raw_data)

    def should_notify_user(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_type: str = "",
    ) -> bool:
        """Check user notification preferences."""
        settings = self.settings_repo.get_by_user_id(user_id)
        if not settings:
            return True
        return settings.get("enable_in_app_notifications", True)

    def create_notification(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        type: str = "",
        title: str = "",
        message: str = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
        dedup_key: Optional[str] = None,
    ) -> NotificationDocument:
        """Create notification with deduplication support."""
        created, _ = self.notif_repo.create_with_dedup(
            user_id=user_id,
            type_=type,
            title=title,
            message=message,
            dedup_key=dedup_key,
            task_id=task_id,
        )
        return self._to_doc(created)

    def get_notification(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_id: Union[str, uuid.UUID] = "",
    ) -> NotificationDocument:
        """Retrieve notification validating recipient ownership."""
        doc_dict = self.notif_repo.get_by_id(notification_id)
        if not doc_dict:
            raise NotificationNotFoundError(notification_id)

        doc = self._to_doc(doc_dict)
        if doc.user_id != str(user_id):
            raise NotificationNotFoundError(notification_id)
        return doc

    def get_user_notifications(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        unread_only: bool = False,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[NotificationDocument], int, int]:
        """Retrieve paginated notifications returning (items, total_count, unread_count)."""
        items, total = self.notif_repo.list_for_user(
            user_id=user_id,
            unread_only=unread_only,
            page=page,
            page_size=page_size,
        )
        unread_count = self.notif_repo.count_unread(user_id)
        return [self._to_doc(i) for i in items], total, unread_count

    def get_unread_count(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
    ) -> int:
        """Return total unread notifications count for user."""
        return self.notif_repo.count_unread(user_id)

    def mark_as_read(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_id: Union[str, uuid.UUID] = "",
    ) -> NotificationDocument:
        """Mark single notification read after ownership check."""
        self.get_notification(db=db, user_id=user_id, notification_id=notification_id)
        updated = self.notif_repo.mark_as_read(notification_id)
        return self._to_doc(updated)

    def mark_all_as_read(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
    ) -> int:
        """Mark all unread notifications read for user."""
        return self.notif_repo.mark_all_read(user_id)

    def delete_notification(
        self,
        db: Any = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_id: Union[str, uuid.UUID] = "",
    ) -> bool:
        """Delete notification after ownership check."""
        self.get_notification(db=db, user_id=user_id, notification_id=notification_id)
        return self.notif_repo.delete(notification_id)
