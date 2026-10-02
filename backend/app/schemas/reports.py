"""Pydantic schemas for Phase 17 Reports, Exports & Management Insights."""

from datetime import datetime
from typing import Dict, List, Literal, Optional, Union
import uuid
from pydantic import BaseModel, ConfigDict, Field
from app.models.enums import TaskPriority, TaskStatus


# =============================================================================
# 1. Shared Filter & Export Request Models
# =============================================================================

ExportFormat = Literal["csv", "json"]
ReportType = Literal[
    "task_summary",
    "task_detail",
    "productivity",
    "workload",
    "activity",
    "reminders_followups",
]


class ReportFilterParams(BaseModel):
    """Shared query filter parameters across management reports and exports."""

    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None
    status: Optional[TaskStatus] = None
    priority: Optional[TaskPriority] = None
    client_id: Optional[Union[uuid.UUID, str]] = None
    workflow_id: Optional[Union[uuid.UUID, str]] = None
    assigned_user_id: Optional[Union[uuid.UUID, str]] = None
    unassigned: Optional[bool] = None
    overdue: Optional[bool] = None
    due_today: Optional[bool] = None
    upcoming: Optional[bool] = None
    has_next_action: Optional[bool] = None
    no_next_action: Optional[bool] = None
    near_max_attempts: Optional[bool] = None
    search: Optional[str] = None
    source: Optional[Literal["manual", "template", "recurring"]] = None


# =============================================================================
# 2. Task Summary Report Schemas
# =============================================================================

class TaskSummaryStatusBreakdown(BaseModel):
    """Status distribution counts in task summary report."""

    pending: int = 0
    in_progress: int = 0
    completed: int = 0
    cancelled: int = 0


class TaskSummaryPriorityBreakdown(BaseModel):
    """Priority distribution counts in task summary report."""

    urgent: int = 0
    high: int = 0
    medium: int = 0
    low: int = 0


class TaskSummaryReport(BaseModel):
    """Aggregated Task Summary report response."""

    model_config = ConfigDict(from_attributes=True)

    total_tasks: int = 0
    open_tasks: int = 0
    completed_tasks: int = 0
    cancelled_tasks: int = 0
    overdue_tasks: int = 0
    due_today_tasks: int = 0
    upcoming_tasks: int = 0
    near_max_attempts: int = 0
    max_attempts_reached: int = 0
    status_breakdown: TaskSummaryStatusBreakdown
    priority_breakdown: TaskSummaryPriorityBreakdown


# =============================================================================
# 3. Task Detail Report Schemas
# =============================================================================

class TaskDetailReportItem(BaseModel):
    """Enriched task record for tabular reports and exports."""

    model_config = ConfigDict(from_attributes=True)

    id: Union[uuid.UUID, str]
    title: str
    subject_line: Optional[str] = None
    description: Optional[str] = None
    status: TaskStatus
    priority: TaskPriority
    client_id: Optional[Union[uuid.UUID, str]] = None
    client_name: Optional[str] = None
    workflow_id: Optional[Union[uuid.UUID, str]] = None
    workflow_name: Optional[str] = None
    assigned_user_id: Optional[Union[uuid.UUID, str]] = None
    assigned_user_name: Optional[str] = None
    assigned_user_email: Optional[str] = None
    due_date: Optional[datetime] = None
    next_action_date: Optional[datetime] = None
    attempt_count: int = 0
    max_attempts: int = 2
    created_at: datetime
    updated_at: datetime
    completed_at: Optional[datetime] = None
    source: str = "manual"  # "manual" | "template" | "recurring"


class TaskDetailReportResponse(BaseModel):
    """Paginated task detail report response."""

    items: List[TaskDetailReportItem]
    total: int
    page: int
    page_size: int


# =============================================================================
# 4. Productivity Report Schemas
# =============================================================================

class ProductivityDailyTrendPoint(BaseModel):
    """Daily productivity data point with zero-filled date preservation."""

    date: str  # YYYY-MM-DD
    created_count: int = 0
    completed_count: int = 0
    overdue_count: int = 0
    completion_rate: float = 0.0  # 0.0 to 100.0 percentage


class ProductivityReportResponse(BaseModel):
    """Comprehensive productivity report response over requested time frame."""

    date_from: datetime
    date_to: datetime
    total_created: int = 0
    total_completed: int = 0
    total_overdue: int = 0
    overall_completion_rate: float = 0.0  # 0.0 to 100.0 percentage
    daily_trends: List[ProductivityDailyTrendPoint]


# =============================================================================
# 5. Workload Report Schemas
# =============================================================================

class WorkloadReportItem(BaseModel):
    """Workload metrics breakdown for an entity (Assignee, Client, Workflow)."""

    id: Optional[Union[uuid.UUID, str]] = None
    name: str
    email: Optional[str] = None
    open_tasks: int = 0
    completed_tasks: int = 0
    overdue_tasks: int = 0
    due_today_tasks: int = 0
    total_tasks: int = 0


class WorkloadReportResponse(BaseModel):
    """Comprehensive multi-dimensional workload report."""

    by_assignee: List[WorkloadReportItem]
    by_client: List[WorkloadReportItem]
    by_workflow: List[WorkloadReportItem]
    total_open_tasks: int = 0
    total_completed_tasks: int = 0
    total_overdue_tasks: int = 0
    total_tasks: int = 0


# =============================================================================
# 6. Activity / Audit Report Schemas
# =============================================================================

class ActivityReportItem(BaseModel):
    """Single audit log entry in the activity report."""

    model_config = ConfigDict(from_attributes=True)

    id: Union[uuid.UUID, str]
    task_id: Optional[Union[uuid.UUID, str]] = None
    task_title: Optional[str] = None
    action: str
    actor_id: Optional[Union[uuid.UUID, str]] = None
    actor_name: Optional[str] = None
    actor_email: Optional[str] = None
    old_value: Optional[str] = None
    new_value: Optional[str] = None
    reason: Optional[str] = None
    created_at: datetime


class ActivityReportResponse(BaseModel):
    """Paginated activity audit report response."""

    items: List[ActivityReportItem]
    total: int
    page: int
    page_size: int
    action_counts: Dict[str, int] = Field(default_factory=dict)


# =============================================================================
# 7. Reminder & Follow-up Report Schemas
# =============================================================================

class ReminderFollowUpSummary(BaseModel):
    """High-level KPI metrics for scheduling queues."""

    reminders_due: int = 0
    reminders_sent: int = 0
    reminders_pending: int = 0
    reminders_total: int = 0
    follow_ups_overdue: int = 0
    follow_ups_today: int = 0
    follow_ups_upcoming: int = 0
    follow_ups_completed: int = 0
    follow_ups_pending: int = 0
    follow_ups_total: int = 0


class ReminderReportItem(BaseModel):
    """Single reminder item in scheduling report."""

    id: Union[uuid.UUID, str]
    task_id: Union[uuid.UUID, str]
    task_title: str
    remind_at: datetime
    is_sent: bool
    message: str
    created_at: datetime


class FollowUpReportItem(BaseModel):
    """Single follow-up item in scheduling report."""

    id: Union[uuid.UUID, str]
    task_id: Union[uuid.UUID, str]
    task_title: str
    scheduled_at: datetime
    completed_at: Optional[datetime] = None
    notes: Optional[str] = None
    is_completed: bool
    created_at: datetime


class ReminderFollowUpReportResponse(BaseModel):
    """Combined scheduling report response."""

    summary: ReminderFollowUpSummary
    reminders: List[ReminderReportItem]
    follow_ups: List[FollowUpReportItem]
