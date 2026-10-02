"""Notification service managing user alerts, ownership security, deduplication, and scheduled evaluation.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from datetime import datetime
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import NotificationNotFoundError, UserNotFoundError


def should_notify_user(db: Session, user_id: uuid.UUID, notif_type: str) -> bool:
    """Check if user has enabled notifications for this specific type in UserSettings."""
    from app.persistence.postgres.notification_service import should_notify_user as pg_should_notify
    return pg_should_notify(db, user_id, notif_type)


def create_notification(
    db: Optional[Session] = None,
    user_id: Union[str, uuid.UUID] = "",
    type: str = "",
    title: str = "",
    message: str = "",
    task_id: Optional[Union[str, uuid.UUID]] = None,
    dedup_key: Optional[str] = None,
) -> Optional[Any]:
    """Create a persistent notification for a specific user."""
    return get_persistence_gateway().notification_service.create_notification(
        db=db,
        user_id=user_id,
        type=type,
        title=title,
        message=message,
        task_id=task_id,
        dedup_key=dedup_key,
    )


def get_notification(
    db: Optional[Session] = None,
    user_id: Union[str, uuid.UUID] = "",
    notification_id: Union[str, uuid.UUID] = "",
) -> Any:
    """Retrieve a single notification for the specified user."""
    return get_persistence_gateway().notification_service.get_notification(
        db=db,
        user_id=user_id,
        notification_id=notification_id,
    )


def get_user_notifications(
    db: Optional[Session] = None,
    user_id: Union[str, uuid.UUID] = "",
    unread_only: bool = False,
    page: int = 1,
    page_size: int = 20,
) -> Tuple[List[Any], int, int]:
    """Retrieve paginated notifications for the specified user."""
    return get_persistence_gateway().notification_service.get_user_notifications(
        db=db,
        user_id=user_id,
        unread_only=unread_only,
        page=page,
        page_size=page_size,
    )


def get_unread_count(db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> int:
    """Return count of unread notifications for the specified user."""
    return get_persistence_gateway().notification_service.get_unread_count(
        db=db, user_id=user_id
    )


def mark_as_read(
    db: Optional[Session] = None,
    user_id: Union[str, uuid.UUID] = "",
    notification_id: Union[str, uuid.UUID] = "",
) -> Any:
    """Mark a specific notification as read after validating ownership."""
    return get_persistence_gateway().notification_service.mark_as_read(
        db=db,
        user_id=user_id,
        notification_id=notification_id,
    )


def mark_all_as_read(db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> int:
    """Mark all unread notifications for a user as read."""
    return get_persistence_gateway().notification_service.mark_all_as_read(
        db=db, user_id=user_id
    )


def evaluate_due_notifications(
    db: Optional[Session] = None,
    as_of: Optional[datetime] = None,
) -> int:
    """Evaluate due notifications."""
    return get_persistence_gateway().notification_service.evaluate_due_notifications(
        db=db, as_of=as_of
    )
