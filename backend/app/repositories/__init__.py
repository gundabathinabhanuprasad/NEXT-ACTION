"""Repositories package for data access abstraction."""

from app.repositories.mongodb_base import BaseMongoRepository
from app.repositories.user_repository import UserRepository
from app.repositories.user_settings_repository import UserSettingsRepository
from app.repositories.client_repository import ClientRepository
from app.repositories.workflow_repository import WorkflowRepository
from app.repositories.task_repository import TaskRepository
from app.repositories.task_history_repository import TaskHistoryRepository
from app.repositories.notification_repository import NotificationRepository
from app.repositories.refresh_token_repository import RefreshTokenRepository
from app.repositories.task_template_repository import TaskTemplateRepository
from app.repositories.recurring_task_repository import RecurringTaskRepository
from app.repositories.recurring_task_execution_repository import RecurringTaskExecutionRepository
from app.repositories.event_repository import EventRepository

__all__ = [
    "BaseMongoRepository",
    "UserRepository",
    "UserSettingsRepository",
    "ClientRepository",
    "WorkflowRepository",
    "TaskRepository",
    "TaskHistoryRepository",
    "NotificationRepository",
    "RefreshTokenRepository",
    "TaskTemplateRepository",
    "RecurringTaskRepository",
    "RecurringTaskExecutionRepository",
    "EventRepository",
]
