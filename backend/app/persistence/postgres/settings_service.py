"""PostgreSQL / SQLAlchemy User Settings Service Adapter."""

from typing import Any, Optional, Tuple, Union
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.user_settings import UserSettings
from app.schemas.settings import UserSettingsUpdate

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


class PostgresSettingsService:
    """PostgreSQL user settings service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def get_user_settings(self, db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> UserSettings:
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(user_id))
            stmt = select(UserSettings).where(UserSettings.user_id == parsed_id)
            settings_rec = session.scalars(stmt).first()

            if not settings_rec:
                settings_rec = UserSettings(user_id=parsed_id, **DEFAULT_SETTINGS)
                session.add(settings_rec)
                session.commit()
                session.refresh(settings_rec)

            return settings_rec
        finally:
            if close_needed:
                session.close()

    def update_user_settings(
        self,
        db: Optional[Session] = None,
        user_id: Union[str, uuid.UUID] = "",
        updates: Optional[UserSettingsUpdate] = None,
    ) -> UserSettings:
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(user_id))
            settings_rec = self.get_user_settings(session, parsed_id)
            if updates is not None:
                update_data = updates.model_dump(exclude_unset=True)
                for field, val in update_data.items():
                    if val is not None and hasattr(settings_rec, field):
                        setattr(settings_rec, field, val)

            session.commit()
            session.refresh(settings_rec)
            return settings_rec
        finally:
            if close_needed:
                session.close()

    def reset_user_settings(self, db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> UserSettings:
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(user_id))
            settings_rec = self.get_user_settings(session, parsed_id)

            for field, val in DEFAULT_SETTINGS.items():
                if hasattr(settings_rec, field):
                    setattr(settings_rec, field, val)

            session.commit()
            session.refresh(settings_rec)
            return settings_rec
        finally:
            if close_needed:
                session.close()
