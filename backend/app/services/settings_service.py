"""User Settings and Personalization Service.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from typing import Any, Optional, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.schemas.settings import UserSettingsUpdate

# System default values for complete reset
DEFAULT_SETTINGS = {
    "display_name_override": None,
    "timezone": "UTC",
    "date_format": "YYYY-MM-DD",
    "time_format": "24h",
    "first_day_of_week": "monday",
    "theme": "system",
    "compact_mode": False,
    "default_task_priority": "medium",
    "default_task_status_filter": "all",
    "default_task_sort": "due_date",
    "default_task_sort_order": "asc",
    "default_max_attempts": 3,
    "default_page_size": 20,
    "default_dashboard_time_range": "last_7_days",
    "default_report_date_range": "last_7_days",
    "default_report_type": "task_summary",
    "default_export_format": "csv",
    "notify_task_assigned": True,
    "notify_task_reassigned": True,
    "notify_reminder_due": True,
    "notify_follow_up_due": True,
    "notify_next_action_due": True,
    "notify_task_overdue": True,
    "notify_attempt_limit_reached": True,
    "notify_task_completed": True,
    "notify_task_reopened": True,
}


def get_user_settings(db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> Any:
    """Retrieve the UserSettings record for a user."""
    return get_persistence_gateway().settings_service.get_user_settings(db=db, user_id=user_id)


def update_user_settings(
    db: Optional[Session] = None,
    user_id: Union[str, uuid.UUID] = "",
    updates: Optional[UserSettingsUpdate] = None,
) -> Any:
    """Perform a partial update (PATCH) of user settings."""
    return get_persistence_gateway().settings_service.update_user_settings(
        db=db, user_id=user_id, updates=updates
    )


def reset_user_settings(db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> Any:
    """Reset all configurable user preferences back to system defaults."""
    return get_persistence_gateway().settings_service.reset_user_settings(db=db, user_id=user_id)
