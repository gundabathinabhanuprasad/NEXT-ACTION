"""Scheduler Pydantic schemas and DTOs for Phase 19 Automated Reminder & Notification Delivery."""

from datetime import datetime
from typing import Dict, Optional
import uuid
from pydantic import BaseModel, ConfigDict, Field


class CategoryEvaluationDetail(BaseModel):
    """Detailed evaluation statistics for a single notification category."""

    model_config = ConfigDict(from_attributes=True)

    evaluated: int = Field(default=0, ge=0, description="Candidate items evaluated in this category")
    notifications_created: int = Field(default=0, ge=0, description="New notifications created")
    duplicates_skipped: int = Field(default=0, ge=0, description="Duplicate notifications skipped via dedup key")
    preferences_suppressed: int = Field(default=0, ge=0, description="Notifications suppressed by user preference")
    errors: int = Field(default=0, ge=0, description="Non-fatal record errors isolated")


class SchedulerEvaluationRequest(BaseModel):
    """Request payload for triggering scheduling engine evaluation."""

    as_of: Optional[datetime] = Field(
        default=None,
        description="Optional evaluation timestamp in UTC; defaults to current time.",
    )
    user_scoped: bool = Field(
        default=True,
        description="Whether to evaluate strictly for the calling user or system-wide.",
    )


class SchedulerEvaluationResponse(BaseModel):
    """Structured response detailing evaluation results and category metrics."""

    model_config = ConfigDict(from_attributes=True)

    evaluated: int = Field(..., ge=0, description="Total candidate items evaluated")
    notifications_created: int = Field(..., ge=0, description="Total persistent notifications created")
    duplicates_skipped: int = Field(..., ge=0, description="Total duplicate notifications skipped via dedup key")
    preferences_suppressed: int = Field(..., ge=0, description="Total notifications suppressed by user preference")
    errors_count: int = Field(default=0, ge=0, description="Total non-fatal item errors isolated")
    duration_ms: float = Field(..., ge=0.0, description="Execution duration in milliseconds")
    evaluated_at: datetime = Field(..., description="Timestamp of evaluation run (UTC)")
    user_id: Optional[uuid.UUID] = Field(
        default=None,
        description="User ID if evaluation was user-scoped; None if global.",
    )
    details: Dict[str, CategoryEvaluationDetail] = Field(
        default_factory=dict,
        description="Category breakdown for reminders, follow-ups, next-actions, overdue, and attempt limits",
    )
