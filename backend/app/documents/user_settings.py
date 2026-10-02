"""MongoDB document schema for UserSettings entity."""

from typing import Optional
from pydantic import Field
from app.documents.common import BaseDocument


class UserSettingsDocument(BaseDocument):
    """User personal preferences and application configuration document."""

    user_id: str = Field(description="Associated User UUID string")

    # Display & Regional
    display_name_override: Optional[str] = Field(default=None, max_length=255)
    timezone: str = Field(default="UTC", max_length=100)
    date_format: str = Field(default="YYYY-MM-DD", max_length=50)
    time_format: str = Field(default="24h", max_length=20)
    first_day_of_week: str = Field(default="monday", max_length=20)

    # Appearance
    theme: str = Field(default="system", max_length=20)
    compact_mode: bool = Field(default=False)

    # Task Defaults
    default_task_priority: str = Field(default="medium", max_length=20)
    default_task_status_filter: str = Field(default="all", max_length=20)
    default_task_sort: str = Field(default="due_date", max_length=50)
    default_task_sort_order: str = Field(default="asc", max_length=10)
    default_max_attempts: int = Field(default=3, ge=1, le=10)
    default_page_size: int = Field(default=20, ge=1, le=100)

    # Dashboard & Reports Personalization
    default_dashboard_time_range: str = Field(default="last_7_days", max_length=50)
    default_report_date_range: str = Field(default="last_7_days", max_length=50)
    default_report_type: str = Field(default="task_summary", max_length=50)
    default_export_format: str = Field(default="csv", max_length=20)

    # Notification Preferences
    notify_task_assigned: bool = Field(default=True)
    notify_task_reassigned: bool = Field(default=True)
    notify_reminder_due: bool = Field(default=True)
    notify_follow_up_due: bool = Field(default=True)
    notify_next_action_due: bool = Field(default=True)
    notify_task_overdue: bool = Field(default=True)
    notify_attempt_limit_reached: bool = Field(default=True)
    notify_task_completed: bool = Field(default=True)
    notify_task_reopened: bool = Field(default=True)
