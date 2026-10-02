"""Tasks REST API router with JWT authentication and actor identity security."""

from datetime import datetime
from typing import List, Optional
import uuid
from fastapi import APIRouter, HTTPException, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.models.enums import TaskPriority, TaskStatus
from app.schemas.follow_up import FollowUpResponse
from app.schemas.history import TaskHistoryResponse
from app.schemas.reminder import ReminderResponse
from app.schemas.task import (
    AssignmentChangeRequest,
    AttemptRequest,
    CompleteTaskRequest,
    NextActionDateRequest,
    OverrideAttemptRequest,
    PostponeTaskRequest,
    PriorityChangeRequest,
    ReopenTaskRequest,
    StatusChangeRequest,
    SubjectLineChangeRequest,
    TaskCreate,
    TaskListResponse,
    TaskResponse,
    TaskUpdate,
)
from app.services.follow_up_service import list_task_follow_ups
from app.services.reminder_service import list_task_reminders
from app.services.task_service import (
    assign_task,
    change_priority,
    change_status,
    complete_task,
    create_task,
    get_recent_activity,
    get_task,
    get_task_history,
    list_tasks,
    postpone_task,
    record_attempt,
    reopen_task,
    update_next_action_date,
    update_subject_line,
    update_task,
)
from app.services.history_service import serialize_task_history

router = APIRouter(prefix="/tasks", tags=["Tasks"])


@router.post(
    "",
    response_model=TaskResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new task",
)
def create_task_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    payload: TaskCreate,
) -> TaskResponse:
    """Create a new task. Acting creator is securely derived from the authenticated JWT."""
    task = create_task(
        db=db,
        title=payload.title,
        description=payload.description,
        subject_line=payload.subject_line,
        client_id=payload.client_id,
        workflow_id=payload.workflow_id,
        assigned_user_id=payload.assigned_user_id,
        status=payload.status,
        priority=payload.priority,
        due_date=payload.due_date,
        next_action_date=payload.next_action_date,
        max_attempts=payload.max_attempts,
        created_by_user_id=current_user.id,
    )
    return TaskResponse.model_validate(task)


ALLOWED_SORT_FIELDS = {
    "created_at",
    "updated_at",
    "due_date",
    "next_action_date",
    "priority",
    "status",
    "title",
    "attempt_count",
}


@router.get(
    "",
    response_model=TaskListResponse,
    status_code=status.HTTP_200_OK,
    summary="List, search, and filter tasks",
)
def list_tasks_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    search: Optional[str] = Query(default=None, description="Case-insensitive search across title, description, subject, client, workflow, assignee"),
    status: Optional[TaskStatus] = Query(default=None, description="Filter by task status"),
    priority: Optional[TaskPriority] = Query(default=None, description="Filter by task priority"),
    assigned_user_id: Optional[uuid.UUID] = Query(default=None, description="Filter by assigned user"),
    unassigned: Optional[bool] = Query(default=None, description="Filter unassigned tasks"),
    client_id: Optional[uuid.UUID] = Query(default=None, description="Filter by client"),
    workflow_id: Optional[uuid.UUID] = Query(default=None, description="Filter by workflow"),
    due_from: Optional[datetime] = Query(default=None, description="Filter tasks due on or after"),
    due_to: Optional[datetime] = Query(default=None, description="Filter tasks due on or before"),
    next_action_from: Optional[datetime] = Query(default=None, description="Filter next actions on or after"),
    next_action_to: Optional[datetime] = Query(default=None, description="Filter next actions on or before"),
    overdue: Optional[bool] = Query(default=None, description="Filter overdue tasks"),
    due_today: Optional[bool] = Query(default=None, description="Filter tasks due today"),
    upcoming: Optional[bool] = Query(default=None, description="Filter upcoming tasks"),
    has_next_action: Optional[bool] = Query(default=None, description="Filter tasks with next action date"),
    no_next_action: Optional[bool] = Query(default=None, description="Filter tasks without next action date"),
    near_max_attempts: Optional[bool] = Query(default=None, description="Filter tasks near or at max attempts"),
    due_date_before: Optional[datetime] = Query(default=None, description="Backward compatibility: Filter tasks due on or before"),
    next_action_before: Optional[datetime] = Query(default=None, description="Backward compatibility: Filter next actions on or before"),
    sort_by: str = Query(default="created_at", description="Field to sort by"),
    sort_order: str = Query(default="desc", description="Sort order: 'asc' or 'desc'"),
    page: int = Query(default=1, ge=1, description="Page number"),
    page_size: int = Query(default=20, ge=1, le=100, description="Items per page"),
) -> TaskListResponse:
    """Retrieve filtered, searched, sorted, and paginated tasks."""
    # Validation for date ranges
    if due_from is not None and due_to is not None and due_from > due_to:
        raise HTTPException(
            status_code=422,
            detail="due_from cannot be after due_to",
        )
    if next_action_from is not None and next_action_to is not None and next_action_from > next_action_to:
        raise HTTPException(
            status_code=422,
            detail="next_action_from cannot be after next_action_to",
        )

    # Validation for sort fields
    if sort_by not in ALLOWED_SORT_FIELDS:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid sort_by field '{sort_by}'. Allowed fields: {sorted(list(ALLOWED_SORT_FIELDS))}",
        )
    if sort_order.lower() not in {"asc", "desc"}:
        raise HTTPException(
            status_code=422,
            detail="sort_order must be 'asc' or 'desc'",
        )

    items, total = list_tasks(
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
    return TaskListResponse(
        items=[TaskResponse.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/activity/recent",
    response_model=List[TaskHistoryResponse],
    status_code=status.HTTP_200_OK,
    summary="Get recent activity across tasks",
)
def get_recent_activity_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    limit: int = Query(default=20, ge=1, le=100, description="Max activities to return"),
    action: Optional[str] = Query(None, description="Optional action filter"),
    task_id: Optional[uuid.UUID] = Query(None, description="Optional task ID filter"),
    actor_id: Optional[uuid.UUID] = Query(None, description="Optional actor ID filter"),
) -> List[TaskHistoryResponse]:
    """Retrieve recent chronological activity across all tasks."""
    histories = get_recent_activity(
        db=db,
        limit=limit,
        action=action,
        task_id=task_id,
        actor_id=actor_id,
    )
    return [serialize_task_history(h) for h in histories]


@router.get(
    "/{task_id}",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Get a task by ID",
)
def get_task_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
) -> TaskResponse:
    """Retrieve task details by ID."""
    task = get_task(db=db, task_id=task_id)
    return TaskResponse.model_validate(task)


@router.patch(
    "/{task_id}",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Update basic task fields",
)
def update_task_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: TaskUpdate,
) -> TaskResponse:
    """Update general fields on a task."""
    task = update_task(
        db=db,
        task_id=task_id,
        title=payload.title,
        description=payload.description,
        subject_line=payload.subject_line,
        user_id=current_user.id,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/attempt",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Record a work attempt",
)
def record_attempt_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: Optional[AttemptRequest] = None,
) -> TaskResponse:
    """Record a normal work attempt on a task. Actor is authenticated user."""
    notes = payload.notes if payload else None
    task = record_attempt(
        db=db,
        task_id=task_id,
        user_id=current_user.id,
        notes=notes,
        authorized_override=False,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/attempt/override",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Record an authorized attempt override",
)
def record_override_attempt_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: OverrideAttemptRequest,
) -> TaskResponse:
    """Record an authorized additional attempt with mandatory justification."""
    task = record_attempt(
        db=db,
        task_id=task_id,
        user_id=current_user.id,
        authorized_override=payload.authorized_override,
        override_reason=payload.reason,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/postpone",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Postpone task due date",
)
def postpone_task_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: PostponeTaskRequest,
) -> TaskResponse:
    """Postpone task due date with mandatory justification. Actor is authenticated user."""
    task = postpone_task(
        db=db,
        task_id=task_id,
        new_due_date=payload.new_due_date,
        reason=payload.reason,
        user_id=current_user.id,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/next-action",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Update next action date",
)
def update_next_action_date_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: NextActionDateRequest,
) -> TaskResponse:
    """Update next action date for a task."""
    task = update_next_action_date(
        db=db,
        task_id=task_id,
        next_action_date=payload.next_action_date,
        user_id=current_user.id,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/complete",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Complete a task",
)
def complete_task_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: Optional[CompleteTaskRequest] = None,
) -> TaskResponse:
    """Complete a task and set completion timestamp. Actor is authenticated user."""
    task = complete_task(db=db, task_id=task_id, user_id=current_user.id)
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/reopen",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Reopen a completed task",
)
def reopen_task_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: ReopenTaskRequest,
) -> TaskResponse:
    """Reopen a completed task with mandatory justification. Actor is authenticated user."""
    task = reopen_task(
        db=db,
        task_id=task_id,
        reason=payload.reason,
        user_id=current_user.id,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/status",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Change task status",
)
def change_status_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: StatusChangeRequest,
) -> TaskResponse:
    """Perform a controlled status transition."""
    task = change_status(
        db=db,
        task_id=task_id,
        new_status=payload.status,
        user_id=current_user.id,
        reason=payload.reason,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/priority",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Change task priority",
)
def change_priority_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: PriorityChangeRequest,
) -> TaskResponse:
    """Change task priority."""
    task = change_priority(
        db=db,
        task_id=task_id,
        new_priority=payload.priority,
        user_id=current_user.id,
        reason=payload.reason,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/assign",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Assign or reassign task",
)
def assign_task_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: AssignmentChangeRequest,
) -> TaskResponse:
    """Assign or reassign task. Target assignee comes from payload, but acting assigner is always the authenticated user."""
    task = assign_task(
        db=db,
        task_id=task_id,
        assigned_user_id=payload.assigned_user_id,
        assigned_by_user_id=current_user.id,
    )
    return TaskResponse.model_validate(task)


@router.post(
    "/{task_id}/subject-line",
    response_model=TaskResponse,
    status_code=status.HTTP_200_OK,
    summary="Update task subject line",
)
def update_subject_line_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    payload: SubjectLineChangeRequest,
) -> TaskResponse:
    """Update task subject line."""
    task = update_subject_line(
        db=db,
        task_id=task_id,
        subject_line=payload.subject_line,
        user_id=current_user.id,
    )
    return TaskResponse.model_validate(task)


@router.get(
    "/{task_id}/history",
    response_model=List[TaskHistoryResponse],
    status_code=status.HTTP_200_OK,
    summary="Get task history logs",
)
def get_task_history_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
    action: Optional[str] = Query(None, description="Filter by action type"),
    actor_id: Optional[uuid.UUID] = Query(None, description="Filter by acting user ID"),
    order: str = Query("asc", pattern="^(asc|desc)$", description="Sort order (asc or desc)"),
    page: Optional[int] = Query(None, ge=1, description="Optional page number"),
    page_size: Optional[int] = Query(None, ge=1, le=100, description="Optional page size"),
) -> List[TaskHistoryResponse]:
    """Retrieve chronological audit history logs for a task."""
    histories = get_task_history(
        db=db,
        task_id=task_id,
        action=action,
        actor_id=actor_id,
        order=order,
        page=page,
        page_size=page_size,
    )
    return [serialize_task_history(h) for h in histories]


@router.get(
    "/{task_id}/follow-ups",
    response_model=List[FollowUpResponse],
    status_code=status.HTTP_200_OK,
    summary="Get task follow-ups",
)
def get_task_follow_ups_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
) -> List[FollowUpResponse]:
    """Retrieve follow-ups associated with a specific task."""
    follow_ups = list_task_follow_ups(db=db, task_id=task_id)
    return [FollowUpResponse.model_validate(f) for f in follow_ups]


@router.get(
    "/{task_id}/reminders",
    response_model=List[ReminderResponse],
    status_code=status.HTTP_200_OK,
    summary="Get task reminders",
)
def get_task_reminders_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID,
) -> List[ReminderResponse]:
    """Retrieve reminders associated with a specific task."""
    reminders = list_task_reminders(db=db, task_id=task_id)
    return [ReminderResponse.model_validate(r) for r in reminders]
