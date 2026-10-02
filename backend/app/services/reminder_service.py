"""Reminder service for managing notifications and preserving attempt invariants.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from datetime import datetime, timezone
from typing import Any, List, Optional, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import ReminderNotFoundError, TaskNotFoundError


def get_reminder(db: Optional[Session] = None, reminder_id: Union[str, uuid.UUID] = "") -> Any:
    """Retrieve a reminder by ID or raise ReminderNotFoundError."""
    return get_persistence_gateway().reminder_service.get_reminder(db=db, reminder_id=reminder_id)


def create_reminder(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    remind_at: datetime = datetime.now(timezone.utc),
    message: str = "",
) -> Any:
    """Create a reminder associated with a task."""
    return get_persistence_gateway().reminder_service.create_reminder(
        db=db,
        task_id=task_id,
        remind_at=remind_at,
        message=message,
    )


def process_reminder(db: Optional[Session] = None, reminder_id: Union[str, uuid.UUID] = "") -> Any:
    """Mark a reminder as sent/processed."""
    return get_persistence_gateway().reminder_service.process_reminder(
        db=db, reminder_id=reminder_id
    )


def list_due_reminders(
    db: Optional[Session] = None,
    as_of: Optional[datetime] = None,
) -> List[Any]:
    """Retrieve all unsent reminders due on or before a given timestamp."""
    return get_persistence_gateway().reminder_service.list_due_reminders(db=db, as_of=as_of)


def list_task_reminders(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
) -> List[Any]:
    """Retrieve all reminders associated with a specific task."""
    return get_persistence_gateway().reminder_service.list_task_reminders(
        db=db, task_id=task_id
    )


def list_reminders(
    db: Optional[Session] = None,
    task_id: Optional[Union[str, uuid.UUID]] = None,
    is_sent: Optional[bool] = None,
) -> List[Any]:
    """Retrieve reminders optionally filtered by task and sent status."""
    return get_persistence_gateway().reminder_service.list_reminders(
        db=db,
        task_id=task_id,
        is_sent=is_sent,
    )


def delete_reminder(db: Optional[Session] = None, reminder_id: Union[str, uuid.UUID] = "") -> None:
    """Delete a reminder by ID."""
    get_persistence_gateway().reminder_service.delete_reminder(db=db, reminder_id=reminder_id)
