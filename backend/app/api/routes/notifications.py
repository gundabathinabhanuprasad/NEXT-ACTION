"""Notification REST API router implementing strictly authenticated, user-scoped notification operations."""

from datetime import datetime, timezone
from typing import Optional
import uuid
from fastapi import APIRouter, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.notification import (
    NotificationEvaluateResponse,
    NotificationListResponse,
    NotificationResponse,
    UnreadCountResponse,
)
from app.services.notification_service import (
    evaluate_due_notifications,
    get_notification,
    get_unread_count,
    get_user_notifications,
    mark_all_as_read,
    mark_as_read,
)

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.get(
    "",
    response_model=NotificationListResponse,
    status_code=status.HTTP_200_OK,
    summary="List authenticated user's notifications",
)
def list_notifications_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    unread_only: bool = Query(False, description="Filter only unread notifications"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
) -> NotificationListResponse:
    """Retrieve paginated notifications strictly scoped to the authenticated user."""
    items, total, unread_count = get_user_notifications(
        db=db,
        user_id=current_user.id,
        unread_only=unread_only,
        page=page,
        page_size=page_size,
    )
    return NotificationListResponse(
        items=[NotificationResponse.model_validate(n) for n in items],
        total=total,
        unread_count=unread_count,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/unread-count",
    response_model=UnreadCountResponse,
    status_code=status.HTTP_200_OK,
    summary="Get unread notifications count for authenticated user",
)
def get_unread_count_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> UnreadCountResponse:
    """Get the total count of unread notifications for the authenticated user."""
    count = get_unread_count(db=db, user_id=current_user.id)
    return UnreadCountResponse(unread_count=count)


@router.post(
    "/read-all",
    response_model=UnreadCountResponse,
    status_code=status.HTTP_200_OK,
    summary="Mark all notifications as read for authenticated user",
)
def mark_all_read_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> UnreadCountResponse:
    """Mark all unread notifications belonging to the authenticated user as read."""
    mark_all_as_read(db=db, user_id=current_user.id)
    return UnreadCountResponse(unread_count=0)


@router.post(
    "/evaluate",
    response_model=NotificationEvaluateResponse,
    status_code=status.HTTP_200_OK,
    summary="Evaluate and generate due notifications across tasks and reminders",
)
def evaluate_notifications_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> NotificationEvaluateResponse:
    """Trigger background/lifecycle evaluation of due items with duplicate prevention."""
    now = datetime.now(timezone.utc)
    count = evaluate_due_notifications(db=db, as_of=now)
    return NotificationEvaluateResponse(
        created_count=count,
        evaluated_at=now,
    )


@router.get(
    "/{notification_id}",
    response_model=NotificationResponse,
    status_code=status.HTTP_200_OK,
    summary="Get single notification by ID",
)
def get_notification_endpoint(
    notification_id: uuid.UUID,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> NotificationResponse:
    """Retrieve a single notification ensuring ownership by authenticated user."""
    notification = get_notification(
        db=db,
        user_id=current_user.id,
        notification_id=notification_id,
    )
    return NotificationResponse.model_validate(notification)


@router.post(
    "/{notification_id}/read",
    response_model=NotificationResponse,
    status_code=status.HTTP_200_OK,
    summary="Mark single notification as read",
)
def mark_notification_read_endpoint(
    notification_id: uuid.UUID,
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> NotificationResponse:
    """Mark a specific notification as read ensuring ownership by authenticated user."""
    notification = mark_as_read(
        db=db,
        user_id=current_user.id,
        notification_id=notification_id,
    )
    return NotificationResponse.model_validate(notification)
