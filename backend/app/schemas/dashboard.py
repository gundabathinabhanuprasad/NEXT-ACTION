"""Pydantic schemas for Dashboard, Productivity Analytics & Workload Insights."""

from datetime import datetime
from typing import List, Literal, Optional, Union
import uuid
from pydantic import BaseModel, ConfigDict
from app.schemas.history import TaskHistoryResponse
from app.schemas.notification import NotificationResponse


DashboardTimeRange = Literal["today", "last_7_days", "last_30_days", "this_month"]


class DashboardKpis(BaseModel):
    """Primary KPI metrics for operational tracking."""

    total_open_tasks: int
    due_today_tasks: int
    overdue_tasks: int
    upcoming_tasks: int
    completed_tasks: int
    completed_in_range: int
    created_in_range: int
    near_max_attempts: int
    max_attempts_reached: int
    pending_follow_ups: int
    overdue_follow_ups: int
    due_today_follow_ups: int
    due_reminders: int
    unread_notifications: int


class DashboardAttentionSummary(BaseModel):
    """Urgent and today-due attention aggregates."""

    urgent_count: int
    today_count: int


class DashboardStatusDistribution(BaseModel):
    """Active and terminal task status counts."""

    pending: int
    in_progress: int
    completed: int
    cancelled: int


class DashboardPriorityDistribution(BaseModel):
    """Active workload count breakdown by priority tier."""

    urgent: int
    high: int
    medium: int
    low: int


class DashboardAttemptPressure(BaseModel):
    """Work attempt distribution for active tasks."""

    zero_attempts: int
    one_attempt: int
    near_max: int
    max_reached: int


class AssigneeWorkloadItem(BaseModel):
    """Operational workload summary per team member / unassigned."""

    user_id: Optional[Union[uuid.UUID, str]] = None
    user_name: str
    open_tasks: int
    due_today: int
    overdue: int
    completed: int


class ClientWorkloadItem(BaseModel):
    """Operational workload summary per client."""

    client_id: Union[uuid.UUID, str]
    client_name: str
    open_tasks: int
    due_today: int
    overdue: int
    completed: int


class WorkflowWorkloadItem(BaseModel):
    """Operational workload summary per workflow."""

    workflow_id: Union[uuid.UUID, str]
    workflow_name: str
    open_tasks: int
    due_today: int
    overdue: int
    completed: int


class DashboardWorkloadBreakdown(BaseModel):
    """Comprehensive workload distributions across assignees, clients, and workflows."""

    by_assignee: List[AssigneeWorkloadItem]
    by_client: List[ClientWorkloadItem]
    by_workflow: List[WorkflowWorkloadItem]


class FollowUpAnalytics(BaseModel):
    """Follow-up queue health and execution analytics."""

    pending: int
    overdue: int
    due_today: int
    upcoming: int
    completed: int


class ReminderAnalytics(BaseModel):
    """Reminder schedule queue analytics."""

    pending: int
    due_today: int
    overdue: int
    upcoming: int


class DashboardSchedulingAnalytics(BaseModel):
    """Combined scheduling insights for follow-ups and reminders."""

    follow_ups: FollowUpAnalytics
    reminders: ReminderAnalytics


class DashboardTrendPoint(BaseModel):
    """Daily time-series trend data point."""

    date: str  # YYYY-MM-DD
    created_count: int
    completed_count: int
    overdue_count: int


class DashboardSummaryResponse(BaseModel):
    """Consolidated, high-performance PostgreSQL dashboard summary response."""

    model_config = ConfigDict(from_attributes=True)

    time_range: str
    range_start: datetime
    range_end: datetime
    kpis: DashboardKpis
    attention: DashboardAttentionSummary
    status_distribution: DashboardStatusDistribution
    priority_distribution: DashboardPriorityDistribution
    attempt_pressure: DashboardAttemptPressure
    workload: DashboardWorkloadBreakdown
    scheduling: DashboardSchedulingAnalytics
    trends: List[DashboardTrendPoint]
    recent_activities: List[TaskHistoryResponse]
    recent_notifications: List[NotificationResponse]
