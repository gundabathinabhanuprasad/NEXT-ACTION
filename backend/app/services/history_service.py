"""Audit history service for recording, querying, and serializing task domain activity.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from datetime import datetime
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.schemas.history import TaskHistoryResponse
from app.services.exceptions import TaskNotFoundError


def log_history(
    db: Optional[Session] = None,
    task_id: Optional[Union[str, uuid.UUID]] = None,
    action: str = "",
    old_value: Optional[str] = None,
    new_value: Optional[str] = None,
    reason: Optional[str] = None,
    created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Create and persist a TaskHistory entry."""
    return get_persistence_gateway().history_service.log_history(
        db=db,
        task_id=task_id,
        action=action,
        old_value=old_value,
        new_value=new_value,
        reason=reason,
        created_by_user_id=created_by_user_id,
    )


def serialize_task_history(history: Any) -> TaskHistoryResponse:
    """Transform a TaskHistory ORM model or MongoDB document into a TaskHistoryResponse DTO."""
    if hasattr(history, "model_dump") or isinstance(history, dict):
        return get_persistence_gateway().history_service.serialize_task_history(history)

    # Standard SQLAlchemy ORM model
    actor_name: Optional[str] = None
    actor_email: Optional[str] = None

    if getattr(history, "created_by_user", None) is not None:
        actor_name = history.created_by_user.name
        actor_email = history.created_by_user.email
    elif getattr(history, "created_by_user_id", None) is not None:
        actor_name = "Former user"
    else:
        actor_name = "System"

    task_title: Optional[str] = history.task.title if getattr(history, "task", None) else None

    return TaskHistoryResponse(
        id=history.id,
        task_id=history.task_id,
        task_title=task_title,
        action=history.action,
        old_value=history.old_value,
        new_value=history.new_value,
        reason=history.reason,
        created_by_user_id=history.created_by_user_id,
        actor_name=actor_name,
        actor_email=actor_email,
        created_at=history.created_at,
    )


def get_task_history(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    action: Optional[str] = None,
    actor_id: Optional[Union[str, uuid.UUID]] = None,
    order: str = "asc",
    page: Optional[int] = None,
    page_size: Optional[int] = None,
) -> List[Any]:
    """Retrieve chronological audit history for a task."""
    return get_persistence_gateway().history_service.get_task_history(
        db=db,
        task_id=task_id,
        action=action,
        actor_id=actor_id,
        order=order,
        page=page,
        page_size=page_size,
    )


def get_recent_activity(
    db: Optional[Session] = None,
    limit: int = 20,
    action: Optional[str] = None,
    task_id: Optional[Union[str, uuid.UUID]] = None,
    actor_id: Optional[Union[str, uuid.UUID]] = None,
) -> List[Any]:
    """Retrieve recent task history logs across all tasks."""
    return get_persistence_gateway().history_service.get_recent_activity(
        db=db,
        limit=limit,
        action=action,
        task_id=task_id,
        actor_id=actor_id,
    )


def list_activity(
    db: Optional[Session] = None,
    page: int = 1,
    page_size: int = 20,
    action: Optional[str] = None,
    task_id: Optional[Union[str, uuid.UUID]] = None,
    actor_id: Optional[Union[str, uuid.UUID]] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
) -> Tuple[List[Any], int]:
    """List activity timeline logs across tasks."""
    return get_persistence_gateway().history_service.list_activity(
        db=db,
        page=page,
        page_size=page_size,
        action=action,
        task_id=task_id,
        actor_id=actor_id,
        start_date=start_date,
        end_date=end_date,
    )
