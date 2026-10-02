"""TaskTemplate service implementing template CRUD and task generation."""

from datetime import datetime, timedelta, timezone
from typing import List, Optional, Tuple
import uuid
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session
from app.models.client import Client
from app.models.enums import TaskPriority
from app.models.task import Task
from app.models.task_template import TaskTemplate
from app.models.user import User
from app.models.workflow import Workflow
from app.services.exceptions import (
    ClientNotFoundError,
    InactiveUserError,
    TaskTemplateNotFoundError,
    UnauthorizedTemplateAccessError,
    UserNotFoundError,
    WorkflowNotFoundError,
)
from app.services.history_service import log_history
from app.services.task_service import create_task


def get_task_template(db: Session, template_id: uuid.UUID) -> TaskTemplate:
    """Retrieve a task template by ID or raise TaskTemplateNotFoundError."""
    template = db.get(TaskTemplate, template_id)
    if not template:
        raise TaskTemplateNotFoundError(template_id)
    return template


def list_task_templates(
    db: Session,
    search: Optional[str] = None,
    is_active: Optional[bool] = None,
    created_by_user_id: Optional[uuid.UUID] = None,
    page: int = 1,
    page_size: int = 20,
) -> Tuple[List[TaskTemplate], int]:
    """List task templates with optional search, active filtering, and pagination."""
    query = select(TaskTemplate)

    if is_active is not None:
        query = query.where(TaskTemplate.is_active == is_active)

    if created_by_user_id is not None:
        query = query.where(TaskTemplate.created_by_user_id == created_by_user_id)

    if search:
        search_term = search.strip()
        if search_term:
            escaped_term = search_term.replace("%", "\\%").replace("_", "\\_")
            pattern = f"%{escaped_term}%"
            query = query.where(
                or_(
                    TaskTemplate.name.ilike(pattern),
                    TaskTemplate.description.ilike(pattern),
                    TaskTemplate.subject_line.ilike(pattern),
                )
            )

    count_query = select(func.count()).select_from(query.subquery())
    total = db.execute(count_query).scalar_one()

    offset = (page - 1) * page_size
    query = query.order_by(TaskTemplate.created_at.desc(), TaskTemplate.id.asc()).offset(offset).limit(page_size)

    items = list(db.execute(query).scalars().all())
    return items, total


def create_task_template(
    db: Session,
    name: str,
    created_by_user_id: uuid.UUID,
    description: Optional[str] = None,
    subject_line: Optional[str] = None,
    workflow_id: Optional[uuid.UUID] = None,
    client_id: Optional[uuid.UUID] = None,
    assigned_user_id: Optional[uuid.UUID] = None,
    priority: TaskPriority = TaskPriority.MEDIUM,
    max_attempts: int = 2,
    default_due_offset_days: Optional[int] = None,
    default_next_action_offset_days: Optional[int] = None,
    is_active: bool = True,
) -> TaskTemplate:
    """Create a new reusable TaskTemplate."""
    if client_id is not None:
        client = db.get(Client, client_id)
        if not client:
            raise ClientNotFoundError(client_id)

    if workflow_id is not None:
        workflow = db.get(Workflow, workflow_id)
        if not workflow:
            raise WorkflowNotFoundError(workflow_id)

    if assigned_user_id is not None:
        user = db.get(User, assigned_user_id)
        if not user:
            raise UserNotFoundError(assigned_user_id)
        if not user.is_active:
            raise InactiveUserError()

    template = TaskTemplate(
        name=name,
        description=description,
        subject_line=subject_line,
        workflow_id=workflow_id,
        client_id=client_id,
        assigned_user_id=assigned_user_id,
        priority=priority,
        max_attempts=max_attempts,
        default_due_offset_days=default_due_offset_days,
        default_next_action_offset_days=default_next_action_offset_days,
        is_active=is_active,
        created_by_user_id=created_by_user_id,
    )
    db.add(template)
    db.commit()
    db.refresh(template)
    return template


def update_task_template(
    db: Session,
    template_id: uuid.UUID,
    current_user_id: uuid.UUID,
    name: Optional[str] = None,
    description: Optional[str] = None,
    subject_line: Optional[str] = None,
    workflow_id: Optional[uuid.UUID] = None,
    client_id: Optional[uuid.UUID] = None,
    assigned_user_id: Optional[uuid.UUID] = None,
    priority: Optional[TaskPriority] = None,
    max_attempts: Optional[int] = None,
    default_due_offset_days: Optional[int] = None,
    default_next_action_offset_days: Optional[int] = None,
    is_active: Optional[bool] = None,
) -> TaskTemplate:
    """Update an existing TaskTemplate with authorization check."""
    template = get_task_template(db, template_id)

    if template.created_by_user_id != current_user_id:
        raise UnauthorizedTemplateAccessError(template_id)

    if client_id is not None:
        client = db.get(Client, client_id)
        if not client:
            raise ClientNotFoundError(client_id)
        template.client_id = client_id

    if workflow_id is not None:
        workflow = db.get(Workflow, workflow_id)
        if not workflow:
            raise WorkflowNotFoundError(workflow_id)
        template.workflow_id = workflow_id

    if assigned_user_id is not None:
        user = db.get(User, assigned_user_id)
        if not user:
            raise UserNotFoundError(assigned_user_id)
        if not user.is_active:
            raise InactiveUserError()
        template.assigned_user_id = assigned_user_id

    if name is not None:
        template.name = name
    if description is not None:
        template.description = description
    if subject_line is not None:
        template.subject_line = subject_line
    if priority is not None:
        template.priority = priority
    if max_attempts is not None:
        template.max_attempts = max_attempts
    if default_due_offset_days is not None:
        template.default_due_offset_days = default_due_offset_days
    if default_next_action_offset_days is not None:
        template.default_next_action_offset_days = default_next_action_offset_days
    if is_active is not None:
        template.is_active = is_active

    db.commit()
    db.refresh(template)
    return template


def delete_task_template(
    db: Session,
    template_id: uuid.UUID,
    current_user_id: uuid.UUID,
) -> None:
    """Delete a TaskTemplate with authorization check."""
    template = get_task_template(db, template_id)

    if template.created_by_user_id != current_user_id:
        raise UnauthorizedTemplateAccessError(template_id)

    db.delete(template)
    db.commit()


def create_task_from_template(
    db: Session,
    template_id: uuid.UUID,
    created_by_user_id: uuid.UUID,
    title: Optional[str] = None,
    description: Optional[str] = None,
    subject_line: Optional[str] = None,
    workflow_id: Optional[uuid.UUID] = None,
    client_id: Optional[uuid.UUID] = None,
    assigned_user_id: Optional[uuid.UUID] = None,
    priority: Optional[TaskPriority] = None,
    max_attempts: Optional[int] = None,
    due_date: Optional[datetime] = None,
    next_action_date: Optional[datetime] = None,
) -> Task:
    """Instantiate a concrete Task from a TaskTemplate applying default offsets and overrides."""
    template = get_task_template(db, template_id)

    now = datetime.now(timezone.utc)

    # Compute due date from offset if not overridden
    effective_due_date = due_date
    if effective_due_date is None and template.default_due_offset_days is not None:
        effective_due_date = now + timedelta(days=template.default_due_offset_days)

    # Compute next action date from offset if not overridden
    effective_next_action_date = next_action_date
    if effective_next_action_date is None and template.default_next_action_offset_days is not None:
        effective_next_action_date = now + timedelta(days=template.default_next_action_offset_days)

    effective_title = title if title is not None else template.name
    effective_description = description if description is not None else template.description
    effective_subject_line = subject_line if subject_line is not None else template.subject_line
    effective_workflow_id = workflow_id if workflow_id is not None else template.workflow_id
    effective_client_id = client_id if client_id is not None else template.client_id
    effective_assigned_user_id = assigned_user_id if assigned_user_id is not None else template.assigned_user_id
    effective_priority = priority if priority is not None else template.priority
    effective_max_attempts = max_attempts if max_attempts is not None else template.max_attempts

    task = create_task(
        db=db,
        title=effective_title,
        description=effective_description,
        subject_line=effective_subject_line,
        workflow_id=effective_workflow_id,
        client_id=effective_client_id,
        assigned_user_id=effective_assigned_user_id,
        template_id=template.id,
        priority=effective_priority,
        max_attempts=effective_max_attempts,
        due_date=effective_due_date,
        next_action_date=effective_next_action_date,
        created_by_user_id=created_by_user_id,
    )

    log_history(
        db=db,
        task_id=task.id,
        action="created_from_template",
        old_value=None,
        new_value=f"Template: {template.name} ({template.id})",
        reason=f"Generated from TaskTemplate '{template.name}'",
        created_by_user_id=created_by_user_id,
    )
    db.commit()

    return task
