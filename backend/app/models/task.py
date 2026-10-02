"""Task SQLAlchemy ORM model."""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING, List, Optional
from sqlalchemy import DateTime, Enum, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db import Base
from app.models.enums import TaskPriority, TaskStatus

if TYPE_CHECKING:
    from app.models.client import Client
    from app.models.event import Event
    from app.models.follow_up import FollowUp
    from app.models.notification import Notification
    from app.models.recurring_task import RecurringTask
    from app.models.reminder import Reminder
    from app.models.task_history import TaskHistory
    from app.models.task_template import TaskTemplate
    from app.models.user import User
    from app.models.workflow import Workflow


class Task(Base):
    """Central Task entity for work items, follow-up queues, and attempt tracking."""

    __tablename__ = "tasks"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    title: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )
    description: Mapped[Optional[str]] = mapped_column(
        Text,
        nullable=True,
    )
    subject_line: Mapped[Optional[str]] = mapped_column(
        String(500),
        nullable=True,
    )

    workflow_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workflows.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    client_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("clients.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    assigned_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    template_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("task_templates.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    recurring_task_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("recurring_tasks.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    status: Mapped[TaskStatus] = mapped_column(
        Enum(TaskStatus, name="task_status", native_enum=True),
        default=TaskStatus.PENDING,
        nullable=False,
        index=True,
    )
    priority: Mapped[TaskPriority] = mapped_column(
        Enum(TaskPriority, name="task_priority", native_enum=True),
        default=TaskPriority.MEDIUM,
        nullable=False,
        index=True,
    )

    due_date: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        index=True,
    )
    next_action_date: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        index=True,
    )

    attempt_count: Mapped[int] = mapped_column(
        Integer,
        default=0,
        nullable=False,
    )
    max_attempts: Mapped[int] = mapped_column(
        Integer,
        default=2,
        nullable=False,
    )

    completed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relationships
    workflow: Mapped[Optional["Workflow"]] = relationship(
        "Workflow",
        back_populates="tasks",
    )
    client: Mapped[Optional["Client"]] = relationship(
        "Client",
        back_populates="tasks",
    )
    assigned_user: Mapped[Optional["User"]] = relationship(
        "User",
        back_populates="assigned_tasks",
    )
    follow_ups: Mapped[List["FollowUp"]] = relationship(
        "FollowUp",
        back_populates="task",
        cascade="all, delete-orphan",
    )
    reminders: Mapped[List["Reminder"]] = relationship(
        "Reminder",
        back_populates="task",
        cascade="all, delete-orphan",
    )
    events: Mapped[List["Event"]] = relationship(
        "Event",
        back_populates="task",
    )
    histories: Mapped[List["TaskHistory"]] = relationship(
        "TaskHistory",
        back_populates="task",
    )
    notifications: Mapped[List["Notification"]] = relationship(
        "Notification",
        back_populates="task",
    )
    template: Mapped[Optional["TaskTemplate"]] = relationship(
        "TaskTemplate",
        back_populates="tasks",
    )
    recurring_task: Mapped[Optional["RecurringTask"]] = relationship(
        "RecurringTask",
        back_populates="tasks",
    )
