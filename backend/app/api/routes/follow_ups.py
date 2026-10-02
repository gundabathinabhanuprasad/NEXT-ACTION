"""Follow-ups REST API router with JWT authentication."""

import uuid
from typing import List, Optional
from fastapi import APIRouter, Response, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.follow_up import (
    FollowUpCompleteRequest,
    FollowUpCreate,
    FollowUpResponse,
)
from app.services.follow_up_service import (
    complete_follow_up,
    create_follow_up,
    delete_follow_up,
    get_follow_up,
    list_follow_ups,
)

router = APIRouter(prefix="/follow-ups", tags=["FollowUps"])


@router.get(
    "",
    response_model=List[FollowUpResponse],
    status_code=status.HTTP_200_OK,
    summary="List follow-ups",
)
def list_follow_ups_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: uuid.UUID | None = None,
    is_completed: bool | None = None,
) -> List[FollowUpResponse]:
    """Retrieve follow-ups with optional filtering."""
    follow_ups = list_follow_ups(db=db, task_id=task_id, is_completed=is_completed)
    return [FollowUpResponse.model_validate(f) for f in follow_ups]


@router.post(
    "",
    response_model=FollowUpResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new follow-up",
)
def create_follow_up_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    payload: FollowUpCreate,
) -> FollowUpResponse:
    """Create a new follow-up for a task."""
    follow_up = create_follow_up(
        db=db,
        task_id=payload.task_id,
        scheduled_at=payload.scheduled_at,
        notes=payload.notes,
    )
    return FollowUpResponse.model_validate(follow_up)


@router.get(
    "/{follow_up_id}",
    response_model=FollowUpResponse,
    status_code=status.HTTP_200_OK,
    summary="Get follow-up by ID",
)
def get_follow_up_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    follow_up_id: uuid.UUID,
) -> FollowUpResponse:
    """Retrieve follow-up details by ID."""
    follow_up = get_follow_up(db=db, follow_up_id=follow_up_id)
    return FollowUpResponse.model_validate(follow_up)


@router.post(
    "/{follow_up_id}/complete",
    response_model=FollowUpResponse,
    status_code=status.HTTP_200_OK,
    summary="Complete a follow-up",
)
def complete_follow_up_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    follow_up_id: uuid.UUID,
    payload: FollowUpCompleteRequest = FollowUpCompleteRequest(),
) -> FollowUpResponse:
    """Mark a follow-up as completed."""
    follow_up = complete_follow_up(
        db=db,
        follow_up_id=follow_up_id,
        completed_at=payload.completed_at,
        notes=payload.notes,
    )
    return FollowUpResponse.model_validate(follow_up)


@router.delete(
    "/{follow_up_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a follow-up",
)
def delete_follow_up_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    follow_up_id: uuid.UUID,
) -> Response:
    """Delete a follow-up by ID."""
    delete_follow_up(db=db, follow_up_id=follow_up_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

