"""RecurringTask Pydantic schemas."""

from datetime import datetime
from typing import List, Optional, Union
import uuid
from pydantic import BaseModel, ConfigDict, Field
from app.models.enums import RecurrenceType, TaskPriority
from app.schemas.task import TaskResponse


class RecurringTaskBase(BaseModel):
    """Base schema for recurring tasks."""

    name: str = Field(min_length=1, max_length=255)
    template_id: Optional[Union[uuid.UUID, str]] = None
    description: Optional[str] = None
    subject_line: Optional[str] = Field(default=None, max_length=500)
    workflow_id: Optional[Union[uuid.UUID, str]] = None
    client_id: Optional[Union[uuid.UUID, str]] = None
    assigned_user_id: Optional[Union[uuid.UUID, str]] = None
    priority: TaskPriority = TaskPriority.MEDIUM
    max_attempts: int = Field(default=2, ge=1)
    due_offset_days: Optional[int] = Field(default=None, ge=0)
    next_action_offset_days: Optional[int] = Field(default=None, ge=0)
    recurrence_type: RecurrenceType = RecurrenceType.DAILY
    interval: int = Field(default=1, ge=1)
    day_of_week: Optional[int] = Field(default=None, ge=0, le=6)
    day_of_month: Optional[int] = Field(default=None, ge=1, le=31)
    start_date: datetime
    end_date: Optional[datetime] = None
    is_active: bool = True


class RecurringTaskCreate(RecurringTaskBase):
    """Schema for creating a new RecurringTask definition."""

    pass


class RecurringTaskUpdate(BaseModel):
    """Schema for updating an existing RecurringTask definition."""

    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    template_id: Optional[Union[uuid.UUID, str]] = None
    description: Optional[str] = None
    subject_line: Optional[str] = Field(default=None, max_length=500)
    workflow_id: Optional[Union[uuid.UUID, str]] = None
    client_id: Optional[Union[uuid.UUID, str]] = None
    assigned_user_id: Optional[Union[uuid.UUID, str]] = None
    priority: Optional[TaskPriority] = None
    max_attempts: Optional[int] = Field(default=None, ge=1)
    due_offset_days: Optional[int] = Field(default=None, ge=0)
    next_action_offset_days: Optional[int] = Field(default=None, ge=0)
    recurrence_type: Optional[RecurrenceType] = None
    interval: Optional[int] = Field(default=None, ge=1)
    day_of_week: Optional[int] = Field(default=None, ge=0, le=6)
    day_of_month: Optional[int] = Field(default=None, ge=1, le=31)
    start_date: Optional[datetime] = None
    next_run_at: Optional[datetime] = None
    end_date: Optional[datetime] = None
    is_active: Optional[bool] = None


class RecurringTaskResponse(RecurringTaskBase):
    """Response schema representing a persisted RecurringTask definition."""

    id: Union[uuid.UUID, str]
    next_run_at: datetime
    last_run_at: Optional[datetime] = None
    created_by_user_id: Union[uuid.UUID, str]
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RecurringTaskListResponse(BaseModel):
    """Paginated response of recurring tasks."""

    items: List[RecurringTaskResponse]
    total: int
    page: int
    page_size: int


class RecurringTaskEvaluationRequest(BaseModel):
    """Request schema for evaluating and generating due recurring task occurrences."""

    max_evaluations: int = Field(default=50, ge=1, le=100)


class RecurringTaskEvaluationResponse(BaseModel):
    """Result summary of recurring task evaluation."""

    evaluated_definitions: int
    tasks_created: int
    created_tasks: List[TaskResponse]
