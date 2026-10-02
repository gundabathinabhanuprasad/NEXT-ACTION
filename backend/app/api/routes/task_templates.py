"""TaskTemplate API routes."""

from typing import Optional
import uuid
from fastapi import APIRouter, Depends, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.task import TaskResponse
from app.schemas.task_template import (
    CreateTaskFromTemplateRequest,
    TaskTemplateCreate,
    TaskTemplateListResponse,
    TaskTemplateResponse,
    TaskTemplateUpdate,
)
from app.services.task_template_service import (
    create_task_from_template,
    create_task_template,
    delete_task_template,
    get_task_template,
    list_task_templates,
    update_task_template,
)

router = APIRouter(prefix="/task-templates", tags=["Task Templates"])


@router.post(
    "",
    response_model=TaskTemplateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new Task Template",
)
def create_template_route(
    payload: TaskTemplateCreate,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> TaskTemplateResponse:
    """Create a new reusable task template blueprint."""
    template = create_task_template(
        db=db,
        name=payload.name,
        created_by_user_id=current_user.id,
        description=payload.description,
        subject_line=payload.subject_line,
        workflow_id=payload.workflow_id,
        client_id=payload.client_id,
        assigned_user_id=payload.assigned_user_id,
        priority=payload.priority,
        max_attempts=payload.max_attempts,
        default_due_offset_days=payload.default_due_offset_days,
        default_next_action_offset_days=payload.default_next_action_offset_days,
        is_active=payload.is_active,
    )
    return TaskTemplateResponse.model_validate(template)


@router.get(
    "",
    response_model=TaskTemplateListResponse,
    summary="List Task Templates",
)
def list_templates_route(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    search: Optional[str] = Query(None, description="Search templates by name, description, subject"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
) -> TaskTemplateListResponse:
    """List task templates with optional search, active filtering, and pagination."""
    items, total = list_task_templates(
        db=db,
        search=search,
        is_active=is_active,
        page=page,
        page_size=page_size,
    )
    return TaskTemplateListResponse(
        items=[TaskTemplateResponse.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/{template_id}",
    response_model=TaskTemplateResponse,
    summary="Get Task Template by ID",
)
def get_template_route(
    template_id: uuid.UUID,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> TaskTemplateResponse:
    """Retrieve a single task template blueprint."""
    template = get_task_template(db, template_id)
    return TaskTemplateResponse.model_validate(template)


@router.patch(
    "/{template_id}",
    response_model=TaskTemplateResponse,
    summary="Update Task Template",
)
def update_template_route(
    template_id: uuid.UUID,
    payload: TaskTemplateUpdate,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> TaskTemplateResponse:
    """Update an existing task template blueprint (creator only)."""
    template = update_task_template(
        db=db,
        template_id=template_id,
        current_user_id=current_user.id,
        name=payload.name,
        description=payload.description,
        subject_line=payload.subject_line,
        workflow_id=payload.workflow_id,
        client_id=payload.client_id,
        assigned_user_id=payload.assigned_user_id,
        priority=payload.priority,
        max_attempts=payload.max_attempts,
        default_due_offset_days=payload.default_due_offset_days,
        default_next_action_offset_days=payload.default_next_action_offset_days,
        is_active=payload.is_active,
    )
    return TaskTemplateResponse.model_validate(template)


@router.delete(
    "/{template_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete Task Template",
)
def delete_template_route(
    template_id: uuid.UUID,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> None:
    """Delete an existing task template blueprint (creator only)."""
    delete_task_template(
        db=db,
        template_id=template_id,
        current_user_id=current_user.id,
    )


@router.post(
    "/{template_id}/create-task",
    response_model=TaskResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create Task from Template",
)
def create_task_from_template_route(
    template_id: uuid.UUID,
    payload: CreateTaskFromTemplateRequest,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> TaskResponse:
    """Instantiate a concrete Task from a Task Template, copying defaults and applying overrides."""
    task = create_task_from_template(
        db=db,
        template_id=template_id,
        created_by_user_id=current_user.id,
        title=payload.title,
        description=payload.description,
        subject_line=payload.subject_line,
        workflow_id=payload.workflow_id,
        client_id=payload.client_id,
        assigned_user_id=payload.assigned_user_id,
        priority=payload.priority,
        max_attempts=payload.max_attempts,
        due_date=payload.due_date,
        next_action_date=payload.next_action_date,
    )
    return TaskResponse.model_validate(task)
