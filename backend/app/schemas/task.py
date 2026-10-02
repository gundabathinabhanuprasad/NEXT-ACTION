"""Task request and response schemas."""

from datetime import datetime
from typing import List, Optional
import uuid
from pydantic import BaseModel, ConfigDict, Field
from app.models.enums import TaskPriority, TaskStatus


class TaskBase(BaseModel):
    """Base fields for Task schemas."""

    title: str = Field(min_length=1, max_length=255)
    description: Optional[str] = None
    subject_line: Optional[str] = Field(default=None, max_length=500)
    client_id: Optional[uuid.UUID] = None
    workflow_id: Optional[uuid.UUID] = None
    assigned_user_id: Optional[uuid.UUID] = None
    template_id: Optional[uuid.UUID] = None
    recurring_task_id: Optional[uuid.UUID] = None
    status: TaskStatus = TaskStatus.PENDING
    priority: TaskPriority = TaskPriority.MEDIUM
    due_date: Optional[datetime] = None
    next_action_date: Optional[datetime] = None
    max_attempts: int = Field(default=2, ge=1)


class TaskCreate(TaskBase):
    """Schema for creating a new Task."""

    created_by_user_id: Optional[uuid.UUID] = None


class TaskUpdate(BaseModel):
    """Schema for updating basic Task fields."""

    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    description: Optional[str] = None
    subject_line: Optional[str] = Field(default=None, max_length=500)
    user_id: Optional[uuid.UUID] = None


class TaskResponse(TaskBase):
    """Response schema for a single Task."""

    id: uuid.UUID
    attempt_count: int
    completed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class TaskListResponse(BaseModel):
    """Paginated list of tasks."""

    items: List[TaskResponse]
    total: int
    page: int
    page_size: int


# =========================================================================
# Operation Request Schemas
# =========================================================================
class AttemptRequest(BaseModel):
    """Schema for recording a normal work attempt."""

    user_id: Optional[uuid.UUID] = None
    notes: Optional[str] = None


class OverrideAttemptRequest(BaseModel):
    """Schema for recording an authorized override attempt."""

    authorized_override: bool = Field(
        default=True,
        description="Explicit confirmation of authorized override",
    )
    reason: str = Field(
        min_length=1,
        description="Mandatory justification for authorized attempt override",
    )
    user_id: Optional[uuid.UUID] = None


class PostponeTaskRequest(BaseModel):
    """Schema for postponing a task's due date."""

    new_due_date: datetime
    reason: str = Field(min_length=1, description="Mandatory justification for postponement")
    user_id: Optional[uuid.UUID] = None


class NextActionDateRequest(BaseModel):
    """Schema for updating next action date."""

    next_action_date: Optional[datetime] = None
    user_id: Optional[uuid.UUID] = None


class CompleteTaskRequest(BaseModel):
    """Schema for completing a task."""

    user_id: Optional[uuid.UUID] = None


class ReopenTaskRequest(BaseModel):
    """Schema for reopening a completed task."""

    reason: str = Field(min_length=1, description="Mandatory justification for reopening task")
    user_id: Optional[uuid.UUID] = None


class StatusChangeRequest(BaseModel):
    """Schema for changing task status."""

    status: TaskStatus
    reason: Optional[str] = None
    user_id: Optional[uuid.UUID] = None


class PriorityChangeRequest(BaseModel):
    """Schema for changing task priority."""

    priority: TaskPriority
    reason: Optional[str] = None
    user_id: Optional[uuid.UUID] = None


class AssignmentChangeRequest(BaseModel):
    """Schema for assigning or reassigning a task."""

    assigned_user_id: Optional[uuid.UUID] = None
    assigned_by_user_id: Optional[uuid.UUID] = None


class SubjectLineChangeRequest(BaseModel):
    """Schema for changing subject line."""

    subject_line: Optional[str] = Field(default=None, max_length=500)
    user_id: Optional[uuid.UUID] = None
