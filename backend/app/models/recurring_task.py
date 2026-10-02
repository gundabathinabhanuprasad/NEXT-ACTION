"""RecurringTask and RecurringTaskExecution SQLAlchemy ORM models."""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING, List, Optional
from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db import Base
from app.models.enums import RecurrenceType, TaskPriority

if TYPE_CHECKING:
    from app.models.client import Client
    from app.models.task import Task
    from app.models.task_template import TaskTemplate
    from app.models.user import User
    from app.models.workflow import Workflow


class RecurringTask(Base):
    """Recurring task schedule definition for automated periodic task creation."""

    __tablename__ = "recurring_tasks"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    template_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("task_templates.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
        index=True,
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

    priority: Mapped[TaskPriority] = mapped_column(
        Enum(TaskPriority, name="task_priority", native_enum=True),
        default=TaskPriority.MEDIUM,
        nullable=False,
        index=True,
    )
    max_attempts: Mapped[int] = mapped_column(
        Integer,
        default=2,
        nullable=False,
    )

    due_offset_days: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )
    next_action_offset_days: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )

    recurrence_type: Mapped[RecurrenceType] = mapped_column(
        Enum(RecurrenceType, name="recurrence_type", native_enum=True),
        default=RecurrenceType.DAILY,
        nullable=False,
        index=True,
    )
    interval: Mapped[int] = mapped_column(
        Integer,
        default=1,
        nullable=False,
    )
    day_of_week: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )
    day_of_month: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )

    start_date: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    end_date: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    next_run_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True,
    )
    last_run_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        index=True,
    )

    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=False,
        index=True,
    )

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

    # Relationships
    template: Mapped[Optional["TaskTemplate"]] = relationship(
        "TaskTemplate",
        back_populates="recurring_tasks",
    )
    workflow: Mapped[Optional["Workflow"]] = relationship("Workflow")
    client: Mapped[Optional["Client"]] = relationship("Client")
    assigned_user: Mapped[Optional["User"]] = relationship(
        "User",
        foreign_keys=[assigned_user_id],
    )
    created_by_user: Mapped["User"] = relationship(
        "User",
        foreign_keys=[created_by_user_id],
    )
    tasks: Mapped[List["Task"]] = relationship(
        "Task",
        back_populates="recurring_task",
    )
    executions: Mapped[List["RecurringTaskExecution"]] = relationship(
        "RecurringTaskExecution",
        back_populates="recurring_task",
        cascade="all, delete-orphan",
    )


class RecurringTaskExecution(Base):
    """Audit and idempotency log tracking each executed occurrence of a recurring task."""

    __tablename__ = "recurring_task_executions"
    __table_args__ = (
        UniqueConstraint(
            "recurring_task_id",
            "scheduled_for",
            name="uq_recurring_execution_schedule",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    recurring_task_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("recurring_tasks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    scheduled_for: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True,
    )
    task_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("tasks.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    status: Mapped[str] = mapped_column(
        String(50),
        default="success",
        nullable=False,
    )
    executed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    recurring_task: Mapped["RecurringTask"] = relationship(
        "RecurringTask",
        back_populates="executions",
    )
    task: Mapped[Optional["Task"]] = relationship("Task")
