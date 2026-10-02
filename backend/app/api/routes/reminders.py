"""Reminders REST API router with JWT authentication."""

from datetime import datetime
from typing import List, Optional
import uuid
from fastapi import APIRouter, Query, Response, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.reminder import ReminderCreate, ReminderResponse
from app.services.reminder_service import (
    create_reminder,
    delete_reminder,
    get_reminder,
    list_due_reminders,
    list_reminders,
    process_reminder,
)

router = APIRouter(prefix="/reminders", tags=["Reminders"])


@router.get(
    "",
    response_model=List[ReminderResponse],
    status_code=status.HTTP_200_OK,
    summary="List reminders",
)
def list_reminders_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    task_id: Optional[uuid.UUID] = Query(default=None, description="Filter by task"),
    is_sent: Optional[bool] = Query(default=None, description="Filter by sent status"),
) -> List[ReminderResponse]:
    """Retrieve reminders with optional task and sent filters."""
    reminders = list_reminders(db=db, task_id=task_id, is_sent=is_sent)
    return [ReminderResponse.model_validate(r) for r in reminders]


@router.post(
    "",
    response_model=ReminderResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new reminder",
)
def create_reminder_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    payload: ReminderCreate,
) -> ReminderResponse:
    """Create a new reminder for a task without incrementing attempt_count."""
    reminder = create_reminder(
        db=db,
        task_id=payload.task_id,
        remind_at=payload.remind_at,
        message=payload.message,
    )
    return ReminderResponse.model_validate(reminder)


@router.get(
    "/due",
    response_model=List[ReminderResponse],
    status_code=status.HTTP_200_OK,
    summary="List due reminders",
)
def list_due_reminders_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    as_of: Optional[datetime] = Query(default=None, description="Due threshold timestamp"),
) -> List[ReminderResponse]:
    """Retrieve all pending reminders due on or before given timestamp."""
    reminders = list_due_reminders(db=db, as_of=as_of)
    return [ReminderResponse.model_validate(r) for r in reminders]


@router.get(
    "/{reminder_id}",
    response_model=ReminderResponse,
    status_code=status.HTTP_200_OK,
    summary="Get reminder by ID",
)
def get_reminder_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    reminder_id: uuid.UUID,
) -> ReminderResponse:
    """Retrieve reminder details by ID."""
    reminder = get_reminder(db=db, reminder_id=reminder_id)
    return ReminderResponse.model_validate(reminder)


@router.post(
    "/{reminder_id}/send",
    response_model=ReminderResponse,
    status_code=status.HTTP_200_OK,
    summary="Mark reminder as sent",
)
def send_reminder_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    reminder_id: uuid.UUID,
) -> ReminderResponse:
    """Process and mark reminder as sent without modifying task attempt_count."""
    reminder = process_reminder(db=db, reminder_id=reminder_id)
    return ReminderResponse.model_validate(reminder)


@router.delete(
    "/{reminder_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a reminder",
)
def delete_reminder_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    reminder_id: uuid.UUID,
) -> Response:
    """Delete a reminder by ID."""
    delete_reminder(db=db, reminder_id=reminder_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

