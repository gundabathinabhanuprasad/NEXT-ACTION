"""TaskHistory request and response schemas."""

from datetime import datetime
from typing import Optional
import uuid
from pydantic import BaseModel, ConfigDict


class TaskHistoryResponse(BaseModel):
    """Schema representing a task history log entry with actor and task metadata."""

    id: uuid.UUID
    task_id: Optional[uuid.UUID] = None
    task_title: Optional[str] = None
    action: str
    old_value: Optional[str] = None
    new_value: Optional[str] = None
    reason: Optional[str] = None
    created_by_user_id: Optional[uuid.UUID] = None
    actor_name: Optional[str] = None
    actor_email: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class TaskHistoryListResponse(BaseModel):
    """Paginated response of task history activity logs."""

    items: list[TaskHistoryResponse]
    total: int
    page: int
    page_size: int

