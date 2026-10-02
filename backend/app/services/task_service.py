"""Task service implementing core NextAction task business rules.

Dispatches to the active persistence engine (PostgreSQL default or MongoDB)
via the centralized PersistenceGateway.
"""

from datetime import datetime
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy.orm import Session

from app.models.enums import TaskPriority, TaskStatus
from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import (
    InactiveUserError,
    InvalidStatusTransitionError,
    InvalidTaskDateError,
    MaxAttemptsReachedError,
    OverrideReasonRequiredError,
    PostponementReasonRequiredError,
    ReopenReasonRequiredError,
    TaskAlreadyCompletedError,
    TaskCancelledError,
    TaskCompletedError,
    TaskNotCompletedError,
    TaskNotFoundError,
    UserNotFoundError,
)


def validate_task_dates(
    due_date: Optional[datetime] = None,
    next_action_date: Optional[datetime] = None,
) -> None:
    """Validate task date parameters ensuring datetime types and reasonable invariants."""
    if due_date is not None and not isinstance(due_date, datetime):
        raise InvalidTaskDateError("due_date must be a valid datetime instance.")
    if next_action_date is not None and not isinstance(next_action_date, datetime):
        raise InvalidTaskDateError("next_action_date must be a valid datetime instance.")


def get_task(db: Optional[Session] = None, task_id: Union[str, uuid.UUID] = "") -> Any:
    """Retrieve a task by ID or raise TaskNotFoundError."""
    return get_persistence_gateway().task_service.get_task(db=db, task_id=task_id)


def create_task(
    db: Optional[Session] = None,
    title: str = "",
    description: Optional[str] = None,
    subject_line: Optional[str] = None,
    client_id: Optional[Union[str, uuid.UUID]] = None,
    workflow_id: Optional[Union[str, uuid.UUID]] = None,
    assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
    template_id: Optional[Union[str, uuid.UUID]] = None,
    recurring_task_id: Optional[Union[str, uuid.UUID]] = None,
    status: TaskStatus = TaskStatus.PENDING,
    priority: TaskPriority = TaskPriority.MEDIUM,
    due_date: Optional[datetime] = None,
    next_action_date: Optional[datetime] = None,
    max_attempts: int = 2,
    created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Create a new Task and log initial creation history atomically."""
    return get_persistence_gateway().task_service.create_task(
        db=db,
        title=title,
        description=description,
        subject_line=subject_line,
        client_id=client_id,
        workflow_id=workflow_id,
        assigned_user_id=assigned_user_id,
        template_id=template_id,
        recurring_task_id=recurring_task_id,
        status=status,
        priority=priority,
        due_date=due_date,
        next_action_date=next_action_date,
        max_attempts=max_attempts,
        created_by_user_id=created_by_user_id,
    )


def record_attempt(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    user_id: Optional[Union[str, uuid.UUID]] = None,
    notes: Optional[str] = None,
    authorized_override: bool = False,
    override_reason: Optional[str] = None,
) -> Any:
    """Record a work attempt on a task."""
    return get_persistence_gateway().task_service.record_attempt(
        db=db,
        task_id=task_id,
        user_id=user_id,
        notes=notes,
        authorized_override=authorized_override,
        override_reason=override_reason,
    )


def postpone_task(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    new_due_date: Optional[datetime] = None,
    reason: str = "",
    user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Postpone a task's due date."""
    return get_persistence_gateway().task_service.postpone_task(
        db=db,
        task_id=task_id,
        new_due_date=new_due_date,
        reason=reason,
        user_id=user_id,
    )


def update_next_action_date(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    next_action_date: Optional[datetime] = None,
    user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Update the next action date for a task."""
    return get_persistence_gateway().task_service.update_next_action_date(
        db=db,
        task_id=task_id,
        next_action_date=next_action_date,
        user_id=user_id,
    )


def complete_task(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Complete a task, set completed_at timestamp, and log history."""
    return get_persistence_gateway().task_service.complete_task(
        db=db,
        task_id=task_id,
        user_id=user_id,
    )


def reopen_task(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    reason: str = "",
    user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Reopen a completed task, clearing completed_at and restoring status to pending."""
    return get_persistence_gateway().task_service.reopen_task(
        db=db,
        task_id=task_id,
        reason=reason,
        user_id=user_id,
    )


def change_status(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    new_status: TaskStatus = TaskStatus.PENDING,
    user_id: Optional[Union[str, uuid.UUID]] = None,
    reason: Optional[str] = None,
) -> Any:
    """Perform a controlled status transition and log history."""
    return get_persistence_gateway().task_service.change_status(
        db=db,
        task_id=task_id,
        new_status=new_status,
        user_id=user_id,
        reason=reason,
    )


def change_priority(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    new_priority: TaskPriority = TaskPriority.MEDIUM,
    user_id: Optional[Union[str, uuid.UUID]] = None,
    reason: Optional[str] = None,
) -> Any:
    """Change the priority of a task and log history."""
    return get_persistence_gateway().task_service.change_priority(
        db=db,
        task_id=task_id,
        new_priority=new_priority,
        user_id=user_id,
        reason=reason,
    )


def assign_task(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
    assigned_by_user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Assign or reassign a task to a user and log history."""
    return get_persistence_gateway().task_service.assign_task(
        db=db,
        task_id=task_id,
        assigned_user_id=assigned_user_id,
        assigned_by_user_id=assigned_by_user_id,
    )


def update_subject_line(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    subject_line: Optional[str] = None,
    user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Update task subject line and log history."""
    return get_persistence_gateway().task_service.update_subject_line(
        db=db,
        task_id=task_id,
        subject_line=subject_line,
        user_id=user_id,
    )


def update_task(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    title: Optional[str] = None,
    description: Optional[str] = None,
    subject_line: Optional[str] = None,
    user_id: Optional[Union[str, uuid.UUID]] = None,
) -> Any:
    """Update general fields on a task."""
    return get_persistence_gateway().task_service.update_task(
        db=db,
        task_id=task_id,
        title=title,
        description=description,
        subject_line=subject_line,
        user_id=user_id,
    )


def delete_task(db: Optional[Session] = None, task_id: Union[str, uuid.UUID] = "") -> bool:
    """Delete a task by ID."""
    return get_persistence_gateway().task_service.delete_task(db=db, task_id=task_id)


def get_task_history(
    db: Optional[Session] = None,
    task_id: Union[str, uuid.UUID] = "",
    action: Optional[str] = None,
    actor_id: Optional[Union[str, uuid.UUID]] = None,
    order: str = "asc",
    page: Optional[int] = None,
    page_size: Optional[int] = None,
) -> list:
    """Retrieve chronological audit history for a task."""
    return get_persistence_gateway().task_service.get_task_history(
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
) -> list:
    """Retrieve recent task history logs across all tasks."""
    return get_persistence_gateway().task_service.get_recent_activity(
        db=db,
        limit=limit,
        action=action,
        task_id=task_id,
        actor_id=actor_id,
    )


def list_tasks(
    db: Optional[Session] = None,
    search: Optional[str] = None,
    status: Optional[TaskStatus] = None,
    priority: Optional[TaskPriority] = None,
    assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
    unassigned: Optional[bool] = None,
    client_id: Optional[Union[str, uuid.UUID]] = None,
    workflow_id: Optional[Union[str, uuid.UUID]] = None,
    due_from: Optional[datetime] = None,
    due_to: Optional[datetime] = None,
    next_action_from: Optional[datetime] = None,
    next_action_to: Optional[datetime] = None,
    overdue: Optional[bool] = None,
    due_today: Optional[bool] = None,
    upcoming: Optional[bool] = None,
    has_next_action: Optional[bool] = None,
    no_next_action: Optional[bool] = None,
    near_max_attempts: Optional[bool] = None,
    due_date_before: Optional[datetime] = None,
    next_action_before: Optional[datetime] = None,
    sort_by: str = "created_at",
    sort_order: str = "desc",
    page: int = 1,
    page_size: int = 20,
) -> Tuple[List[Any], int]:
    """Retrieve filtered, searched, and paginated list of tasks alongside total count."""
    return get_persistence_gateway().task_service.list_tasks(
        db=db,
        search=search,
        status=status,
        priority=priority,
        assigned_user_id=assigned_user_id,
        unassigned=unassigned,
        client_id=client_id,
        workflow_id=workflow_id,
        due_from=due_from,
        due_to=due_to,
        next_action_from=next_action_from,
        next_action_to=next_action_to,
        overdue=overdue,
        due_today=due_today,
        upcoming=upcoming,
        has_next_action=has_next_action,
        no_next_action=no_next_action,
        near_max_attempts=near_max_attempts,
        due_date_before=due_date_before,
        next_action_before=next_action_before,
        sort_by=sort_by,
        sort_order=sort_order,
        page=page,
        page_size=page_size,
    )
