"""TaskTemplate Pydantic schemas."""

from datetime import datetime
from typing import List, Optional, Union
import uuid
from pydantic import BaseModel, ConfigDict, Field
from app.models.enums import TaskPriority


class TaskTemplateBase(BaseModel):
    """Base schema for task templates."""

    name: str = Field(min_length=1, max_length=255)
    description: Optional[str] = None
    subject_line: Optional[str] = Field(default=None, max_length=500)
    workflow_id: Optional[Union[uuid.UUID, str]] = None
    client_id: Optional[Union[uuid.UUID, str]] = None
    assigned_user_id: Optional[Union[uuid.UUID, str]] = None
    priority: TaskPriority = TaskPriority.MEDIUM
    max_attempts: int = Field(default=2, ge=1)
    default_due_offset_days: Optional[int] = Field(default=None, ge=0)
    default_next_action_offset_days: Optional[int] = Field(default=None, ge=0)
    is_active: bool = True


class TaskTemplateCreate(TaskTemplateBase):
    """Schema for creating a new TaskTemplate."""

    pass


class TaskTemplateUpdate(BaseModel):
    """Schema for updating an existing TaskTemplate."""

    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    description: Optional[str] = None
    subject_line: Optional[str] = Field(default=None, max_length=500)
    workflow_id: Optional[Union[uuid.UUID, str]] = None
    client_id: Optional[Union[uuid.UUID, str]] = None
    assigned_user_id: Optional[Union[uuid.UUID, str]] = None
    priority: Optional[TaskPriority] = None
    max_attempts: Optional[int] = Field(default=None, ge=1)
    default_due_offset_days: Optional[int] = Field(default=None, ge=0)
    default_next_action_offset_days: Optional[int] = Field(default=None, ge=0)
    is_active: Optional[bool] = None


class TaskTemplateResponse(TaskTemplateBase):
    """Response schema representing a persisted TaskTemplate."""

    id: Union[uuid.UUID, str]
    created_by_user_id: Union[uuid.UUID, str]
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class TaskTemplateListResponse(BaseModel):
    """Paginated response of task templates."""

    items: List[TaskTemplateResponse]
    total: int
    page: int
    page_size: int


class CreateTaskFromTemplateRequest(BaseModel):
    """Optional overrides when generating a concrete Task from a TaskTemplate."""

    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    description: Optional[str] = None
    subject_line: Optional[str] = Field(default=None, max_length=500)
    workflow_id: Optional[uuid.UUID] = None
    client_id: Optional[uuid.UUID] = None
    assigned_user_id: Optional[uuid.UUID] = None
    priority: Optional[TaskPriority] = None
    max_attempts: Optional[int] = Field(default=None, ge=1)
    due_date: Optional[datetime] = None
    next_action_date: Optional[datetime] = None
