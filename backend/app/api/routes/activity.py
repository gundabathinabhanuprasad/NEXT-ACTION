"""Activity timeline REST API routes."""

from datetime import datetime
from typing import Optional
import uuid
from fastapi import APIRouter, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.history import TaskHistoryListResponse
from app.services.history_service import list_activity, serialize_task_history

router = APIRouter(prefix="/activity", tags=["Activity"])


@router.get(
    "",
    response_model=TaskHistoryListResponse,
    status_code=status.HTTP_200_OK,
    summary="List chronological activity timeline across tasks",
)
def list_activity_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    action: Optional[str] = Query(None, description="Filter by action type"),
    task_id: Optional[uuid.UUID] = Query(None, description="Filter by task ID"),
    actor_id: Optional[uuid.UUID] = Query(None, description="Filter by acting user ID"),
    start_date: Optional[datetime] = Query(None, description="Filter activities on or after timestamp"),
    end_date: Optional[datetime] = Query(None, description="Filter activities on or before timestamp"),
) -> TaskHistoryListResponse:
    """Retrieve paginated chronological activity logs across tasks with filtering and eager loading."""
    items, total = list_activity(
        db=db,
        page=page,
        page_size=page_size,
        action=action,
        task_id=task_id,
        actor_id=actor_id,
        start_date=start_date,
        end_date=end_date,
    )
    return TaskHistoryListResponse(
        items=[serialize_task_history(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )
