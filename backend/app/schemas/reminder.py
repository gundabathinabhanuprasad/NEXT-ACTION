"""Reminder request and response schemas."""

from datetime import datetime
import uuid
from pydantic import BaseModel, ConfigDict, Field


class ReminderCreate(BaseModel):
    """Schema for creating a new Reminder."""

    task_id: uuid.UUID
    remind_at: datetime
    message: str = Field(min_length=1)


class ReminderResponse(BaseModel):
    """Schema representing a Reminder."""

    id: uuid.UUID
    task_id: uuid.UUID
    remind_at: datetime
    message: str
    is_sent: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
