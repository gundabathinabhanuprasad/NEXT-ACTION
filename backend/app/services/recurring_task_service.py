"""RecurringTask service implementing recurrence definitions, duplicate-safe evaluation, and lifecycle rules."""

import calendar
from datetime import datetime, timedelta, timezone
from typing import Any, List, Optional, Tuple, Union
import uuid
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session
from app.models.client import Client
from app.models.enums import RecurrenceType, TaskPriority
from app.models.recurring_task import RecurringTask, RecurringTaskExecution
from app.models.task import Task
from app.models.task_template import TaskTemplate
from app.models.user import User
from app.models.workflow import Workflow
from app.persistence.gateway import get_persistence_gateway
from app.persistence.mongodb.recurring_task_service import MongoRecurringTaskService
from app.services.exceptions import (
    ClientNotFoundError,
    InactiveUserError,
    InvalidRecurrenceRuleError,
    RecurringTaskNotFoundError,
    TaskTemplateNotFoundError,
    UnauthorizedRecurringTaskAccessError,
    UserNotFoundError,
    WorkflowNotFoundError,
)
from app.services.history_service import log_history
from app.services.task_service import create_task


def compute_next_run(
    current_run: datetime,
    recurrence_type: RecurrenceType,
    interval: int,
    day_of_week: Optional[int] = None,
    day_of_month: Optional[int] = None,
) -> datetime:
    """Compute the next scheduled run datetime given recurrence parameters and calendar boundaries."""
    if interval < 1:
        interval = 1

    if recurrence_type == RecurrenceType.DAILY or recurrence_type == RecurrenceType.CUSTOM_INTERVAL:
        return current_run + timedelta(days=interval)

    elif recurrence_type == RecurrenceType.WEEKLY:
        next_date = current_run + timedelta(weeks=interval)
        if day_of_week is not None and 0 <= day_of_week <= 6:
            current_weekday = next_date.weekday()
            diff = day_of_week - current_weekday
            next_date = next_date + timedelta(days=diff)
        return next_date

    elif recurrence_type == RecurrenceType.MONTHLY:
        target_month_raw = current_run.month + interval
        target_year = current_run.year + (target_month_raw - 1) // 12
        target_month = ((target_month_raw - 1) % 12) + 1

        target_day = day_of_month if day_of_month is not None else current_run.day
        max_days = calendar.monthrange(target_year, target_month)[1]
        effective_day = min(target_day, max_days)

        return current_run.replace(
            year=target_year,
            month=target_month,
            day=effective_day,
        )

    return current_run + timedelta(days=interval)


def get_recurring_task(db: Optional[Session] = None, recurring_task_id: Union[str, uuid.UUID] = "") -> Any:
    """Retrieve a recurring task definition by ID or raise RecurringTaskNotFoundError."""
    if get_persistence_gateway().is_mongodb:
        return MongoRecurringTaskService().get_recurring_task(db=db, recurring_task_id=recurring_task_id)
    rec = db.get(RecurringTask, recurring_task_id) if db else None
    if not rec:
        raise RecurringTaskNotFoundError(recurring_task_id)
    return rec


def list_recurring_tasks(
    db: Optional[Session] = None,
    search: Optional[str] = None,
    is_active: Optional[bool] = None,
    created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    page: int = 1,
    page_size: int = 20,
) -> Tuple[List[Any], int]:
    """List recurring task definitions with optional search, active filtering, and pagination."""
    if get_persistence_gateway().is_mongodb:
        return MongoRecurringTaskService().list_recurring_tasks(
            db=db,
            search=search,
            is_active=is_active,
            created_by_user_id=created_by_user_id,
            page=page,
            page_size=page_size,
        )
    query = select(RecurringTask)

    if is_active is not None:
        query = query.where(RecurringTask.is_active == is_active)

    if created_by_user_id is not None:
        query = query.where(RecurringTask.created_by_user_id == created_by_user_id)

    if search:
        search_term = search.strip()
        if search_term:
            escaped_term = search_term.replace("%", "\\%").replace("_", "\\_")
            pattern = f"%{escaped_term}%"
            query = query.where(
                or_(
                    RecurringTask.name.ilike(pattern),
                    RecurringTask.description.ilike(pattern),
                    RecurringTask.subject_line.ilike(pattern),
                )
            )

    count_query = select(func.count()).select_from(query.subquery())
    total = db.execute(count_query).scalar_one()

    offset = (page - 1) * page_size
    query = query.order_by(RecurringTask.created_at.desc(), RecurringTask.id.asc()).offset(offset).limit(page_size)

    items = list(db.execute(query).scalars().all())
    return items, total


def create_recurring_task(
    db: Optional[Session] = None,
    name: str = "",
    start_date: datetime = datetime.now(timezone.utc),
    created_by_user_id: Union[str, uuid.UUID] = "",
    template_id: Optional[Union[str, uuid.UUID]] = None,
    description: Optional[str] = None,
    subject_line: Optional[str] = None,
    workflow_id: Optional[Union[str, uuid.UUID]] = None,
    client_id: Optional[Union[str, uuid.UUID]] = None,
    assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
    priority: TaskPriority = TaskPriority.MEDIUM,
    max_attempts: int = 2,
    due_offset_days: Optional[int] = None,
    next_action_offset_days: Optional[int] = None,
    recurrence_type: RecurrenceType = RecurrenceType.DAILY,
    interval: int = 1,
    day_of_week: Optional[int] = None,
    day_of_month: Optional[int] = None,
    end_date: Optional[datetime] = None,
    is_active: bool = True,
) -> Any:
    """Create a new RecurringTask definition."""
    if get_persistence_gateway().is_mongodb:
        return MongoRecurringTaskService().create_recurring_task(
            db=db,
            name=name,
            start_date=start_date,
            created_by_user_id=created_by_user_id,
            template_id=template_id,
            description=description,
            subject_line=subject_line,
            workflow_id=workflow_id,
            client_id=client_id,
            assigned_user_id=assigned_user_id,
            priority=priority,
            max_attempts=max_attempts,
            due_offset_days=due_offset_days,
            next_action_offset_days=next_action_offset_days,
            recurrence_type=recurrence_type,
            interval=interval,
            day_of_week=day_of_week,
            day_of_month=day_of_month,
            end_date=end_date,
            is_active=is_active,
        )
    if interval < 1:
        raise InvalidRecurrenceRuleError("Recurrence interval must be at least 1.")

    if end_date is not None and end_date < start_date:
        raise InvalidRecurrenceRuleError("end_date cannot be earlier than start_date.")

    if template_id is not None:
        template = db.get(TaskTemplate, template_id)
        if not template:
            raise TaskTemplateNotFoundError(template_id)

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

    next_run_at = start_date

    rec = RecurringTask(
        name=name,
        template_id=template_id,
        description=description,
        subject_line=subject_line,
        workflow_id=workflow_id,
        client_id=client_id,
        assigned_user_id=assigned_user_id,
        priority=priority,
        max_attempts=max_attempts,
        due_offset_days=due_offset_days,
        next_action_offset_days=next_action_offset_days,
        recurrence_type=recurrence_type,
        interval=interval,
        day_of_week=day_of_week,
        day_of_month=day_of_month,
        start_date=start_date,
        end_date=end_date,
        next_run_at=next_run_at,
        is_active=is_active,
        created_by_user_id=created_by_user_id,
    )
    db.add(rec)
    db.commit()
    db.refresh(rec)
    return rec


def update_recurring_task(
    db: Optional[Session] = None,
    recurring_task_id: Union[str, uuid.UUID] = "",
    current_user_id: Union[str, uuid.UUID] = "",
    name: Optional[str] = None,
    template_id: Optional[Union[str, uuid.UUID]] = None,
    description: Optional[str] = None,
    subject_line: Optional[str] = None,
    workflow_id: Optional[Union[str, uuid.UUID]] = None,
    client_id: Optional[Union[str, uuid.UUID]] = None,
    assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
    priority: Optional[TaskPriority] = None,
    max_attempts: Optional[int] = None,
    due_offset_days: Optional[int] = None,
    next_action_offset_days: Optional[int] = None,
    recurrence_type: Optional[RecurrenceType] = None,
    interval: Optional[int] = None,
    day_of_week: Optional[int] = None,
    day_of_month: Optional[int] = None,
    start_date: Optional[datetime] = None,
    next_run_at: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    is_active: Optional[bool] = None,
) -> Any:
    """Update an existing RecurringTask definition with authorization check."""
    if get_persistence_gateway().is_mongodb:
        return MongoRecurringTaskService().update_recurring_task(
            db=db,
            recurring_task_id=recurring_task_id,
            current_user_id=current_user_id,
            name=name,
            template_id=template_id,
            description=description,
            subject_line=subject_line,
            workflow_id=workflow_id,
            client_id=client_id,
            assigned_user_id=assigned_user_id,
            priority=priority,
            max_attempts=max_attempts,
            due_offset_days=due_offset_days,
            next_action_offset_days=next_action_offset_days,
            recurrence_type=recurrence_type,
            interval=interval,
            day_of_week=day_of_week,
            day_of_month=day_of_month,
            start_date=start_date,
            next_run_at=next_run_at,
            end_date=end_date,
            is_active=is_active,
        )
    rec = get_recurring_task(db, recurring_task_id)

    if rec.created_by_user_id != current_user_id:
        raise UnauthorizedRecurringTaskAccessError(recurring_task_id)

    if template_id is not None:
        template = db.get(TaskTemplate, template_id)
        if not template:
            raise TaskTemplateNotFoundError(template_id)
        rec.template_id = template_id

    if client_id is not None:
        client = db.get(Client, client_id)
        if not client:
            raise ClientNotFoundError(client_id)
        rec.client_id = client_id

    if workflow_id is not None:
        workflow = db.get(Workflow, workflow_id)
        if not workflow:
            raise WorkflowNotFoundError(workflow_id)
        rec.workflow_id = workflow_id

    if assigned_user_id is not None:
        user = db.get(User, assigned_user_id)
        if not user:
            raise UserNotFoundError(assigned_user_id)
        if not user.is_active:
            raise InactiveUserError()
        rec.assigned_user_id = assigned_user_id

    if interval is not None:
        if interval < 1:
            raise InvalidRecurrenceRuleError("Recurrence interval must be at least 1.")
        rec.interval = interval

    if name is not None:
        rec.name = name
    if description is not None:
        rec.description = description
    if subject_line is not None:
        rec.subject_line = subject_line
    if priority is not None:
        rec.priority = priority
    if max_attempts is not None:
        rec.max_attempts = max_attempts
    if due_offset_days is not None:
        rec.due_offset_days = due_offset_days
    if next_action_offset_days is not None:
        rec.next_action_offset_days = next_action_offset_days
    if recurrence_type is not None:
        rec.recurrence_type = recurrence_type
    if day_of_week is not None:
        rec.day_of_week = day_of_week
    if day_of_month is not None:
        rec.day_of_month = day_of_month
    if start_date is not None:
        rec.start_date = start_date
    if next_run_at is not None:
        rec.next_run_at = next_run_at
    if end_date is not None:
        rec.end_date = end_date
    if is_active is not None:
        rec.is_active = is_active

    db.commit()
    db.refresh(rec)
    return rec


def delete_recurring_task(
    db: Optional[Session] = None,
    recurring_task_id: Union[str, uuid.UUID] = "",
    current_user_id: Union[str, uuid.UUID] = "",
) -> None:
    """Delete a RecurringTask definition with authorization check."""
    if get_persistence_gateway().is_mongodb:
        return MongoRecurringTaskService().delete_recurring_task(
            db=db,
            recurring_task_id=recurring_task_id,
            current_user_id=current_user_id,
        )
    rec = get_recurring_task(db, recurring_task_id)

    if rec.created_by_user_id != current_user_id:
        raise UnauthorizedRecurringTaskAccessError(recurring_task_id)

    db.delete(rec)
    db.commit()


def evaluate_recurring_tasks(
    db: Optional[Session] = None,
    max_evaluations: int = 50,
) -> Tuple[int, int, List[Any]]:
    """Evaluate all due recurring tasks in bounded batches and generate tasks idempotently."""
    if get_persistence_gateway().is_mongodb:
        return MongoRecurringTaskService().evaluate_recurring_tasks(
            db=db,
            max_evaluations=max_evaluations,
        )
    now = datetime.now(timezone.utc)

    # Find active definitions where next_run_at <= now
    query = (
        select(RecurringTask)
        .where(
            RecurringTask.is_active == True,
            RecurringTask.next_run_at <= now,
            or_(
                RecurringTask.end_date == None,
                RecurringTask.next_run_at <= RecurringTask.end_date,
            ),
        )
        .order_by(RecurringTask.next_run_at.asc(), RecurringTask.id.asc())
        .limit(max_evaluations)
    )

    due_definitions = list(db.execute(query).scalars().all())
    created_tasks: List[Task] = []

    for rec in due_definitions:
        scheduled_for = rec.next_run_at

        # Check for existing execution to prevent duplicate instances
        existing_exec = db.execute(
            select(RecurringTaskExecution).where(
                RecurringTaskExecution.recurring_task_id == rec.id,
                RecurringTaskExecution.scheduled_for == scheduled_for,
            )
        ).scalar_one_or_none()

        task = None
        if not existing_exec:
            # Compute due date & next action date
            due_date = None
            if rec.due_offset_days is not None:
                due_date = scheduled_for + timedelta(days=rec.due_offset_days)

            next_action_date = None
            if rec.next_action_offset_days is not None:
                next_action_date = scheduled_for + timedelta(days=rec.next_action_offset_days)

            task = create_task(
                db=db,
                title=rec.name,
                description=rec.description,
                subject_line=rec.subject_line,
                workflow_id=rec.workflow_id,
                client_id=rec.client_id,
                assigned_user_id=rec.assigned_user_id,
                template_id=rec.template_id,
                recurring_task_id=rec.id,
                priority=rec.priority,
                max_attempts=rec.max_attempts,
                due_date=due_date,
                next_action_date=next_action_date,
                created_by_user_id=rec.created_by_user_id,
            )

            execution = RecurringTaskExecution(
                recurring_task_id=rec.id,
                scheduled_for=scheduled_for,
                task_id=task.id,
                status="success",
            )
            db.add(execution)

            log_history(
                db=db,
                task_id=task.id,
                action="generated_from_recurrence",
                old_value=None,
                new_value=f"RecurringTask: {rec.name} ({rec.id})",
                reason=f"Generated by recurring task '{rec.name}' for schedule {scheduled_for.isoformat()}",
                created_by_user_id=rec.created_by_user_id,
            )

            created_tasks.append(task)

        # Update last run and advance next_run_at
        rec.last_run_at = scheduled_for
        next_next_run = compute_next_run(
            current_run=scheduled_for,
            recurrence_type=rec.recurrence_type,
            interval=rec.interval,
            day_of_week=rec.day_of_week,
            day_of_month=rec.day_of_month,
        )

        if rec.end_date is not None and next_next_run > rec.end_date:
            rec.is_active = False
            rec.next_run_at = next_next_run
        else:
            rec.next_run_at = next_next_run

        db.commit()

    return len(due_definitions), len(created_tasks), created_tasks
