"""Persistence layer interface protocols for dual-engine dispatch.

Defines the contract that both PostgreSQL and MongoDB service adapters implement.
"""

from datetime import datetime
from typing import Any, List, Optional, Protocol, Tuple, Union
import uuid

from app.models.enums import TaskPriority, TaskStatus
from app.schemas.history import TaskHistoryResponse
from app.schemas.settings import UserSettingsUpdate


class TaskPersistenceService(Protocol):
    """Protocol for task persistence operations."""

    def get_task(self, db: Optional[Any] = None, task_id: Union[str, uuid.UUID] = "") -> Any: ...

    def create_task(
        self,
        db: Optional[Any] = None,
        title: str = "",
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        template_id: Optional[Union[str, uuid.UUID]] = None,
        recurring_task_id: Optional[Union[str, uuid.UUID]] = None,
        status: TaskStatus = TaskStatus.PENDING,
        priority: TaskPriority = TaskPriority.MEDIUM,
        due_date: Optional[datetime] = None,
        next_action_date: Optional[datetime] = None,
        max_attempts: int = 2,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def record_attempt(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
        notes: Optional[str] = None,
        authorized_override: bool = False,
        override_reason: Optional[str] = None,
    ) -> Any: ...

    def postpone_task(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        new_due_date: datetime = ...,
        reason: str = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def update_next_action_date(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        next_action_date: Optional[datetime] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def complete_task(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def reopen_task(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        reason: str = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def change_status(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        new_status: TaskStatus = TaskStatus.PENDING,
        user_id: Optional[Union[str, uuid.UUID]] = None,
        reason: Optional[str] = None,
    ) -> Any: ...

    def change_priority(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        new_priority: TaskPriority = TaskPriority.MEDIUM,
        user_id: Optional[Union[str, uuid.UUID]] = None,
        reason: Optional[str] = None,
    ) -> Any: ...

    def assign_task(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def update_subject_line(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        subject_line: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def update_task(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        title: Optional[str] = None,
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def delete_task(self, db: Optional[Any] = None, task_id: Union[str, uuid.UUID] = "") -> bool: ...

    def list_tasks(
        self,
        db: Optional[Any] = None,
        search: Optional[str] = None,
        status: Optional[TaskStatus] = None,
        priority: Optional[TaskPriority] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        unassigned: Optional[bool] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        due_from: Optional[datetime] = None,
        due_to: Optional[datetime] = None,
        next_action_from: Optional[datetime] = None,
        next_action_to: Optional[datetime] = None,
        overdue: Optional[bool] = None,
        due_today: Optional[bool] = None,
        upcoming: Optional[bool] = None,
        has_next_action: Optional[bool] = None,
        no_next_action: Optional[bool] = None,
        near_max_attempts: Optional[bool] = None,
        due_date_before: Optional[datetime] = None,
        next_action_before: Optional[datetime] = None,
        sort_by: str = "created_at",
        sort_order: str = "desc",
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Any], int]: ...


class UserPersistenceService(Protocol):
    """Protocol for user and auth persistence operations."""

    def get_user_by_id(
        self,
        db: Optional[Any] = None,
        user_id: Union[str, uuid.UUID] = "",
        allow_inactive: bool = False,
    ) -> Any: ...

    def get_user_by_email(self, db: Optional[Any] = None, email: str = "") -> Optional[Any]: ...

    def register_user(
        self,
        db: Optional[Any] = None,
        name: str = "",
        email: str = "",
        password: str = "",
    ) -> Any: ...

    def authenticate_user(
        self,
        db: Optional[Any] = None,
        email: str = "",
        password: str = "",
    ) -> Any: ...

    def authenticate_or_create_google_user(
        self,
        db: Optional[Any] = None,
        google_id: str = "",
        email: str = "",
        name: str = "",
    ) -> Any: ...

    def list_users(
        self,
        db: Optional[Any] = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 50,
    ) -> Tuple[List[Any], int]: ...

    def create_tokens(
        self,
        db: Optional[Any] = None,
        user: Any = None,
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> Tuple[str, str, datetime]: ...

    def refresh_user_tokens(
        self,
        db: Optional[Any] = None,
        refresh_token_str: str = "",
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None,
    ) -> Tuple[str, str, datetime]: ...

    def revoke_refresh_token(
        self,
        db: Optional[Any] = None,
        refresh_token_str: str = "",
    ) -> None: ...

    def revoke_all_user_tokens(
        self,
        db: Optional[Any] = None,
        user_id: Union[str, uuid.UUID] = "",
    ) -> int: ...


class ClientPersistenceService(Protocol):
    """Protocol for client operations."""

    def get_client(self, db: Optional[Any] = None, client_id: Union[str, uuid.UUID] = "") -> Any: ...

    def create_client(
        self,
        db: Optional[Any] = None,
        name: str = "",
        company: Optional[str] = None,
        email: Optional[str] = None,
        phone: Optional[str] = None,
        notes: Optional[str] = None,
    ) -> Any: ...

    def update_client(
        self,
        db: Optional[Any] = None,
        client_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        company: Optional[str] = None,
        email: Optional[str] = None,
        phone: Optional[str] = None,
        notes: Optional[str] = None,
    ) -> Any: ...

    def delete_client(self, db: Optional[Any] = None, client_id: Union[str, uuid.UUID] = "") -> bool: ...

    def list_clients(
        self,
        db: Optional[Any] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 100,
    ) -> Tuple[List[Any], int]: ...


class WorkflowPersistenceService(Protocol):
    """Protocol for workflow operations."""

    def get_workflow(self, db: Optional[Any] = None, workflow_id: Union[str, uuid.UUID] = "") -> Any: ...

    def create_workflow(
        self,
        db: Optional[Any] = None,
        name: str = "",
        description: Optional[str] = None,
        is_active: bool = True,
    ) -> Any: ...

    def update_workflow(
        self,
        db: Optional[Any] = None,
        workflow_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        description: Optional[str] = None,
        is_active: Optional[bool] = None,
    ) -> Any: ...

    def delete_workflow(self, db: Optional[Any] = None, workflow_id: Union[str, uuid.UUID] = "") -> bool: ...

    def list_workflows(
        self,
        db: Optional[Any] = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 100,
    ) -> Tuple[List[Any], int]: ...


class SettingsPersistenceService(Protocol):
    """Protocol for user settings operations."""

    def get_user_settings(self, db: Optional[Any] = None, user_id: Union[str, uuid.UUID] = "") -> Any: ...

    def update_user_settings(
        self,
        db: Optional[Any] = None,
        user_id: Union[str, uuid.UUID] = "",
        updates: Optional[UserSettingsUpdate] = None,
    ) -> Any: ...

    def reset_user_settings(self, db: Optional[Any] = None, user_id: Union[str, uuid.UUID] = "") -> Any: ...


class NotificationPersistenceService(Protocol):
    """Protocol for notification operations."""

    def create_notification(
        self,
        db: Optional[Any] = None,
        user_id: Union[str, uuid.UUID] = "",
        type: str = "",
        title: str = "",
        message: str = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
        dedup_key: Optional[str] = None,
    ) -> Optional[Any]: ...

    def get_notification(
        self,
        db: Optional[Any] = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_id: Union[str, uuid.UUID] = "",
    ) -> Any: ...

    def get_user_notifications(
        self,
        db: Optional[Any] = None,
        user_id: Union[str, uuid.UUID] = "",
        unread_only: bool = False,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Any], int, int]: ...

    def get_unread_count(self, db: Optional[Any] = None, user_id: Union[str, uuid.UUID] = "") -> int: ...

    def mark_as_read(
        self,
        db: Optional[Any] = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_id: Union[str, uuid.UUID] = "",
    ) -> Any: ...

    def mark_all_as_read(self, db: Optional[Any] = None, user_id: Union[str, uuid.UUID] = "") -> int: ...


class ReminderPersistenceService(Protocol):
    """Protocol for reminder operations."""

    def get_reminder(self, db: Optional[Any] = None, reminder_id: Union[str, uuid.UUID] = "") -> Any: ...

    def create_reminder(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        remind_at: datetime = ...,
        message: str = "",
    ) -> Any: ...

    def process_reminder(self, db: Optional[Any] = None, reminder_id: Union[str, uuid.UUID] = "") -> Any: ...

    def list_due_reminders(self, db: Optional[Any] = None, as_of: Optional[datetime] = None) -> List[Any]: ...

    def list_task_reminders(self, db: Optional[Any] = None, task_id: Union[str, uuid.UUID] = "") -> List[Any]: ...

    def list_reminders(
        self,
        db: Optional[Any] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        is_sent: Optional[bool] = None,
    ) -> List[Any]: ...

    def delete_reminder(self, db: Optional[Any] = None, reminder_id: Union[str, uuid.UUID] = "") -> None: ...


class FollowUpPersistenceService(Protocol):
    """Protocol for follow-up operations."""

    def get_follow_up(self, db: Optional[Any] = None, follow_up_id: Union[str, uuid.UUID] = "") -> Any: ...

    def create_follow_up(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        scheduled_at: datetime = ...,
        notes: Optional[str] = None,
    ) -> Any: ...

    def complete_follow_up(
        self,
        db: Optional[Any] = None,
        follow_up_id: Union[str, uuid.UUID] = "",
        completed_at: Optional[datetime] = None,
        notes: Optional[str] = None,
    ) -> Any: ...

    def list_task_follow_ups(self, db: Optional[Any] = None, task_id: Union[str, uuid.UUID] = "") -> List[Any]: ...

    def list_due_follow_ups(self, db: Optional[Any] = None, as_of: Optional[datetime] = None) -> List[Any]: ...

    def list_follow_ups(
        self,
        db: Optional[Any] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        is_completed: Optional[bool] = None,
    ) -> List[Any]: ...

    def delete_follow_up(self, db: Optional[Any] = None, follow_up_id: Union[str, uuid.UUID] = "") -> None: ...


class HistoryPersistenceService(Protocol):
    """Protocol for history audit operations."""

    def log_history(
        self,
        db: Optional[Any] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        action: str = "",
        old_value: Optional[str] = None,
        new_value: Optional[str] = None,
        reason: Optional[str] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Any: ...

    def get_task_history(
        self,
        db: Optional[Any] = None,
        task_id: Union[str, uuid.UUID] = "",
        action: Optional[str] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
        order: str = "asc",
        page: Optional[int] = None,
        page_size: Optional[int] = None,
    ) -> List[Any]: ...

    def get_recent_activity(
        self,
        db: Optional[Any] = None,
        limit: int = 20,
        action: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> List[Any]: ...

    def list_activity(
        self,
        db: Optional[Any] = None,
        page: int = 1,
        page_size: int = 20,
        action: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> Tuple[List[Any], int]: ...

    def serialize_task_history(self, history: Any) -> TaskHistoryResponse: ...
