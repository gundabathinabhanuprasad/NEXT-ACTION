"""Reports and Exports API router for Phase 17 Management Insights."""

from datetime import datetime
from typing import Any, Optional, Union
import uuid
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.orm import Session
from app.api.dependencies import get_current_user
from app.db.session import get_db
from app.models.enums import TaskPriority, TaskStatus
from app.models.user import User
from app.schemas.reports import (
    ActivityReportResponse,
    ExportFormat,
    ProductivityReportResponse,
    ReminderFollowUpReportResponse,
    ReportFilterParams,
    ReportType,
    TaskDetailReportResponse,
    TaskSummaryReport,
    WorkloadReportResponse,
)
from app.services.report_service import (
    export_to_csv,
    export_to_json,
    get_activity_report,
    get_productivity_report,
    get_reminders_followups_report,
    get_task_detail_report,
    get_task_summary_report,
    get_workload_report,
)

router = APIRouter(prefix="/reports", tags=["Reports & Exports"])

SORT_ALLOWLIST = {
    "created_at",
    "updated_at",
    "due_date",
    "next_action_date",
    "priority",
    "status",
    "title",
    "attempt_count",
}


def _validate_sort(sort_by: str) -> str:
    """Validate sort field against security allowlist."""
    if sort_by not in SORT_ALLOWLIST:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid sort_by field '{sort_by}'. Allowed fields: {sorted(list(SORT_ALLOWLIST))}",
        )
    return sort_by


def _validate_date_range(date_from: Optional[datetime], date_to: Optional[datetime]) -> None:
    """Validate that date_from does not exceed date_to."""
    if date_from is not None and date_to is not None and date_from > date_to:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="date_from cannot be strictly later than date_to",
        )


# =============================================================================
# 1. Task Summary Report Endpoint
# =============================================================================

@router.get(
    "/task-summary",
    response_model=TaskSummaryReport,
    summary="Get aggregated task summary metrics",
)
def get_task_summary(
    search: Optional[str] = Query(default=None),
    status_filter: Optional[TaskStatus] = Query(default=None, alias="status"),
    priority: Optional[TaskPriority] = Query(default=None),
    client_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    workflow_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    assigned_user_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    unassigned: Optional[bool] = Query(default=None),
    date_from: Optional[datetime] = Query(default=None),
    date_to: Optional[datetime] = Query(default=None),
    overdue: Optional[bool] = Query(default=None),
    due_today: Optional[bool] = Query(default=None),
    upcoming: Optional[bool] = Query(default=None),
    has_next_action: Optional[bool] = Query(default=None),
    no_next_action: Optional[bool] = Query(default=None),
    near_max_attempts: Optional[bool] = Query(default=None),
    source: Optional[str] = Query(default=None, pattern="^(manual|template|recurring)$"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TaskSummaryReport:
    """Retrieve high-level task metrics and distributions aggregated in PostgreSQL."""
    _validate_date_range(date_from, date_to)

    filters = ReportFilterParams(
        date_from=date_from,
        date_to=date_to,
        status=status_filter,
        priority=priority,
        client_id=client_id,
        workflow_id=workflow_id,
        assigned_user_id=assigned_user_id,
        unassigned=unassigned,
        overdue=overdue,
        due_today=due_today,
        upcoming=upcoming,
        has_next_action=has_next_action,
        no_next_action=no_next_action,
        near_max_attempts=near_max_attempts,
        search=search,
        source=source,  # type: ignore
    )
    return get_task_summary_report(db=db, filters=filters)


# =============================================================================
# 2. Task Detail Report Endpoint
# =============================================================================

@router.get(
    "/tasks",
    response_model=TaskDetailReportResponse,
    summary="Get filtered, detailed task list report",
)
def get_task_detail(
    search: Optional[str] = Query(default=None),
    status_filter: Optional[TaskStatus] = Query(default=None, alias="status"),
    priority: Optional[TaskPriority] = Query(default=None),
    client_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    workflow_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    assigned_user_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    unassigned: Optional[bool] = Query(default=None),
    date_from: Optional[datetime] = Query(default=None),
    date_to: Optional[datetime] = Query(default=None),
    overdue: Optional[bool] = Query(default=None),
    due_today: Optional[bool] = Query(default=None),
    upcoming: Optional[bool] = Query(default=None),
    has_next_action: Optional[bool] = Query(default=None),
    no_next_action: Optional[bool] = Query(default=None),
    near_max_attempts: Optional[bool] = Query(default=None),
    source: Optional[str] = Query(default=None, pattern="^(manual|template|recurring)$"),
    sort_by: str = Query(default="created_at"),
    sort_order: str = Query(default="desc", pattern="^(asc|desc)$"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TaskDetailReportResponse:
    """Retrieve detailed, paginated task list with relations and custom filters."""
    _validate_sort(sort_by)
    _validate_date_range(date_from, date_to)

    filters = ReportFilterParams(
        date_from=date_from,
        date_to=date_to,
        status=status_filter,
        priority=priority,
        client_id=client_id,
        workflow_id=workflow_id,
        assigned_user_id=assigned_user_id,
        unassigned=unassigned,
        overdue=overdue,
        due_today=due_today,
        upcoming=upcoming,
        has_next_action=has_next_action,
        no_next_action=no_next_action,
        near_max_attempts=near_max_attempts,
        search=search,
        source=source,  # type: ignore
    )
    return get_task_detail_report(
        db=db,
        filters=filters,
        sort_by=sort_by,
        sort_order=sort_order,
        page=page,
        page_size=page_size,
    )


# =============================================================================
# 3. Productivity Report Endpoint
# =============================================================================

@router.get(
    "/productivity",
    response_model=ProductivityReportResponse,
    summary="Get productivity metrics & daily trends",
)
def get_productivity(
    date_from: Optional[datetime] = Query(default=None),
    date_to: Optional[datetime] = Query(default=None),
    client_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    workflow_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    assigned_user_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    unassigned: Optional[bool] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ProductivityReportResponse:
    """Compute productivity and completion trends with zero-filled date series."""
    _validate_date_range(date_from, date_to)

    filters = ReportFilterParams(
        date_from=date_from,
        date_to=date_to,
        client_id=client_id,
        workflow_id=workflow_id,
        assigned_user_id=assigned_user_id,
        unassigned=unassigned,
    )
    return get_productivity_report(
        db=db,
        date_from=date_from,
        date_to=date_to,
        filters=filters,
    )


# =============================================================================
# 4. Workload Report Endpoint
# =============================================================================

@router.get(
    "/workload",
    response_model=WorkloadReportResponse,
    summary="Get multi-dimensional workload report",
)
def get_workload(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> WorkloadReportResponse:
    """Retrieve workload distributions across assignees, clients, and workflows."""
    return get_workload_report(db=db)


# =============================================================================
# 5. Activity / Audit Report Endpoint
# =============================================================================

@router.get(
    "/activity",
    response_model=ActivityReportResponse,
    summary="Get activity audit report",
)
def get_activity(
    action: Optional[str] = Query(default=None),
    actor_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    task_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    date_from: Optional[datetime] = Query(default=None),
    date_to: Optional[datetime] = Query(default=None),
    search: Optional[str] = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ActivityReportResponse:
    """Retrieve audit history entries with action type summary counts."""
    _validate_date_range(date_from, date_to)

    return get_activity_report(
        db=db,
        action=action,
        actor_id=actor_id,
        task_id=task_id,
        date_from=date_from,
        date_to=date_to,
        search=search,
        page=page,
        page_size=page_size,
    )


# =============================================================================
# 6. Reminders & Follow-ups Report Endpoint
# =============================================================================

@router.get(
    "/reminders-followups",
    response_model=ReminderFollowUpReportResponse,
    summary="Get reminder & follow-up queues report",
)
def get_reminders_followups(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ReminderFollowUpReportResponse:
    """Retrieve combined scheduling queue statistics and detailed items."""
    return get_reminders_followups_report(db=db)


# =============================================================================
# 7. Unified and Dedicated Export Endpoints
# =============================================================================

def _build_export_response(report_type: str, export_format: ExportFormat, data: Any) -> Response:
    """Format and return streaming/attachment HTTP response for downloads."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{report_type}_report_{timestamp}"

    if export_format == "json":
        content = export_to_json(report_type, data)
        media_type = "application/json; charset=utf-8"
        ext = "json"
    else:
        content = export_to_csv(report_type, data)
        # Prepend UTF-8 BOM so spreadsheet applications properly render Unicode
        if not content.startswith("\ufeff"):
            content = "\ufeff" + content
        media_type = "text/csv; charset=utf-8"
        ext = "csv"

    headers = {
        "Content-Disposition": f'attachment; filename="{filename}.{ext}"',
        "Cache-Control": "no-cache, no-store, must-revalidate",
    }
    return Response(content=content, media_type=media_type, headers=headers)


@router.get(
    "/export",
    summary="Unified on-demand report export",
)
def export_report(
    report_type: ReportType = Query(..., description="Report type to export"),
    format: ExportFormat = Query(default="csv", description="Export format: csv or json"),
    search: Optional[str] = Query(default=None),
    status_filter: Optional[TaskStatus] = Query(default=None, alias="status"),
    priority: Optional[TaskPriority] = Query(default=None),
    client_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    workflow_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    assigned_user_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    unassigned: Optional[bool] = Query(default=None),
    date_from: Optional[datetime] = Query(default=None),
    date_to: Optional[datetime] = Query(default=None),
    overdue: Optional[bool] = Query(default=None),
    due_today: Optional[bool] = Query(default=None),
    upcoming: Optional[bool] = Query(default=None),
    has_next_action: Optional[bool] = Query(default=None),
    no_next_action: Optional[bool] = Query(default=None),
    near_max_attempts: Optional[bool] = Query(default=None),
    source: Optional[str] = Query(default=None, pattern="^(manual|template|recurring)$"),
    action: Optional[str] = Query(default=None),
    actor_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    task_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    """Generate and stream on-demand CSV or JSON report export."""
    _validate_date_range(date_from, date_to)

    filters = ReportFilterParams(
        date_from=date_from,
        date_to=date_to,
        status=status_filter,
        priority=priority,
        client_id=client_id,
        workflow_id=workflow_id,
        assigned_user_id=assigned_user_id,
        unassigned=unassigned,
        overdue=overdue,
        due_today=due_today,
        upcoming=upcoming,
        has_next_action=has_next_action,
        no_next_action=no_next_action,
        near_max_attempts=near_max_attempts,
        search=search,
        source=source,  # type: ignore
    )

    if report_type == "task_summary":
        data = get_task_summary_report(db=db, filters=filters)
    elif report_type in ("task_detail", "tasks"):
        data = get_task_detail_report(db=db, filters=filters, page=1, page_size=1000)
    elif report_type == "productivity":
        data = get_productivity_report(db=db, date_from=date_from, date_to=date_to, filters=filters)
    elif report_type == "workload":
        data = get_workload_report(db=db, filters=filters)
    elif report_type == "activity":
        data = get_activity_report(
            db=db,
            action=action,
            actor_id=actor_id,
            task_id=task_id,
            date_from=date_from,
            date_to=date_to,
            search=search,
            page=1,
            page_size=1000,
        )
    elif report_type == "reminders_followups":
        data = get_reminders_followups_report(db=db, filters=filters)
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown report type: {report_type}",
        )

    return _build_export_response(report_type=report_type, export_format=format, data=data)


# Dedicated convenience export endpoints matching prompt suggestions
@router.get("/tasks/export", summary="Export task detail report")
def export_tasks_report(
    format: ExportFormat = Query(default="csv"),
    search: Optional[str] = Query(default=None),
    status_filter: Optional[TaskStatus] = Query(default=None, alias="status"),
    priority: Optional[TaskPriority] = Query(default=None),
    client_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    workflow_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    assigned_user_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    unassigned: Optional[bool] = Query(default=None),
    date_from: Optional[datetime] = Query(default=None),
    date_to: Optional[datetime] = Query(default=None),
    overdue: Optional[bool] = Query(default=None),
    due_today: Optional[bool] = Query(default=None),
    upcoming: Optional[bool] = Query(default=None),
    has_next_action: Optional[bool] = Query(default=None),
    no_next_action: Optional[bool] = Query(default=None),
    near_max_attempts: Optional[bool] = Query(default=None),
    source: Optional[str] = Query(default=None, pattern="^(manual|template|recurring)$"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    """Dedicated endpoint for task report export."""
    _validate_date_range(date_from, date_to)
    filters = ReportFilterParams(
        date_from=date_from,
        date_to=date_to,
        status=status_filter,
        priority=priority,
        client_id=client_id,
        workflow_id=workflow_id,
        assigned_user_id=assigned_user_id,
        unassigned=unassigned,
        overdue=overdue,
        due_today=due_today,
        upcoming=upcoming,
        has_next_action=has_next_action,
        no_next_action=no_next_action,
        near_max_attempts=near_max_attempts,
        search=search,
        source=source,  # type: ignore
    )
    data = get_task_detail_report(db=db, filters=filters, page=1, page_size=1000)
    return _build_export_response(report_type="task_detail", export_format=format, data=data)


@router.get("/activity/export", summary="Export activity report")
def export_activity_report(
    format: ExportFormat = Query(default="csv"),
    action: Optional[str] = Query(default=None),
    actor_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    task_id: Optional[Union[uuid.UUID, str]] = Query(default=None),
    date_from: Optional[datetime] = Query(default=None),
    date_to: Optional[datetime] = Query(default=None),
    search: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    """Dedicated endpoint for activity report export."""
    _validate_date_range(date_from, date_to)
    data = get_activity_report(
        db=db,
        action=action,
        actor_id=actor_id,
        task_id=task_id,
        date_from=date_from,
        date_to=date_to,
        search=search,
        page=1,
        page_size=1000,
    )
    return _build_export_response(report_type="activity", export_format=format, data=data)


@router.get("/workload/export", summary="Export workload report")
def export_workload_report(
    format: ExportFormat = Query(default="csv"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    """Dedicated endpoint for workload report export."""
    data = get_workload_report(db=db)
    return _build_export_response(report_type="workload", export_format=format, data=data)
