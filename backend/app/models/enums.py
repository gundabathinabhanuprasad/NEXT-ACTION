"""Domain enumerations for NextAction database models."""

import enum


class TaskStatus(str, enum.Enum):
    """Task lifecycle statuses."""

    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    CANCELLED = "cancelled"

    @classmethod
    def _missing_(cls, value: object):
        if isinstance(value, str):
            val_norm = value.strip().lower()
            for member in cls:
                if member.value == val_norm or member.name.lower() == val_norm:
                    return member
        return None


class TaskPriority(str, enum.Enum):
    """Task urgency priorities."""

    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    URGENT = "urgent"

    @classmethod
    def _missing_(cls, value: object):
        if isinstance(value, str):
            val_norm = value.strip().lower()
            for member in cls:
                if member.value == val_norm or member.name.lower() == val_norm:
                    return member
        return None


class RecurrenceType(str, enum.Enum):
    """Recurring task frequency types."""

    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    CUSTOM_INTERVAL = "custom_interval"

    @classmethod
    def _missing_(cls, value: object):
        if isinstance(value, str):
            val_norm = value.strip().lower()
            for member in cls:
                if member.value == val_norm or member.name.lower() == val_norm:
                    return member
        return None

