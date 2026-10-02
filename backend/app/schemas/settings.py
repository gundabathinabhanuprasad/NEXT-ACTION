"""Pydantic schemas for User Settings and Preferences."""

from datetime import datetime
from typing import Optional
import uuid
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator


VALID_DATE_FORMATS = {"YYYY-MM-DD", "DD/MM/YYYY", "MM/DD/YYYY"}
VALID_TIME_FORMATS = {"24h", "12h"}
VALID_FIRST_DAYS = {"monday", "sunday"}
VALID_THEMES = {"system", "light", "dark"}
VALID_PRIORITIES = {"low", "medium", "high", "urgent"}
VALID_STATUS_FILTERS = {"all", "pending", "in_progress", "completed"}
VALID_TASK_SORTS = {"due_date", "created_at", "priority", "title"}
VALID_SORT_ORDERS = {"asc", "desc"}
VALID_PAGE_SIZES = {10, 20, 50, 100}
VALID_DASHBOARD_RANGES = {"today", "last_7_days", "last_30_days", "this_month"}
VALID_REPORT_RANGES = {"all", "today", "last_7_days", "last_30_days", "this_month"}
VALID_REPORT_TYPES = {
    "task_summary",
    "task_detail",
    "productivity",
    "workload",
    "activity",
    "reminders_followups",
}
VALID_EXPORT_FORMATS = {"csv", "json"}


class UserSettingsBase(BaseModel):
    """Base schema for user settings."""

    display_name_override: Optional[str] = Field(None, max_length=255)
    timezone: str = Field(default="UTC", max_length=100)
    date_format: str = Field(default="YYYY-MM-DD")
    time_format: str = Field(default="24h")
    first_day_of_week: str = Field(default="monday")

    theme: str = Field(default="system")
    compact_mode: bool = Field(default=False)

    default_task_priority: str = Field(default="medium")
    default_task_status_filter: str = Field(default="all")
    default_task_sort: str = Field(default="due_date")
    default_task_sort_order: str = Field(default="asc")
    default_max_attempts: int = Field(default=3, ge=1, le=10)
    default_page_size: int = Field(default=20)

    default_dashboard_time_range: str = Field(default="last_7_days")
    default_report_date_range: str = Field(default="last_7_days")
    default_report_type: str = Field(default="task_summary")
    default_export_format: str = Field(default="csv")

    notify_task_assigned: bool = Field(default=True)
    notify_task_reassigned: bool = Field(default=True)
    notify_reminder_due: bool = Field(default=True)
    notify_follow_up_due: bool = Field(default=True)
    notify_next_action_due: bool = Field(default=True)
    notify_task_overdue: bool = Field(default=True)
    notify_attempt_limit_reached: bool = Field(default=True)
    notify_task_completed: bool = Field(default=True)
    notify_task_reopened: bool = Field(default=True)


class UserSettingsResponse(UserSettingsBase):
    """Normalized response schema for user settings."""

    id: uuid.UUID
    user_id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class UserSettingsUpdate(BaseModel):
    """Schema for partial update of user settings (PATCH)."""

    display_name_override: Optional[str] = None
    timezone: Optional[str] = None
    date_format: Optional[str] = None
    time_format: Optional[str] = None
    first_day_of_week: Optional[str] = None

    theme: Optional[str] = None
    compact_mode: Optional[bool] = None

    default_task_priority: Optional[str] = None
    default_task_status_filter: Optional[str] = None
    default_task_sort: Optional[str] = None
    default_task_sort_order: Optional[str] = None
    default_max_attempts: Optional[int] = Field(None, ge=1, le=10)
    default_page_size: Optional[int] = None

    default_dashboard_time_range: Optional[str] = None
    default_report_date_range: Optional[str] = None
    default_report_type: Optional[str] = None
    default_export_format: Optional[str] = None

    notify_task_assigned: Optional[bool] = None
    notify_task_reassigned: Optional[bool] = None
    notify_reminder_due: Optional[bool] = None
    notify_follow_up_due: Optional[bool] = None
    notify_next_action_due: Optional[bool] = None
    notify_task_overdue: Optional[bool] = None
    notify_attempt_limit_reached: Optional[bool] = None
    notify_task_completed: Optional[bool] = None
    notify_task_reopened: Optional[bool] = None

    @field_validator("timezone")
    @classmethod
    def validate_tz(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            try:
                ZoneInfo(v)
            except (ZoneInfoNotFoundError, ValueError, KeyError):
                raise ValueError(f"Invalid IANA timezone identifier: {v}")
        return v

    @field_validator("date_format")
    @classmethod
    def validate_date_fmt(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_DATE_FORMATS:
            raise ValueError(f"date_format must be one of {sorted(VALID_DATE_FORMATS)}")
        return v

    @field_validator("time_format")
    @classmethod
    def validate_time_fmt(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in VALID_TIME_FORMATS:
            raise ValueError(f"time_format must be one of {sorted(VALID_TIME_FORMATS)}")
        return v

    @field_validator("first_day_of_week")
    @classmethod
    def validate_first_day(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_FIRST_DAYS:
            raise ValueError(f"first_day_of_week must be one of {sorted(VALID_FIRST_DAYS)}")
        return v.lower() if v else v

    @field_validator("theme")
    @classmethod
    def validate_thm(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_THEMES:
            raise ValueError(f"theme must be one of {sorted(VALID_THEMES)}")
        return v.lower() if v else v

    @field_validator("default_task_priority")
    @classmethod
    def validate_prio(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_PRIORITIES:
            raise ValueError(f"default_task_priority must be one of {sorted(VALID_PRIORITIES)}")
        return v.lower() if v else v

    @field_validator("default_task_status_filter")
    @classmethod
    def validate_status_flt(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_STATUS_FILTERS:
            raise ValueError(f"default_task_status_filter must be one of {sorted(VALID_STATUS_FILTERS)}")
        return v.lower() if v else v

    @field_validator("default_task_sort")
    @classmethod
    def validate_sort(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_TASK_SORTS:
            raise ValueError(f"default_task_sort must be one of {sorted(VALID_TASK_SORTS)}")
        return v.lower() if v else v

    @field_validator("default_task_sort_order")
    @classmethod
    def validate_order(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_SORT_ORDERS:
            raise ValueError(f"default_task_sort_order must be one of {sorted(VALID_SORT_ORDERS)}")
        return v.lower() if v else v

    @field_validator("default_page_size")
    @classmethod
    def validate_pg_size(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v not in VALID_PAGE_SIZES:
            raise ValueError(f"default_page_size must be one of {sorted(VALID_PAGE_SIZES)}")
        return v

    @field_validator("default_dashboard_time_range")
    @classmethod
    def validate_dash_range(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_DASHBOARD_RANGES:
            raise ValueError(f"default_dashboard_time_range must be one of {sorted(VALID_DASHBOARD_RANGES)}")
        return v.lower() if v else v

    @field_validator("default_report_date_range")
    @classmethod
    def validate_rep_range(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_REPORT_RANGES:
            raise ValueError(f"default_report_date_range must be one of {sorted(VALID_REPORT_RANGES)}")
        return v.lower() if v else v

    @field_validator("default_report_type")
    @classmethod
    def validate_rep_type(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_REPORT_TYPES:
            raise ValueError(f"default_report_type must be one of {sorted(VALID_REPORT_TYPES)}")
        return v.lower() if v else v

    @field_validator("default_export_format")
    @classmethod
    def validate_exp_fmt(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v.lower() not in VALID_EXPORT_FORMATS:
            raise ValueError(f"default_export_format must be one of {sorted(VALID_EXPORT_FORMATS)}")
        return v.lower() if v else v
