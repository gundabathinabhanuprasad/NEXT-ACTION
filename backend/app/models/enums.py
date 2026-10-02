"""Domain enumerations for NextAction database models."""

import enum


class TaskStatus(str, enum.Enum):
    """Task lifecycle statuses."""

    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class TaskPriority(str, enum.Enum):
    """Task urgency priorities."""

    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    URGENT = "urgent"


class RecurrenceType(str, enum.Enum):
    """Recurring task frequency types."""

    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    CUSTOM_INTERVAL = "custom_interval"

