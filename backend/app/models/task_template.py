"""TaskTemplate SQLAlchemy ORM model."""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING, List, Optional
from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db import Base
from app.models.enums import TaskPriority

if TYPE_CHECKING:
    from app.models.client import Client
    from app.models.recurring_task import RecurringTask
    from app.models.task import Task
    from app.models.user import User
    from app.models.workflow import Workflow


class TaskTemplate(Base):
    """Reusable task definition blueprint for generating standardized tasks and recurring workflows."""

    __tablename__ = "task_templates"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
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

    default_due_offset_days: Mapped[Optional[int]] = mapped_column(
        Integer,
        nullable=True,
    )
    default_next_action_offset_days: Mapped[Optional[int]] = mapped_column(
        Integer,
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
        back_populates="template",
    )
    recurring_tasks: Mapped[List["RecurringTask"]] = relationship(
        "RecurringTask",
        back_populates="template",
    )
