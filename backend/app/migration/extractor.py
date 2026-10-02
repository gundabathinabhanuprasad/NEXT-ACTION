"""Extraction layer: Reads existing entities from PostgreSQL via SQLAlchemy."""

from typing import Dict, List
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload, selectinload

from app.models.client import Client
from app.models.event import Event
from app.models.notification import Notification
from app.models.recurring_task import RecurringTask, RecurringTaskExecution
from app.models.refresh_token import RefreshToken
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.task_template import TaskTemplate
from app.models.user import User
from app.models.user_settings import UserSettings
from app.models.workflow import Workflow


class PostgreSQLExtractor:
    """Reads all migratable entities from PostgreSQL in deterministic order."""

    def __init__(self, db: Session):
        self.db = db

    def extract_users(self) -> List[User]:
        """Extract all users ordered by creation date."""
        return list(self.db.scalars(select(User).order_by(User.created_at, User.id)).all())

    def extract_user_settings(self) -> List[UserSettings]:
        """Extract all user settings ordered by user_id."""
        return list(
            self.db.scalars(select(UserSettings).order_by(UserSettings.created_at, UserSettings.id)).all()
        )

    def extract_clients(self) -> List[Client]:
        """Extract all clients ordered by creation date."""
        return list(self.db.scalars(select(Client).order_by(Client.created_at, Client.id)).all())

    def extract_workflows(self) -> List[Workflow]:
        """Extract all workflows ordered by creation date."""
        return list(self.db.scalars(select(Workflow).order_by(Workflow.created_at, Workflow.id)).all())

    def extract_task_templates(self) -> List[TaskTemplate]:
        """Extract all task templates ordered by creation date."""
        return list(
            self.db.scalars(select(TaskTemplate).order_by(TaskTemplate.created_at, TaskTemplate.id)).all()
        )

    def extract_recurring_tasks(self) -> List[RecurringTask]:
        """Extract all recurring tasks ordered by creation date."""
        return list(
            self.db.scalars(select(RecurringTask).order_by(RecurringTask.created_at, RecurringTask.id)).all()
        )

    def extract_tasks(self) -> List[Task]:
        """Extract all tasks with eagerly loaded child reminders, follow-ups, and denormalized relations."""
        stmt = (
            select(Task)
            .options(
                selectinload(Task.reminders),
                selectinload(Task.follow_ups),
                joinedload(Task.client),
                joinedload(Task.workflow),
                joinedload(Task.assigned_user),
            )
            .order_by(Task.created_at, Task.id)
        )
        return list(self.db.scalars(stmt).unique().all())

    def extract_task_histories(self) -> List[TaskHistory]:
        """Extract all task history audit records ordered by creation date."""
        return list(
            self.db.scalars(select(TaskHistory).order_by(TaskHistory.created_at, TaskHistory.id)).all()
        )

    def extract_recurring_task_executions(self) -> List[RecurringTaskExecution]:
        """Extract all recurring task executions ordered by execution date."""
        return list(
            self.db.scalars(
                select(RecurringTaskExecution).order_by(
                    RecurringTaskExecution.executed_at, RecurringTaskExecution.id
                )
            ).all()
        )

    def extract_notifications(self) -> List[Notification]:
        """Extract all notifications ordered by creation date."""
        return list(
            self.db.scalars(select(Notification).order_by(Notification.created_at, Notification.id)).all()
        )

    def extract_events(self) -> List[Event]:
        """Extract all calendar events ordered by start date."""
        return list(self.db.scalars(select(Event).order_by(Event.start_at, Event.id)).all())

    def extract_refresh_tokens(self) -> List[RefreshToken]:
        """Extract all refresh tokens ordered by creation date."""
        return list(
            self.db.scalars(select(RefreshToken).order_by(RefreshToken.created_at, RefreshToken.id)).all()
        )

    def get_source_counts(self) -> Dict[str, int]:
        """Return record counts for all 12 entities directly from PostgreSQL."""
        return {
            "users": len(self.extract_users()),
            "user_settings": len(self.extract_user_settings()),
            "clients": len(self.extract_clients()),
            "workflows": len(self.extract_workflows()),
            "task_templates": len(self.extract_task_templates()),
            "recurring_tasks": len(self.extract_recurring_tasks()),
            "tasks": len(self.extract_tasks()),
            "task_history": len(self.extract_task_histories()),
            "recurring_task_executions": len(self.extract_recurring_task_executions()),
            "notifications": len(self.extract_notifications()),
            "events": len(self.extract_events()),
            "refresh_tokens": len(self.extract_refresh_tokens()),
        }
