"""RecurringTask API routes."""

from typing import Optional
import uuid
from fastapi import APIRouter, Depends, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.recurring_task import (
    RecurringTaskCreate,
    RecurringTaskEvaluationRequest,
    RecurringTaskEvaluationResponse,
    RecurringTaskListResponse,
    RecurringTaskResponse,
    RecurringTaskUpdate,
)
from app.schemas.task import TaskResponse
from app.services.recurring_task_service import (
    create_recurring_task,
    delete_recurring_task,
    evaluate_recurring_tasks,
    get_recurring_task,
    list_recurring_tasks,
    update_recurring_task,
)

router = APIRouter(prefix="/recurring-tasks", tags=["Recurring Tasks"])


@router.post(
    "",
    response_model=RecurringTaskResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new Recurring Task Definition",
)
def create_recurring_task_route(
    payload: RecurringTaskCreate,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> RecurringTaskResponse:
    """Create a new recurring task schedule definition."""
    rec = create_recurring_task(
        db=db,
        name=payload.name,
        start_date=payload.start_date,
        created_by_user_id=current_user.id,
        template_id=payload.template_id,
        description=payload.description,
        subject_line=payload.subject_line,
        workflow_id=payload.workflow_id,
        client_id=payload.client_id,
        assigned_user_id=payload.assigned_user_id,
        priority=payload.priority,
        max_attempts=payload.max_attempts,
        due_offset_days=payload.due_offset_days,
        next_action_offset_days=payload.next_action_offset_days,
        recurrence_type=payload.recurrence_type,
        interval=payload.interval,
        day_of_week=payload.day_of_week,
        day_of_month=payload.day_of_month,
        end_date=payload.end_date,
        is_active=payload.is_active,
    )
    return RecurringTaskResponse.model_validate(rec)


@router.get(
    "",
    response_model=RecurringTaskListResponse,
    summary="List Recurring Task Definitions",
)
def list_recurring_tasks_route(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    search: Optional[str] = Query(None, description="Search recurring tasks by name, description, subject"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
) -> RecurringTaskListResponse:
    """List recurring task definitions with optional search, active filtering, and pagination."""
    items, total = list_recurring_tasks(
        db=db,
        search=search,
        is_active=is_active,
        page=page,
        page_size=page_size,
    )
    return RecurringTaskListResponse(
        items=[RecurringTaskResponse.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.post(
    "/evaluate",
    response_model=RecurringTaskEvaluationResponse,
    summary="Evaluate and Generate Due Recurring Task Instances",
)
def evaluate_recurring_tasks_route(
    payload: Optional[RecurringTaskEvaluationRequest] = None,
    db: DatabaseDep = None,
    current_user: CurrentUserDep = None,
) -> RecurringTaskEvaluationResponse:
    """Evaluate active recurring task definitions against current time and instantiate tasks idempotently."""
    max_evals = payload.max_evaluations if payload else 50
    evaluated_count, tasks_created, tasks = evaluate_recurring_tasks(
        db=db,
        max_evaluations=max_evals,
    )
    return RecurringTaskEvaluationResponse(
        evaluated_definitions=evaluated_count,
        tasks_created=tasks_created,
        created_tasks=[TaskResponse.model_validate(t) for t in tasks],
    )


@router.get(
    "/{recurring_task_id}",
    response_model=RecurringTaskResponse,
    summary="Get Recurring Task Definition by ID",
)
def get_recurring_task_route(
    recurring_task_id: uuid.UUID,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> RecurringTaskResponse:
    """Retrieve a single recurring task schedule definition."""
    rec = get_recurring_task(db, recurring_task_id)
    return RecurringTaskResponse.model_validate(rec)


@router.patch(
    "/{recurring_task_id}",
    response_model=RecurringTaskResponse,
    summary="Update Recurring Task Definition",
)
def update_recurring_task_route(
    recurring_task_id: uuid.UUID,
    payload: RecurringTaskUpdate,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> RecurringTaskResponse:
    """Update an existing recurring task schedule definition (creator only)."""
    rec = update_recurring_task(
        db=db,
        recurring_task_id=recurring_task_id,
        current_user_id=current_user.id,
        name=payload.name,
        template_id=payload.template_id,
        description=payload.description,
        subject_line=payload.subject_line,
        workflow_id=payload.workflow_id,
        client_id=payload.client_id,
        assigned_user_id=payload.assigned_user_id,
        priority=payload.priority,
        max_attempts=payload.max_attempts,
        due_offset_days=payload.due_offset_days,
        next_action_offset_days=payload.next_action_offset_days,
        recurrence_type=payload.recurrence_type,
        interval=payload.interval,
        day_of_week=payload.day_of_week,
        day_of_month=payload.day_of_month,
        start_date=payload.start_date,
        next_run_at=payload.next_run_at,
        end_date=payload.end_date,
        is_active=payload.is_active,
    )
    return RecurringTaskResponse.model_validate(rec)


@router.delete(
    "/{recurring_task_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete Recurring Task Definition",
)
def delete_recurring_task_route(
    recurring_task_id: uuid.UUID,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> None:
    """Delete an existing recurring task schedule definition (creator only)."""
    delete_recurring_task(
        db=db,
        recurring_task_id=recurring_task_id,
        current_user_id=current_user.id,
    )
