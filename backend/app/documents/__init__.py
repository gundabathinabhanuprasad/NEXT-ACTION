"""MongoDB Pydantic document schemas package."""

from app.documents.client import ClientDocument
from app.documents.common import BaseDocument, BaseSubDocument, utcnow
from app.documents.event import EventDocument
from app.documents.notification import NotificationDocument
from app.documents.recurring_task import (
    RecurringTaskDocument,
    RecurringTaskExecutionDocument,
)
from app.documents.refresh_token import RefreshTokenDocument
from app.documents.task import (
    FollowUpSubDocument,
    ReminderSubDocument,
    TaskDocument,
)
from app.documents.task_history import TaskHistoryDocument
from app.documents.task_template import TaskTemplateDocument
from app.documents.user import UserDocument
from app.documents.user_settings import UserSettingsDocument
from app.documents.workflow import WorkflowDocument
from app.models.enums import RecurrenceType, TaskPriority, TaskStatus

__all__ = [
    "BaseDocument",
    "BaseSubDocument",
    "ClientDocument",
    "EventDocument",
    "FollowUpSubDocument",
    "NotificationDocument",
    "RecurringTaskDocument",
    "RecurringTaskExecutionDocument",
    "RefreshTokenDocument",
    "ReminderSubDocument",
    "TaskDocument",
    "TaskHistoryDocument",
    "TaskTemplateDocument",
    "UserDocument",
    "UserSettingsDocument",
    "WorkflowDocument",
    "RecurrenceType",
    "TaskPriority",
    "TaskStatus",
    "utcnow",
]
