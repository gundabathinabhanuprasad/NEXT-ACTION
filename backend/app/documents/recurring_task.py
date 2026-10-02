"""MongoDB document schemas for RecurringTask and RecurringTaskExecution entities."""

from datetime import datetime
from typing import Optional
import uuid
from pydantic import BaseModel, ConfigDict, Field
from app.documents.common import BaseDocument, utcnow
from app.models.enums import RecurrenceType, TaskPriority


class RecurringTaskDocument(BaseDocument):
    """Recurring task schedule definition document."""

    template_id: Optional[str] = Field(default=None)
    name: str = Field(min_length=1, max_length=255)
    description: Optional[str] = Field(default=None)
    subject_line: Optional[str] = Field(default=None, max_length=500)

    workflow_id: Optional[str] = Field(default=None)
    client_id: Optional[str] = Field(default=None)
    assigned_user_id: Optional[str] = Field(default=None)

    priority: TaskPriority = Field(default=TaskPriority.MEDIUM)
    max_attempts: int = Field(default=2, ge=1)

    due_offset_days: Optional[int] = Field(default=None, ge=0)
    next_action_offset_days: Optional[int] = Field(default=None, ge=0)

    recurrence_type: RecurrenceType = Field(default=RecurrenceType.DAILY)
    interval: int = Field(default=1, ge=1)
    day_of_week: Optional[int] = Field(default=None, ge=0, le=6)
    day_of_month: Optional[int] = Field(default=None, ge=1, le=31)

    start_date: datetime = Field(description="Recurrence schedule start UTC datetime")
    end_date: Optional[datetime] = Field(default=None)

    next_run_at: datetime = Field(description="Next evaluation UTC datetime")
    last_run_at: Optional[datetime] = Field(default=None)

    is_active: bool = Field(default=True)
    created_by_user_id: str = Field(description="Creator User UUID string")


class RecurringTaskExecutionDocument(BaseModel):
    """Idempotency log tracking each executed occurrence of a recurring task."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()), alias="_id")
    recurring_task_id: str = Field(description="Associated RecurringTask UUID string")
    scheduled_for: datetime = Field(description="Scheduled target UTC timestamp")
    task_id: Optional[str] = Field(default=None, description="Generated Task UUID string")
    status: str = Field(default="success", max_length=50)
    executed_at: datetime = Field(default_factory=utcnow)

    model_config = ConfigDict(
        populate_by_name=True,
        arbitrary_types_allowed=True,
    )

    def to_mongo(self):
        return self.model_dump(by_alias=True)

    def to_domain(self):
        return self.model_dump(by_alias=False)
