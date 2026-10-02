"""UserSettings SQLAlchemy ORM model."""

from datetime import datetime
from typing import TYPE_CHECKING, Optional
import uuid
from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db import Base

if TYPE_CHECKING:
    from app.models.user import User


class UserSettings(Base):
    """User personal preferences and application configuration."""

    __tablename__ = "user_settings"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        index=True,
        nullable=False,
    )

    # Display & Regional
    display_name_override: Mapped[Optional[str]] = mapped_column(
        String(255),
        nullable=True,
    )
    timezone: Mapped[str] = mapped_column(
        String(100),
        default="UTC",
        nullable=False,
    )
    date_format: Mapped[str] = mapped_column(
        String(50),
        default="YYYY-MM-DD",
        nullable=False,
    )
    time_format: Mapped[str] = mapped_column(
        String(20),
        default="24h",
        nullable=False,
    )
    first_day_of_week: Mapped[str] = mapped_column(
        String(20),
        default="monday",
        nullable=False,
    )

    # Appearance
    theme: Mapped[str] = mapped_column(
        String(20),
        default="system",
        nullable=False,
    )
    compact_mode: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
    )

    # Task Defaults
    default_task_priority: Mapped[str] = mapped_column(
        String(20),
        default="medium",
        nullable=False,
    )
    default_task_status_filter: Mapped[str] = mapped_column(
        String(20),
        default="all",
        nullable=False,
    )
    default_task_sort: Mapped[str] = mapped_column(
        String(50),
        default="due_date",
        nullable=False,
    )
    default_task_sort_order: Mapped[str] = mapped_column(
        String(10),
        default="asc",
        nullable=False,
    )
    default_max_attempts: Mapped[int] = mapped_column(
        Integer,
        default=3,
        nullable=False,
    )
    default_page_size: Mapped[int] = mapped_column(
        Integer,
        default=20,
        nullable=False,
    )

    # Dashboard & Reports Personalization
    default_dashboard_time_range: Mapped[str] = mapped_column(
        String(50),
        default="last_7_days",
        nullable=False,
    )
    default_report_date_range: Mapped[str] = mapped_column(
        String(50),
        default="last_7_days",
        nullable=False,
    )
    default_report_type: Mapped[str] = mapped_column(
        String(50),
        default="task_summary",
        nullable=False,
    )
    default_export_format: Mapped[str] = mapped_column(
        String(20),
        default="csv",
        nullable=False,
    )

    # Notification Preferences
    notify_task_assigned: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_task_reassigned: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_reminder_due: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_follow_up_due: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_next_action_due: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_task_overdue: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_attempt_limit_reached: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_task_completed: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )
    notify_task_reopened: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
    )

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relationship back to User
    user: Mapped["User"] = relationship(
        "User",
        back_populates="settings",
    )
