"""Workflows REST API router with JWT authentication."""

from typing import List, Optional
import uuid
from fastapi import APIRouter, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.workflow import (
    WorkflowCreate,
    WorkflowListResponse,
    WorkflowResponse,
    WorkflowUpdate,
)
from app.services.workflow_service import (
    create_workflow,
    get_workflow,
    list_workflows,
    update_workflow,
)

router = APIRouter(prefix="/workflows", tags=["Workflows"])


@router.post(
    "",
    response_model=WorkflowResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new workflow",
)
def create_workflow_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    payload: WorkflowCreate,
) -> WorkflowResponse:
    """Create a new Workflow process group."""
    workflow = create_workflow(
        db=db,
        name=payload.name,
        description=payload.description,
        is_active=payload.is_active,
    )
    return WorkflowResponse.model_validate(workflow)


@router.get(
    "",
    response_model=WorkflowListResponse,
    status_code=status.HTTP_200_OK,
    summary="List and search workflows",
)
def list_workflows_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    is_active: Optional[bool] = Query(default=None, description="Filter by active status"),
    search: Optional[str] = Query(default=None, description="Search term for name/description"),
    page: int = Query(default=1, ge=1, description="Page number"),
    page_size: int = Query(default=100, ge=1, le=200, description="Items per page"),
) -> WorkflowListResponse:
    """Retrieve filtered and paginated workflows."""
    items, total = list_workflows(
        db=db,
        is_active=is_active,
        search=search,
        page=page,
        page_size=page_size,
    )
    return WorkflowListResponse(
        items=[WorkflowResponse.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/{workflow_id}",
    response_model=WorkflowResponse,
    status_code=status.HTTP_200_OK,
    summary="Get a workflow by ID",
)
def get_workflow_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    workflow_id: uuid.UUID,
) -> WorkflowResponse:
    """Retrieve workflow details by ID."""
    workflow = get_workflow(db=db, workflow_id=workflow_id)
    return WorkflowResponse.model_validate(workflow)


@router.patch(
    "/{workflow_id}",
    response_model=WorkflowResponse,
    status_code=status.HTTP_200_OK,
    summary="Update a workflow",
)
def update_workflow_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    workflow_id: uuid.UUID,
    payload: WorkflowUpdate,
) -> WorkflowResponse:
    """Update existing workflow attributes."""
    workflow = update_workflow(
        db=db,
        workflow_id=workflow_id,
        name=payload.name,
        description=payload.description,
        is_active=payload.is_active,
    )
    return WorkflowResponse.model_validate(workflow)
