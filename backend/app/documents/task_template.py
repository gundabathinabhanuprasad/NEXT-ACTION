"""MongoDB document schema for TaskTemplate entity."""

from typing import Optional
from pydantic import Field
from app.documents.common import BaseDocument
from app.models.enums import TaskPriority


class TaskTemplateDocument(BaseDocument):
    """Reusable task blueprint document."""

    name: str = Field(min_length=1, max_length=255)
    description: Optional[str] = Field(default=None)
    subject_line: Optional[str] = Field(default=None, max_length=500)

    workflow_id: Optional[str] = Field(default=None)
    client_id: Optional[str] = Field(default=None)
    assigned_user_id: Optional[str] = Field(default=None)

    priority: TaskPriority = Field(default=TaskPriority.MEDIUM)
    max_attempts: int = Field(default=2, ge=1)

    default_due_offset_days: Optional[int] = Field(default=None, ge=0)
    default_next_action_offset_days: Optional[int] = Field(default=None, ge=0)

    is_active: bool = Field(default=True)
    created_by_user_id: str = Field(description="Creator User UUID string")
