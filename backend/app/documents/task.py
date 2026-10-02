"""MongoDB document schema for Task entity with embedded Reminders and FollowUps."""

from datetime import datetime
from typing import List, Optional
from pydantic import Field
from app.documents.common import BaseDocument, BaseSubDocument, utcnow
from app.models.enums import TaskPriority, TaskStatus


class ReminderSubDocument(BaseSubDocument):
    """Embedded reminder alert within a Task document."""

    task_id: Optional[str] = Field(default=None, description="Parent Task UUID string")
    remind_at: Optional[datetime] = Field(default_factory=utcnow, description="Alert trigger UTC timestamp")
    message: str = Field(default="Reminder alert", min_length=1)
    is_sent: bool = Field(default=False)


class FollowUpSubDocument(BaseSubDocument):
    """Embedded follow-up action item within a Task document."""

    task_id: Optional[str] = Field(default=None, description="Parent Task UUID string")
    scheduled_at: Optional[datetime] = Field(default_factory=utcnow, description="Target follow-up UTC timestamp")
    completed_at: Optional[datetime] = Field(default=None)
    notes: Optional[str] = Field(default=None)


class TaskDocument(BaseDocument):
    """Core Task entity document.

    Maintains embedded subdocuments for tightly coupled items (reminders and follow-ups)
    and denormalized summary fields for high-performance reading without relational joins.
    """

    title: str = Field(min_length=1, max_length=255)
    description: Optional[str] = Field(default=None)
    subject_line: Optional[str] = Field(default=None, max_length=500)

    workflow_id: Optional[str] = Field(default=None)
    client_id: Optional[str] = Field(default=None)
    assigned_user_id: Optional[str] = Field(default=None)
    template_id: Optional[str] = Field(default=None)
    recurring_task_id: Optional[str] = Field(default=None)

    status: TaskStatus = Field(default=TaskStatus.PENDING)
    priority: TaskPriority = Field(default=TaskPriority.MEDIUM)

    due_date: Optional[datetime] = Field(default=None)
    next_action_date: Optional[datetime] = Field(default=None)

    attempt_count: int = Field(default=0, ge=0)
    max_attempts: int = Field(default=2, ge=1)

    completed_at: Optional[datetime] = Field(default=None)

    # Embedded child subdocuments
    reminders: List[ReminderSubDocument] = Field(default_factory=list)
    follow_ups: List[FollowUpSubDocument] = Field(default_factory=list)

    # Denormalized metadata snapshots for join-free list queries
    client_name: Optional[str] = Field(default=None, max_length=255)
    workflow_name: Optional[str] = Field(default=None, max_length=255)
    assigned_user_name: Optional[str] = Field(default=None, max_length=255)
    assigned_user_email: Optional[str] = Field(default=None, max_length=255)
