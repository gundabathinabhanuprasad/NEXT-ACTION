"""MongoDB repository for Notification documents."""

from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
from pymongo.database import Database
from app.documents.common import utcnow
from app.documents.notification import NotificationDocument
from app.repositories.mongodb_base import BaseMongoRepository


class NotificationRepository(BaseMongoRepository):
    """Data access repository for notifications collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("notifications", db=db)

    def create(self, notification_data: Union[NotificationDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new notification document."""
        if isinstance(notification_data, NotificationDocument):
            payload = notification_data.to_mongo()
        else:
            payload = dict(notification_data)
        return self.insert_doc(payload)

    def create_with_dedup(
        self,
        user_id: Union[str, uuid.UUID],
        type_: str,
        title: str,
        message: str,
        dedup_key: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Tuple[Dict[str, Any], bool]:
        """
        Create a notification with deduplication support.
        If dedup_key is provided and a notification for the same user with that dedup_key
        already exists, returns (existing_doc, False).
        Otherwise creates a new notification and returns (new_doc, True).
        """
        user_str = str(user_id)
        if dedup_key:
            existing = self.find_one({"user_id": user_str, "dedup_key": dedup_key})
            if existing:
                return existing, False

        doc = NotificationDocument(
            user_id=user_str,
            task_id=str(task_id) if task_id is not None else None,
            type=type_,
            title=title,
            message=message,
            dedup_key=dedup_key,
        )
        created = self.insert_doc(doc.to_mongo())
        return created, True

    def get_by_id(self, notification_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve a notification by its UUID string."""
        return self.find_by_id(notification_id)

    def list_for_user(
        self,
        user_id: Union[str, uuid.UUID],
        unread_only: bool = False,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """List notifications for a user with optional unread filter and pagination."""
        query: Dict[str, Any] = {"user_id": str(user_id)}
        if unread_only:
            query["is_read"] = False
        return self.paginate_find(query, sort_by="created_at", sort_order="desc", page=page, page_size=page_size)

    def count_unread(self, user_id: Union[str, uuid.UUID]) -> int:
        """Count unread notifications for a user."""
        return self.count({"user_id": str(user_id), "is_read": False})

    def mark_as_read(self, notification_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Mark a single notification as read with timestamp."""
        now = utcnow()
        return self.update_by_id(notification_id, {"is_read": True, "read_at": now})

    def mark_all_read(self, user_id: Union[str, uuid.UUID]) -> int:
        """Mark all unread notifications for a user as read."""
        user_str = str(user_id)
        now = utcnow()
        result = self.collection.update_many(
            {"user_id": user_str, "is_read": False},
            {"$set": {"is_read": True, "read_at": now, "updated_at": now}},
        )
        return result.modified_count

    def delete(self, notification_id: Union[str, uuid.UUID]) -> bool:
        """Delete a notification by ID."""
        return self.delete_by_id(notification_id)

    def delete_all_for_user(self, user_id: Union[str, uuid.UUID]) -> int:
        """Delete all notifications for a given user."""
        return self.delete_many({"user_id": str(user_id)})
