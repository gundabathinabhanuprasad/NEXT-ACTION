"""Notification Pydantic schemas and DTOs."""

from datetime import datetime
from typing import List, Optional
import uuid
from pydantic import BaseModel, ConfigDict, Field


class NotificationResponse(BaseModel):
    """Pydantic schema for Notification serialization."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    task_id: Optional[uuid.UUID] = None
    type: str
    title: str
    message: str
    dedup_key: Optional[str] = None
    is_read: bool
    read_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class NotificationListResponse(BaseModel):
    """Paginated response containing list of notifications and total/unread counts."""

    items: List[NotificationResponse]
    total: int
    unread_count: int
    page: int
    page_size: int


class UnreadCountResponse(BaseModel):
    """Response containing unread notification count for the authenticated user."""

    unread_count: int = Field(..., ge=0, description="Total number of unread notifications")


class NotificationEvaluateResponse(BaseModel):
    """Response returned when due/overdue notification evaluation is triggered."""

    created_count: int = Field(..., ge=0, description="Number of new notifications generated")
    evaluated_at: datetime = Field(..., description="Timestamp when evaluation was executed")
