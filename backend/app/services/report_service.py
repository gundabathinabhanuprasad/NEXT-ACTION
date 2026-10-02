"""Report service providing server-side PostgreSQL aggregation, analytics, and on-demand exports for Phase 17."""

import csv
from datetime import datetime, timedelta, timezone
import io
import json
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session, joinedload
from app.models.client import Client
from app.models.enums import TaskPriority, TaskStatus
from app.models.follow_up import FollowUp
from app.models.reminder import Reminder
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.user import User
from app.models.workflow import Workflow
from app.persistence.gateway import get_persistence_gateway
from app.persistence.mongodb.report_service import MongoReportService
from app.schemas.reports import (
    ActivityReportItem,
    ActivityReportResponse,
    FollowUpReportItem,
    ProductivityDailyTrendPoint,
    ProductivityReportResponse,
    ReminderFollowUpReportResponse,
    ReminderFollowUpSummary,
    ReminderReportItem,
    ReportFilterParams,
    TaskDetailReportItem,
    TaskDetailReportResponse,
    TaskSummaryPriorityBreakdown,
    TaskSummaryReport,
    TaskSummaryStatusBreakdown,
    WorkloadReportItem,
    WorkloadReportResponse,
)


def _apply_task_filters(stmt, count_stmt, filters: ReportFilterParams, now: datetime):
    """Apply shared Phase 13/17 report filters to SQLAlchemy select statements."""
    today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
    today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)

    # Search filter
    if filters.search is not None and filters.search.strip():
        term = f"%{filters.search.strip()}%"
        stmt = stmt.outerjoin(Client, Task.client_id == Client.id)
        stmt = stmt.outerjoin(Workflow, Task.workflow_id == Workflow.id)
        stmt = stmt.outerjoin(User, Task.assigned_user_id == User.id)

        count_stmt = count_stmt.outerjoin(Client, Task.client_id == Client.id)
        count_stmt = count_stmt.outerjoin(Workflow, Task.workflow_id == Workflow.id)
        count_stmt = count_stmt.outerjoin(User, Task.assigned_user_id == User.id)

        search_cond = or_(
            Task.title.ilike(term),
            Task.description.ilike(term),
            Task.subject_line.ilike(term),
            Client.name.ilike(term),
            Workflow.name.ilike(term),
            User.name.ilike(term),
            User.email.ilike(term),
        )
        stmt = stmt.where(search_cond)
        count_stmt = count_stmt.where(search_cond)

    if filters.status is not None:
        stmt = stmt.where(Task.status == filters.status)
        count_stmt = count_stmt.where(Task.status == filters.status)

    if filters.priority is not None:
        stmt = stmt.where(Task.priority == filters.priority)
        count_stmt = count_stmt.where(Task.priority == filters.priority)

    if filters.unassigned is True:
        stmt = stmt.where(Task.assigned_user_id.is_(None))
        count_stmt = count_stmt.where(Task.assigned_user_id.is_(None))
    elif filters.assigned_user_id is not None:
        stmt = stmt.where(Task.assigned_user_id == filters.assigned_user_id)
        count_stmt = count_stmt.where(Task.assigned_user_id == filters.assigned_user_id)

    if filters.client_id is not None:
        stmt = stmt.where(Task.client_id == filters.client_id)
        count_stmt = count_stmt.where(Task.client_id == filters.client_id)

    if filters.workflow_id is not None:
        stmt = stmt.where(Task.workflow_id == filters.workflow_id)
        count_stmt = count_stmt.where(Task.workflow_id == filters.workflow_id)

    if filters.date_from is not None:
        stmt = stmt.where(Task.created_at >= filters.date_from)
        count_stmt = count_stmt.where(Task.created_at >= filters.date_from)

    if filters.date_to is not None:
        stmt = stmt.where(Task.created_at <= filters.date_to)
        count_stmt = count_stmt.where(Task.created_at <= filters.date_to)

    if filters.overdue is True:
        stmt = stmt.where(
            Task.due_date < now,
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )
        count_stmt = count_stmt.where(
            Task.due_date < now,
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )

    if filters.due_today is True:
        stmt = stmt.where(
            Task.due_date >= today_start,
            Task.due_date <= today_end,
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )
        count_stmt = count_stmt.where(
            Task.due_date >= today_start,
            Task.due_date <= today_end,
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )

    if filters.upcoming is True:
        stmt = stmt.where(
            Task.due_date > now,
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )
        count_stmt = count_stmt.where(
            Task.due_date > now,
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )

    if filters.no_next_action is True or filters.has_next_action is False:
        stmt = stmt.where(Task.next_action_date.is_(None))
        count_stmt = count_stmt.where(Task.next_action_date.is_(None))
    elif filters.has_next_action is True:
        stmt = stmt.where(Task.next_action_date.is_not(None))
        count_stmt = count_stmt.where(Task.next_action_date.is_not(None))

    if filters.near_max_attempts is True:
        stmt = stmt.where(
            Task.attempt_count >= (Task.max_attempts - 1),
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )
        count_stmt = count_stmt.where(
            Task.attempt_count >= (Task.max_attempts - 1),
            Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
        )

    if filters.source is not None:
        if filters.source == "manual":
            stmt = stmt.where(Task.template_id.is_(None), Task.recurring_task_id.is_(None))
            count_stmt = count_stmt.where(Task.template_id.is_(None), Task.recurring_task_id.is_(None))
        elif filters.source == "template":
            stmt = stmt.where(Task.template_id.is_not(None))
            count_stmt = count_stmt.where(Task.template_id.is_not(None))
        elif filters.source == "recurring":
            stmt = stmt.where(Task.recurring_task_id.is_not(None))
            count_stmt = count_stmt.where(Task.recurring_task_id.is_not(None))

    return stmt, count_stmt


# =============================================================================
# 1. Task Summary Report
# =============================================================================

def get_task_summary_report(db: Session, filters: Optional[ReportFilterParams] = None) -> TaskSummaryReport:
    """Compute aggregated Task Summary metrics entirely inside PostgreSQL or MongoDB."""
    if get_persistence_gateway().is_mongodb:
        return MongoReportService().get_task_summary_report(filters=filters)

    now = datetime.now(timezone.utc)
    today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
    today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)

    stmt = select(
        func.count(Task.id).label("total_tasks"),
        func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
        func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed_tasks"),
        func.count(case((Task.status == TaskStatus.CANCELLED, 1))).label("cancelled_tasks"),
        # Overdue
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.due_date < now,
                    ),
                    1,
                )
            )
        ).label("overdue_tasks"),
        # Due today
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.due_date >= today_start,
                        Task.due_date <= today_end,
                    ),
                    1,
                )
            )
        ).label("due_today_tasks"),
        # Upcoming
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.due_date > now,
                    ),
                    1,
                )
            )
        ).label("upcoming_tasks"),
        # Near max attempts
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.attempt_count >= (Task.max_attempts - 1),
                    ),
                    1,
                )
            )
        ).label("near_max_attempts"),
        # Max attempts reached
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.attempt_count >= Task.max_attempts,
                    ),
                    1,
                )
            )
        ).label("max_attempts_reached"),
        # Status breakdown
        func.count(case((Task.status == TaskStatus.PENDING, 1))).label("pending_count"),
        func.count(case((Task.status == TaskStatus.IN_PROGRESS, 1))).label("in_progress_count"),
        func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed_count"),
        func.count(case((Task.status == TaskStatus.CANCELLED, 1))).label("cancelled_count"),
        # Priority breakdown
        func.count(case((Task.priority == TaskPriority.URGENT, 1))).label("urgent_count"),
        func.count(case((Task.priority == TaskPriority.HIGH, 1))).label("high_count"),
        func.count(case((Task.priority == TaskPriority.MEDIUM, 1))).label("medium_count"),
        func.count(case((Task.priority == TaskPriority.LOW, 1))).label("low_count"),
    )

    count_dummy = select(func.count(Task.id))
    if filters:
        stmt, _ = _apply_task_filters(stmt, count_dummy, filters, now)

    row = db.execute(stmt).one()

    return TaskSummaryReport(
        total_tasks=row.total_tasks or 0,
        open_tasks=row.open_tasks or 0,
        completed_tasks=row.completed_tasks or 0,
        cancelled_tasks=row.cancelled_tasks or 0,
        overdue_tasks=row.overdue_tasks or 0,
        due_today_tasks=row.due_today_tasks or 0,
        upcoming_tasks=row.upcoming_tasks or 0,
        near_max_attempts=row.near_max_attempts or 0,
        max_attempts_reached=row.max_attempts_reached or 0,
        status_breakdown=TaskSummaryStatusBreakdown(
            pending=row.pending_count or 0,
            in_progress=row.in_progress_count or 0,
            completed=row.completed_count or 0,
            cancelled=row.cancelled_count or 0,
        ),
        priority_breakdown=TaskSummaryPriorityBreakdown(
            urgent=row.urgent_count or 0,
            high=row.high_count or 0,
            medium=row.medium_count or 0,
            low=row.low_count or 0,
        ),
    )


# =============================================================================
# 2. Task Detail Report
# =============================================================================

def get_task_detail_report(
    db: Session,
    filters: Optional[ReportFilterParams] = None,
    sort_by: str = "created_at",
    sort_order: str = "desc",
    page: int = 1,
    page_size: int = 20,
) -> TaskDetailReportResponse:
    """Retrieve detailed, filterable, and paginated task list with resolved relations."""
    if get_persistence_gateway().is_mongodb:
        return MongoReportService().get_task_detail_report(
            filters=filters,
            sort_by=sort_by,
            sort_order=sort_order,
            page=page,
            page_size=page_size,
        )

    now = datetime.now(timezone.utc)
    stmt = (
        select(Task)
        .options(
            joinedload(Task.client),
            joinedload(Task.workflow),
            joinedload(Task.assigned_user),
        )
    )
    count_stmt = select(func.count(func.distinct(Task.id)))

    if filters:
        stmt, count_stmt = _apply_task_filters(stmt, count_stmt, filters, now)

    total = db.scalar(count_stmt) or 0

    sort_fields = {
        "created_at": Task.created_at,
        "updated_at": Task.updated_at,
        "due_date": Task.due_date,
        "next_action_date": Task.next_action_date,
        "priority": Task.priority,
        "status": Task.status,
        "title": Task.title,
        "attempt_count": Task.attempt_count,
    }
    sort_col = sort_fields.get(sort_by, Task.created_at)
    if sort_order.lower() == "asc":
        order_expr = sort_col.asc().nullslast() if sort_by in ("due_date", "next_action_date") else sort_col.asc()
    else:
        order_expr = sort_col.desc().nullslast() if sort_by in ("due_date", "next_action_date") else sort_col.desc()

    offset = max(0, (page - 1) * page_size)
    stmt = stmt.order_by(order_expr, Task.created_at.desc(), Task.id.asc()).offset(offset).limit(page_size)

    tasks = list(db.scalars(stmt).unique().all())

    items = []
    for t in tasks:
        source = "manual"
        if t.recurring_task_id is not None:
            source = "recurring"
        elif t.template_id is not None:
            source = "template"

        items.append(
            TaskDetailReportItem(
                id=t.id,
                title=t.title,
                subject_line=t.subject_line,
                description=t.description,
                status=t.status,
                priority=t.priority,
                client_id=t.client_id,
                client_name=t.client.name if t.client else None,
                workflow_id=t.workflow_id,
                workflow_name=t.workflow.name if t.workflow else None,
                assigned_user_id=t.assigned_user_id,
                assigned_user_name=t.assigned_user.name if t.assigned_user else None,
                assigned_user_email=t.assigned_user.email if t.assigned_user else None,
                due_date=t.due_date,
                next_action_date=t.next_action_date,
                attempt_count=t.attempt_count,
                max_attempts=t.max_attempts,
                created_at=t.created_at,
                updated_at=t.updated_at,
                completed_at=t.completed_at,
                source=source,
            )
        )

    return TaskDetailReportResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
    )


# =============================================================================
# 3. Productivity Report
# =============================================================================

def get_productivity_report(
    db: Session,
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
    filters: Optional[ReportFilterParams] = None,
) -> ProductivityReportResponse:
    """Compute productivity and completion rate metrics with zero-filled daily buckets."""
    if get_persistence_gateway().is_mongodb:
        return MongoReportService().get_productivity_report(
            date_from=date_from,
            date_to=date_to,
            filters=filters,
        )

    now = datetime.now(timezone.utc)
    if date_to is None:
        date_to = now.replace(hour=23, minute=59, second=59, microsecond=999999)
    if date_from is None:
        date_from = (date_to - timedelta(days=29)).replace(hour=0, minute=0, second=0, microsecond=0)

    # Validate date range
    if date_from > date_to:
        date_from, date_to = date_to, date_from

    # Query daily created counts
    created_stmt = (
        select(
            func.date_trunc("day", Task.created_at).label("day"),
            func.count(Task.id).label("cnt"),
        )
        .where(
            Task.created_at >= date_from,
            Task.created_at <= date_to,
        )
    )
    if filters and filters.client_id:
        created_stmt = created_stmt.where(Task.client_id == filters.client_id)
    if filters and filters.workflow_id:
        created_stmt = created_stmt.where(Task.workflow_id == filters.workflow_id)
    if filters and filters.assigned_user_id:
        created_stmt = created_stmt.where(Task.assigned_user_id == filters.assigned_user_id)
    if filters and filters.unassigned:
        created_stmt = created_stmt.where(Task.assigned_user_id.is_(None))

    created_stmt = created_stmt.group_by("day").order_by("day")
    created_map: Dict[str, int] = {}
    for row in db.execute(created_stmt):
        if row.day:
            day_str = row.day.strftime("%Y-%m-%d")
            created_map[day_str] = row.cnt

    # Query daily completed counts
    completed_stmt = (
        select(
            func.date_trunc("day", Task.completed_at).label("day"),
            func.count(Task.id).label("cnt"),
        )
        .where(
            Task.completed_at.is_not(None),
            Task.completed_at >= date_from,
            Task.completed_at <= date_to,
        )
    )
    if filters and filters.client_id:
        completed_stmt = completed_stmt.where(Task.client_id == filters.client_id)
    if filters and filters.workflow_id:
        completed_stmt = completed_stmt.where(Task.workflow_id == filters.workflow_id)
    if filters and filters.assigned_user_id:
        completed_stmt = completed_stmt.where(Task.assigned_user_id == filters.assigned_user_id)
    if filters and filters.unassigned:
        completed_stmt = completed_stmt.where(Task.assigned_user_id.is_(None))

    completed_stmt = completed_stmt.group_by("day").order_by("day")
    completed_map: Dict[str, int] = {}
    for row in db.execute(completed_stmt):
        if row.day:
            day_str = row.day.strftime("%Y-%m-%d")
            completed_map[day_str] = row.cnt

    # Query daily overdue counts (tasks whose due_date fell on that day and were not completed on time)
    overdue_stmt = (
        select(
            func.date_trunc("day", Task.due_date).label("day"),
            func.count(Task.id).label("cnt"),
        )
        .where(
            Task.due_date.is_not(None),
            Task.due_date >= date_from,
            Task.due_date <= date_to,
            or_(
                Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                Task.completed_at > Task.due_date,
            ),
        )
    )
    if filters and filters.client_id:
        overdue_stmt = overdue_stmt.where(Task.client_id == filters.client_id)
    if filters and filters.workflow_id:
        overdue_stmt = overdue_stmt.where(Task.workflow_id == filters.workflow_id)
    if filters and filters.assigned_user_id:
        overdue_stmt = overdue_stmt.where(Task.assigned_user_id == filters.assigned_user_id)
    if filters and filters.unassigned:
        overdue_stmt = overdue_stmt.where(Task.assigned_user_id.is_(None))

    overdue_stmt = overdue_stmt.group_by("day").order_by("day")
    overdue_map: Dict[str, int] = {}
    for row in db.execute(overdue_stmt):
        if row.day:
            day_str = row.day.strftime("%Y-%m-%d")
            overdue_map[day_str] = row.cnt

    # Zero-fill daily time points from date_from to date_to
    cur = date_from.date()
    end_date = date_to.date()
    daily_trends: List[ProductivityDailyTrendPoint] = []
    total_created = 0
    total_completed = 0
    total_overdue = 0

    while cur <= end_date:
        d_str = cur.strftime("%Y-%m-%d")
        c_cnt = created_map.get(d_str, 0)
        cmp_cnt = completed_map.get(d_str, 0)
        ovd_cnt = overdue_map.get(d_str, 0)

        total_created += c_cnt
        total_completed += cmp_cnt
        total_overdue += ovd_cnt

        rate = round((cmp_cnt / c_cnt * 100.0), 1) if c_cnt > 0 else (100.0 if cmp_cnt > 0 else 0.0)

        daily_trends.append(
            ProductivityDailyTrendPoint(
                date=d_str,
                created_count=c_cnt,
                completed_count=cmp_cnt,
                overdue_count=ovd_cnt,
                completion_rate=rate,
            )
        )
        cur += timedelta(days=1)

    overall_rate = round((total_completed / total_created * 100.0), 1) if total_created > 0 else (100.0 if total_completed > 0 else 0.0)

    return ProductivityReportResponse(
        date_from=date_from,
        date_to=date_to,
        total_created=total_created,
        total_completed=total_completed,
        total_overdue=total_overdue,
        overall_completion_rate=overall_rate,
        daily_trends=daily_trends,
    )


# =============================================================================
# 4. Workload Report
# =============================================================================

def get_workload_report(db: Session, filters: Optional[ReportFilterParams] = None) -> WorkloadReportResponse:
    """Compute multi-dimensional operational workload breakdown across Assignees, Clients, and Workflows."""
    if get_persistence_gateway().is_mongodb:
        return MongoReportService().get_workload_report(filters=filters)

    now = datetime.now(timezone.utc)
    today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
    today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)

    # 1. By Assignee
    assignee_stmt = select(
        Task.assigned_user_id,
        func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
        func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed_tasks"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.due_date < now,
                    ),
                    1,
                )
            )
        ).label("overdue_tasks"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.due_date >= today_start,
                        Task.due_date <= today_end,
                    ),
                    1,
                )
            )
        ).label("due_today_tasks"),
        func.count(Task.id).label("total_tasks"),
    ).group_by(Task.assigned_user_id)

    assignee_rows = db.execute(assignee_stmt).all()

    # Pre-fetch users for name mapping
    all_users = {u.id: u for u in db.scalars(select(User)).all()}

    by_assignee: List[WorkloadReportItem] = []
    for row in assignee_rows:
        user_id = row.assigned_user_id
        user = all_users.get(user_id) if user_id else None
        name = user.name if user else ("Unassigned" if user_id is None else "Former user")
        email = user.email if user else None

        by_assignee.append(
            WorkloadReportItem(
                id=user_id,
                name=name,
                email=email,
                open_tasks=row.open_tasks or 0,
                completed_tasks=row.completed_tasks or 0,
                overdue_tasks=row.overdue_tasks or 0,
                due_today_tasks=row.due_today_tasks or 0,
                total_tasks=row.total_tasks or 0,
            )
        )

    # Sort assignee: highest open tasks first, then unassigned last
    by_assignee.sort(key=lambda x: (x.id is None, -(x.open_tasks or 0), x.name))

    # 2. By Client
    client_stmt = (
        select(
            Client.id,
            Client.name,
            func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
            func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed_tasks"),
            func.count(
                case(
                    (
                        and_(
                            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                            Task.due_date < now,
                        ),
                        1,
                    )
                )
            ).label("overdue_tasks"),
            func.count(
                case(
                    (
                        and_(
                            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                            Task.due_date >= today_start,
                            Task.due_date <= today_end,
                        ),
                        1,
                    )
                )
            ).label("due_today_tasks"),
            func.count(Task.id).label("total_tasks"),
        )
        .join(Task, Client.id == Task.client_id)
        .group_by(Client.id, Client.name)
        .order_by(func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).desc())
    )

    client_rows = db.execute(client_stmt).all()
    by_client: List[WorkloadReportItem] = [
        WorkloadReportItem(
            id=row.id,
            name=row.name,
            open_tasks=row.open_tasks or 0,
            completed_tasks=row.completed_tasks or 0,
            overdue_tasks=row.overdue_tasks or 0,
            due_today_tasks=row.due_today_tasks or 0,
            total_tasks=row.total_tasks or 0,
        )
        for row in client_rows
    ]

    # 3. By Workflow
    workflow_stmt = (
        select(
            Workflow.id,
            Workflow.name,
            func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
            func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed_tasks"),
            func.count(
                case(
                    (
                        and_(
                            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                            Task.due_date < now,
                        ),
                        1,
                    )
                )
            ).label("overdue_tasks"),
            func.count(
                case(
                    (
                        and_(
                            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                            Task.due_date >= today_start,
                            Task.due_date <= today_end,
                        ),
                        1,
                    )
                )
            ).label("due_today_tasks"),
            func.count(Task.id).label("total_tasks"),
        )
        .join(Task, Workflow.id == Task.workflow_id)
        .group_by(Workflow.id, Workflow.name)
        .order_by(func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).desc())
    )

    workflow_rows = db.execute(workflow_stmt).all()
    by_workflow: List[WorkloadReportItem] = [
        WorkloadReportItem(
            id=row.id,
            name=row.name,
            open_tasks=row.open_tasks or 0,
            completed_tasks=row.completed_tasks or 0,
            overdue_tasks=row.overdue_tasks or 0,
            due_today_tasks=row.due_today_tasks or 0,
            total_tasks=row.total_tasks or 0,
        )
        for row in workflow_rows
    ]

    # Global totals
    total_open = sum(item.open_tasks for item in by_assignee)
    total_completed = sum(item.completed_tasks for item in by_assignee)
    total_overdue = sum(item.overdue_tasks for item in by_assignee)
    total_all = sum(item.total_tasks for item in by_assignee)

    return WorkloadReportResponse(
        by_assignee=by_assignee,
        by_client=by_client,
        by_workflow=by_workflow,
        total_open_tasks=total_open,
        total_completed_tasks=total_completed,
        total_overdue_tasks=total_overdue,
        total_tasks=total_all,
    )


# =============================================================================
# 5. Activity / Audit Report
# =============================================================================

def get_activity_report(
    db: Session,
    action: Optional[str] = None,
    actor_id: Optional[Union[uuid.UUID, str]] = None,
    task_id: Optional[Union[uuid.UUID, str]] = None,
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
    search: Optional[str] = None,
    page: int = 1,
    page_size: int = 20,
) -> ActivityReportResponse:
    """Retrieve audit history logs with action distributions and pagination."""
    if get_persistence_gateway().is_mongodb:
        return MongoReportService().get_activity_report(
            action=action,
            actor_id=actor_id,
            task_id=task_id,
            date_from=date_from,
            date_to=date_to,
            search=search,
            page=page,
            page_size=page_size,
        )

    query = (
        select(TaskHistory)
        .options(
            joinedload(TaskHistory.created_by_user),
            joinedload(TaskHistory.task),
        )
    )
    count_query = select(func.count(TaskHistory.id))

    if action and action.strip():
        act = action.strip().lower()
        query = query.where(TaskHistory.action == act)
        count_query = count_query.where(TaskHistory.action == act)

    if actor_id:
        query = query.where(TaskHistory.created_by_user_id == actor_id)
        count_query = count_query.where(TaskHistory.created_by_user_id == actor_id)

    if task_id:
        query = query.where(TaskHistory.task_id == task_id)
        count_query = count_query.where(TaskHistory.task_id == task_id)

    if date_from:
        query = query.where(TaskHistory.created_at >= date_from)
        count_query = count_query.where(TaskHistory.created_at >= date_from)

    if date_to:
        query = query.where(TaskHistory.created_at <= date_to)
        count_query = count_query.where(TaskHistory.created_at <= date_to)

    if search and search.strip():
        term = f"%{search.strip()}%"
        query = query.outerjoin(Task, TaskHistory.task_id == Task.id).outerjoin(User, TaskHistory.created_by_user_id == User.id)
        count_query = count_query.outerjoin(Task, TaskHistory.task_id == Task.id).outerjoin(User, TaskHistory.created_by_user_id == User.id)

        search_cond = or_(
            TaskHistory.action.ilike(term),
            TaskHistory.reason.ilike(term),
            TaskHistory.old_value.ilike(term),
            TaskHistory.new_value.ilike(term),
            Task.title.ilike(term),
            User.name.ilike(term),
            User.email.ilike(term),
        )
        query = query.where(search_cond)
        count_query = count_query.where(search_cond)

    total = db.scalar(count_query) or 0

    # Action counts query
    action_counts_stmt = select(TaskHistory.action, func.count(TaskHistory.id)).group_by(TaskHistory.action)
    action_counts = {row[0]: row[1] for row in db.execute(action_counts_stmt)}

    offset = max(0, (page - 1) * page_size)
    query = query.order_by(TaskHistory.created_at.desc(), TaskHistory.id.desc()).offset(offset).limit(page_size)

    rows = list(db.scalars(query).unique().all())

    items: List[ActivityReportItem] = []
    for r in rows:
        actor_name = r.created_by_user.name if r.created_by_user else ("Former user" if r.created_by_user_id else "System")
        actor_email = r.created_by_user.email if r.created_by_user else None
        task_title = r.task.title if r.task else None

        items.append(
            ActivityReportItem(
                id=r.id,
                task_id=r.task_id,
                task_title=task_title,
                action=r.action,
                actor_id=r.created_by_user_id,
                actor_name=actor_name,
                actor_email=actor_email,
                old_value=r.old_value,
                new_value=r.new_value,
                reason=r.reason,
                created_at=r.created_at,
            )
        )

    return ActivityReportResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        action_counts=action_counts,
    )


# =============================================================================
# 6. Reminders & Follow-ups Report
# =============================================================================

def get_reminders_followups_report(
    db: Session,
    filters: Optional[ReportFilterParams] = None,
) -> ReminderFollowUpReportResponse:
    """Compute scheduling queues report with task linkages and KPI aggregates."""
    if get_persistence_gateway().is_mongodb:
        return MongoReportService().get_reminders_followups_report(filters=filters)

    now = datetime.now(timezone.utc)
    today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
    today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)

    # 1. Reminders Aggregations
    reminders_stmt = select(
        func.count(case((and_(Reminder.is_sent.is_(False), Reminder.remind_at <= now), 1))).label("reminders_due"),
        func.count(case((Reminder.is_sent.is_(True), 1))).label("reminders_sent"),
        func.count(case((and_(Reminder.is_sent.is_(False), Reminder.remind_at > now), 1))).label("reminders_pending"),
        func.count(Reminder.id).label("reminders_total"),
    )
    if filters and (filters.client_id or filters.workflow_id or filters.assigned_user_id):
        reminders_stmt = reminders_stmt.join(Task, Reminder.task_id == Task.id)
        if filters.client_id:
            reminders_stmt = reminders_stmt.where(Task.client_id == filters.client_id)
        if filters.workflow_id:
            reminders_stmt = reminders_stmt.where(Task.workflow_id == filters.workflow_id)
        if filters.assigned_user_id:
            reminders_stmt = reminders_stmt.where(Task.assigned_user_id == filters.assigned_user_id)

    rem_summary_row = db.execute(reminders_stmt).one()

    # 2. Follow-ups Aggregations
    follow_ups_stmt = select(
        func.count(case((and_(FollowUp.completed_at.is_(None), FollowUp.scheduled_at < today_start), 1))).label("follow_ups_overdue"),
        func.count(
            case(
                (
                    and_(
                        FollowUp.completed_at.is_(None),
                        FollowUp.scheduled_at >= today_start,
                        FollowUp.scheduled_at <= today_end,
                    ),
                    1,
                )
            )
        ).label("follow_ups_today"),
        func.count(case((and_(FollowUp.completed_at.is_(None), FollowUp.scheduled_at > today_end), 1))).label("follow_ups_upcoming"),
        func.count(case((FollowUp.completed_at.is_not(None), 1))).label("follow_ups_completed"),
        func.count(case((FollowUp.completed_at.is_(None), 1))).label("follow_ups_pending"),
        func.count(FollowUp.id).label("follow_ups_total"),
    )
    if filters and (filters.client_id or filters.workflow_id or filters.assigned_user_id):
        follow_ups_stmt = follow_ups_stmt.join(Task, FollowUp.task_id == Task.id)
        if filters.client_id:
            follow_ups_stmt = follow_ups_stmt.where(Task.client_id == filters.client_id)
        if filters.workflow_id:
            follow_ups_stmt = follow_ups_stmt.where(Task.workflow_id == filters.workflow_id)
        if filters.assigned_user_id:
            follow_ups_stmt = follow_ups_stmt.where(Task.assigned_user_id == filters.assigned_user_id)

    fu_summary_row = db.execute(follow_ups_stmt).one()

    summary = ReminderFollowUpSummary(
        reminders_due=rem_summary_row.reminders_due or 0,
        reminders_sent=rem_summary_row.reminders_sent or 0,
        reminders_pending=rem_summary_row.reminders_pending or 0,
        reminders_total=rem_summary_row.reminders_total or 0,
        follow_ups_overdue=fu_summary_row.follow_ups_overdue or 0,
        follow_ups_today=fu_summary_row.follow_ups_today or 0,
        follow_ups_upcoming=fu_summary_row.follow_ups_upcoming or 0,
        follow_ups_completed=fu_summary_row.follow_ups_completed or 0,
        follow_ups_pending=fu_summary_row.follow_ups_pending or 0,
        follow_ups_total=fu_summary_row.follow_ups_total or 0,
    )

    # 3. Reminders list
    rem_list_stmt = (
        select(Reminder)
        .options(joinedload(Reminder.task))
    )
    if filters and (filters.client_id or filters.workflow_id or filters.assigned_user_id):
        rem_list_stmt = rem_list_stmt.join(Task, Reminder.task_id == Task.id)
        if filters.client_id:
            rem_list_stmt = rem_list_stmt.where(Task.client_id == filters.client_id)
        if filters.workflow_id:
            rem_list_stmt = rem_list_stmt.where(Task.workflow_id == filters.workflow_id)
        if filters.assigned_user_id:
            rem_list_stmt = rem_list_stmt.where(Task.assigned_user_id == filters.assigned_user_id)

    rem_list_stmt = rem_list_stmt.order_by(Reminder.created_at.desc(), Reminder.remind_at.asc()).limit(100)
    rem_items = [
        ReminderReportItem(
            id=r.id,
            task_id=r.task_id,
            task_title=r.task.title if r.task else "Deleted Task",
            remind_at=r.remind_at,
            is_sent=r.is_sent,
            message=r.message,
            created_at=r.created_at,
        )
        for r in db.scalars(rem_list_stmt).unique().all()
    ]

    # 4. Follow-ups list
    fu_list_stmt = (
        select(FollowUp)
        .options(joinedload(FollowUp.task))
    )
    if filters and (filters.client_id or filters.workflow_id or filters.assigned_user_id):
        fu_list_stmt = fu_list_stmt.join(Task, FollowUp.task_id == Task.id)
        if filters.client_id:
            fu_list_stmt = fu_list_stmt.where(Task.client_id == filters.client_id)
        if filters.workflow_id:
            fu_list_stmt = fu_list_stmt.where(Task.workflow_id == filters.workflow_id)
        if filters.assigned_user_id:
            fu_list_stmt = fu_list_stmt.where(Task.assigned_user_id == filters.assigned_user_id)

    fu_list_stmt = fu_list_stmt.order_by(FollowUp.created_at.desc(), FollowUp.scheduled_at.asc()).limit(100)
    fu_items = [
        FollowUpReportItem(
            id=f.id,
            task_id=f.task_id,
            task_title=f.task.title if f.task else "Deleted Task",
            scheduled_at=f.scheduled_at,
            completed_at=f.completed_at,
            notes=f.notes,
            is_completed=f.completed_at is not None,
            created_at=f.created_at,
        )
        for f in db.scalars(fu_list_stmt).unique().all()
    ]

    return ReminderFollowUpReportResponse(
        summary=summary,
        reminders=rem_items,
        follow_ups=fu_items,
    )


# =============================================================================
# 7. CSV & JSON Export Generators
# =============================================================================

def export_to_csv(report_type: str, data: Any) -> str:
    """Generate UTF-8 RFC-4180 compliant CSV content for report datasets."""
    output = io.StringIO()
    writer = csv.writer(output, quoting=csv.QUOTE_MINIMAL)

    if report_type in ("tasks", "task_detail"):
        # Header
        writer.writerow([
            "Task ID",
            "Title",
            "Subject Line",
            "Status",
            "Priority",
            "Client Name",
            "Workflow Name",
            "Assignee Name",
            "Assignee Email",
            "Due Date",
            "Next Action Date",
            "Attempts",
            "Max Attempts",
            "Source",
            "Created At",
            "Updated At",
            "Completed At",
            "Description",
        ])
        items = data.items if hasattr(data, "items") else data
        for item in items:
            writer.writerow([
                str(item.id),
                item.title,
                item.subject_line or "",
                item.status.value if hasattr(item.status, "value") else str(item.status),
                item.priority.value if hasattr(item.priority, "value") else str(item.priority),
                item.client_name or "",
                item.workflow_name or "",
                item.assigned_user_name or "",
                item.assigned_user_email or "",
                item.due_date.isoformat() if item.due_date else "",
                item.next_action_date.isoformat() if item.next_action_date else "",
                item.attempt_count,
                item.max_attempts,
                item.source,
                item.created_at.isoformat() if item.created_at else "",
                item.updated_at.isoformat() if item.updated_at else "",
                item.completed_at.isoformat() if item.completed_at else "",
                item.description or "",
            ])

    elif report_type == "task_summary":
        summary: TaskSummaryReport = data
        writer.writerow(["Metric", "Count"])
        writer.writerow(["Total Tasks", summary.total_tasks])
        writer.writerow(["Open Tasks", summary.open_tasks])
        writer.writerow(["Completed Tasks", summary.completed_tasks])
        writer.writerow(["Cancelled Tasks", summary.cancelled_tasks])
        writer.writerow(["Overdue Tasks", summary.overdue_tasks])
        writer.writerow(["Due Today Tasks", summary.due_today_tasks])
        writer.writerow(["Upcoming Tasks", summary.upcoming_tasks])
        writer.writerow(["Near Max Attempts", summary.near_max_attempts])
        writer.writerow(["Max Attempts Reached", summary.max_attempts_reached])
        writer.writerow(["Status: Pending", summary.status_breakdown.pending])
        writer.writerow(["Status: In Progress", summary.status_breakdown.in_progress])
        writer.writerow(["Status: Completed", summary.status_breakdown.completed])
        writer.writerow(["Status: Cancelled", summary.status_breakdown.cancelled])
        writer.writerow(["Priority: Urgent", summary.priority_breakdown.urgent])
        writer.writerow(["Priority: High", summary.priority_breakdown.high])
        writer.writerow(["Priority: Medium", summary.priority_breakdown.medium])
        writer.writerow(["Priority: Low", summary.priority_breakdown.low])

    elif report_type == "productivity":
        prod: ProductivityReportResponse = data
        writer.writerow(["Productivity Summary"])
        writer.writerow(["Date From", prod.date_from.isoformat()])
        writer.writerow(["Date To", prod.date_to.isoformat()])
        writer.writerow(["Total Created", prod.total_created])
        writer.writerow(["Total Completed", prod.total_completed])
        writer.writerow(["Total Overdue", prod.total_overdue])
        writer.writerow(["Overall Completion Rate (%)", prod.overall_completion_rate])
        writer.writerow([])
        writer.writerow(["Date", "Created Tasks", "Completed Tasks", "Overdue Tasks", "Completion Rate (%)"])
        for point in prod.daily_trends:
            writer.writerow([
                point.date,
                point.created_count,
                point.completed_count,
                point.overdue_count,
                point.completion_rate,
            ])

    elif report_type == "workload":
        wl: WorkloadReportResponse = data
        writer.writerow(["=== WORKLOAD BY ASSIGNEE ==="])
        writer.writerow(["Assignee Name", "Email", "Open Tasks", "Completed Tasks", "Overdue Tasks", "Due Today Tasks", "Total Tasks"])
        for a in wl.by_assignee:
            writer.writerow([a.name, a.email or "", a.open_tasks, a.completed_tasks, a.overdue_tasks, a.due_today_tasks, a.total_tasks])
        writer.writerow([])
        writer.writerow(["=== WORKLOAD BY CLIENT ==="])
        writer.writerow(["Client Name", "Open Tasks", "Completed Tasks", "Overdue Tasks", "Due Today Tasks", "Total Tasks"])
        for c in wl.by_client:
            writer.writerow([c.name, c.open_tasks, c.completed_tasks, c.overdue_tasks, c.due_today_tasks, c.total_tasks])
        writer.writerow([])
        writer.writerow(["=== WORKLOAD BY WORKFLOW ==="])
        writer.writerow(["Workflow Name", "Open Tasks", "Completed Tasks", "Overdue Tasks", "Due Today Tasks", "Total Tasks"])
        for w in wl.by_workflow:
            writer.writerow([w.name, w.open_tasks, w.completed_tasks, w.overdue_tasks, w.due_today_tasks, w.total_tasks])

    elif report_type == "activity":
        writer.writerow([
            "Activity ID",
            "Timestamp",
            "Action",
            "Actor Name",
            "Actor Email",
            "Task Title",
            "Task ID",
            "Old Value",
            "New Value",
            "Reason",
        ])
        items = data.items if hasattr(data, "items") else data
        for act in items:
            writer.writerow([
                str(act.id),
                act.created_at.isoformat() if act.created_at else "",
                act.action,
                act.actor_name or "",
                act.actor_email or "",
                act.task_title or "",
                str(act.task_id) if act.task_id else "",
                act.old_value or "",
                act.new_value or "",
                act.reason or "",
            ])

    elif report_type == "reminders_followups":
        rf: ReminderFollowUpReportResponse = data
        writer.writerow(["=== SCHEDULING QUEUES SUMMARY ==="])
        writer.writerow(["Reminders Due", rf.summary.reminders_due])
        writer.writerow(["Reminders Sent", rf.summary.reminders_sent])
        writer.writerow(["Reminders Pending", rf.summary.reminders_pending])
        writer.writerow(["Reminders Total", rf.summary.reminders_total])
        writer.writerow(["Follow-ups Overdue", rf.summary.follow_ups_overdue])
        writer.writerow(["Follow-ups Due Today", rf.summary.follow_ups_today])
        writer.writerow(["Follow-ups Upcoming", rf.summary.follow_ups_upcoming])
        writer.writerow(["Follow-ups Completed", rf.summary.follow_ups_completed])
        writer.writerow(["Follow-ups Total", rf.summary.follow_ups_total])
        writer.writerow([])
        writer.writerow(["=== REMINDERS ==="])
        writer.writerow(["Reminder ID", "Task Title", "Remind At", "Is Sent", "Message", "Created At"])
        for r in rf.reminders:
            writer.writerow([str(r.id), r.task_title, r.remind_at.isoformat(), r.is_sent, r.message, r.created_at.isoformat()])
        writer.writerow([])
        writer.writerow(["=== FOLLOW-UPS ==="])
        writer.writerow(["Follow-up ID", "Task Title", "Scheduled At", "Is Completed", "Completed At", "Notes", "Created At"])
        for f in rf.follow_ups:
            writer.writerow([
                str(f.id),
                f.task_title,
                f.scheduled_at.isoformat(),
                f.is_completed,
                f.completed_at.isoformat() if f.completed_at else "",
                f.notes or "",
                f.created_at.isoformat(),
            ])

    return output.getvalue()


def export_to_json(report_type: str, data: Any) -> str:
    """Generate clean, indented JSON string for report datasets."""
    if hasattr(data, "model_dump"):
        raw_dict = data.model_dump(mode="json")
    elif hasattr(data, "dict"):
        raw_dict = data.dict()
    else:
        raw_dict = data

    return json.dumps({"report_type": report_type, "generated_at": datetime.now(timezone.utc).isoformat(), "data": raw_dict}, indent=2)
