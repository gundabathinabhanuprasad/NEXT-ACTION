"""FollowUp service for scheduling and completing task follow-up actions.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from datetime import datetime, timezone
from typing import Any, List, Optional, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import FollowUpNotFoundError


def get_follow_up(db: Optional[Session] = None, follow_up_id: Union[str, uuid.UUID] = "") -> Any:
    """Retrieve a follow-up by ID or raise FollowUpNotFoundError."""
    return get_persistence_gateway().follow_up_service.get_follow_up(
        db=db, follow_up_id=follow_up_id
    )


def create_follow_up(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    scheduled_at: datetime = datetime.now(timezone.utc),
    notes: Optional[str] = None,
) -> Any:
    """Create a new follow-up for a task."""
    return get_persistence_gateway().follow_up_service.create_follow_up(
        db=db,
        task_id=task_id,
        scheduled_at=scheduled_at,
        notes=notes,
    )


def complete_follow_up(
    db: Optional[Session] = None,
    follow_up_id: Union[str, uuid.UUID] = "",
    completed_at: Optional[datetime] = None,
    notes: Optional[str] = None,
) -> Any:
    """Mark a follow-up action as completed."""
    return get_persistence_gateway().follow_up_service.complete_follow_up(
        db=db,
        follow_up_id=follow_up_id,
        completed_at=completed_at,
        notes=notes,
    )


def list_task_follow_ups(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
) -> List[Any]:
    """Retrieve all follow-ups associated with a specific task."""
    return get_persistence_gateway().follow_up_service.list_task_follow_ups(
        db=db, task_id=task_id
    )


def list_due_follow_ups(
    db: Optional[Session] = None,
    as_of: Optional[datetime] = None,
) -> List[Any]:
    """Retrieve all pending follow-up actions due on or before a given timestamp."""
    return get_persistence_gateway().follow_up_service.list_due_follow_ups(db=db, as_of=as_of)


def list_follow_ups(
    db: Optional[Session] = None,
    task_id: Optional[Union[str, uuid.UUID]] = None,
    is_completed: Optional[bool] = None,
) -> List[Any]:
    """Retrieve follow-ups filtered by task and completion status."""
    return get_persistence_gateway().follow_up_service.list_follow_ups(
        db=db,
        task_id=task_id,
        is_completed=is_completed,
    )


def delete_follow_up(db: Optional[Session] = None, follow_up_id: Union[str, uuid.UUID] = "") -> None:
    """Delete a follow-up by ID."""
    get_persistence_gateway().follow_up_service.delete_follow_up(db=db, follow_up_id=follow_up_id)
