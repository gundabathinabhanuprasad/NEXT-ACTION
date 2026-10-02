"""FollowUp request and response schemas."""

from datetime import datetime
from typing import Optional, Union
import uuid
from pydantic import BaseModel, ConfigDict, Field


class FollowUpCreate(BaseModel):
    """Schema for creating a new FollowUp."""

    task_id: uuid.UUID
    scheduled_at: datetime
    notes: Optional[str] = None


class FollowUpCompleteRequest(BaseModel):
    """Schema for completing a FollowUp."""

    completed_at: Optional[datetime] = None
    notes: Optional[str] = None


class FollowUpResponse(BaseModel):
    """Schema representing a FollowUp."""

    id: Union[uuid.UUID, str]
    task_id: Optional[Union[uuid.UUID, str]] = None
    scheduled_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    notes: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)
