"""Dashboard service providing high-performance PostgreSQL aggregated metrics, workload insights, and time-series trends."""

from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple
import uuid
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session
from app.models.client import Client
from app.models.enums import TaskPriority, TaskStatus
from app.models.follow_up import FollowUp
from app.models.notification import Notification
from app.models.reminder import Reminder
from app.models.task import Task
from app.models.user import User
from app.models.workflow import Workflow
from app.schemas.dashboard import (
    AssigneeWorkloadItem,
    ClientWorkloadItem,
    DashboardAttentionSummary,
    DashboardAttemptPressure,
    DashboardKpis,
    DashboardPriorityDistribution,
    DashboardSchedulingAnalytics,
    DashboardStatusDistribution,
    DashboardSummaryResponse,
    DashboardTrendPoint,
    DashboardWorkloadBreakdown,
    FollowUpAnalytics,
    ReminderAnalytics,
    WorkflowWorkloadItem,
)
from app.services.history_service import get_recent_activity, serialize_task_history
from app.services.notification_service import get_user_notifications


def get_time_range_bounds(time_range: str, now: Optional[datetime] = None) -> Tuple[datetime, datetime]:
    """Calculate exact UTC start and end bounds for the specified time range."""
    if now is None:
        now = datetime.now(timezone.utc)

    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = now.replace(hour=23, minute=59, second=59, microsecond=999999)

    range_lower = time_range.lower()
    if range_lower == "today":
        return today_start, today_end
    elif range_lower == "last_7_days":
        return today_start - timedelta(days=6), today_end
    elif range_lower == "last_30_days":
        return today_start - timedelta(days=29), today_end
    elif range_lower == "this_month":
        return today_start.replace(day=1), today_end
    else:
        # Default fallback to last 7 days
        return today_start - timedelta(days=6), today_end


def get_dashboard_summary(
    db: Session,
    user_id: uuid.UUID,
    time_range: str = "last_7_days",
) -> DashboardSummaryResponse:
    """Retrieve comprehensive operational dashboard analytics aggregated directly inside PostgreSQL."""
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = now.replace(hour=23, minute=59, second=59, microsecond=999999)
    range_start, range_end = get_time_range_bounds(time_range, now=now)

    # -------------------------------------------------------------------------
    # 1. Core Task Aggregations (Single SQL query with conditional counts)
    # -------------------------------------------------------------------------
    task_kpis_stmt = select(
        # Status distributions
        func.count(case((Task.status == TaskStatus.PENDING, 1))).label("pending_count"),
        func.count(case((Task.status == TaskStatus.IN_PROGRESS, 1))).label("in_progress_count"),
        func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed_count"),
        func.count(case((Task.status == TaskStatus.CANCELLED, 1))).label("cancelled_count"),
        # Open tasks (pending + in_progress)
        func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
        # Priority distribution on active tasks
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.priority == TaskPriority.URGENT,
                    ),
                    1,
                )
            )
        ).label("urgent_priority"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.priority == TaskPriority.HIGH,
                    ),
                    1,
                )
            )
        ).label("high_priority"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.priority == TaskPriority.MEDIUM,
                    ),
                    1,
                )
            )
        ).label("medium_priority"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.priority == TaskPriority.LOW,
                    ),
                    1,
                )
            )
        ).label("low_priority"),
        # Due date categories on active tasks
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
        ).label("due_today"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.due_date < today_start,
                    ),
                    1,
                )
            )
        ).label("overdue"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.due_date > today_end,
                    ),
                    1,
                )
            )
        ).label("upcoming"),
        # In-range completion and creation
        func.count(
            case(
                (
                    and_(
                        Task.status == TaskStatus.COMPLETED,
                        Task.completed_at >= range_start,
                        Task.completed_at <= range_end,
                    ),
                    1,
                )
            )
        ).label("completed_in_range"),
        func.count(
            case(
                (
                    and_(
                        Task.created_at >= range_start,
                        Task.created_at <= range_end,
                    ),
                    1,
                )
            )
        ).label("created_in_range"),
        # Attempt pressure on active tasks
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.attempt_count == 0,
                    ),
                    1,
                )
            )
        ).label("zero_attempts"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.attempt_count == 1,
                    ),
                    1,
                )
            )
        ).label("one_attempt"),
        func.count(
            case(
                (
                    and_(
                        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                        Task.max_attempts > 1,
                        Task.attempt_count == Task.max_attempts - 1,
                    ),
                    1,
                )
            )
        ).label("near_max"),
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
        ).label("max_reached"),
    )
    task_kpis = db.execute(task_kpis_stmt).one()

    # -------------------------------------------------------------------------
    # 2. Scheduling Aggregations (Follow-ups & Reminders)
    # -------------------------------------------------------------------------
    fu_stmt = select(
        func.count(case((FollowUp.completed_at.is_(None), 1))).label("pending"),
        func.count(
            case(
                (
                    and_(
                        FollowUp.completed_at.is_(None),
                        FollowUp.scheduled_at < today_start,
                    ),
                    1,
                )
            )
        ).label("overdue"),
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
        ).label("due_today"),
        func.count(
            case(
                (
                    and_(
                        FollowUp.completed_at.is_(None),
                        FollowUp.scheduled_at > today_end,
                    ),
                    1,
                )
            )
        ).label("upcoming"),
        func.count(case((FollowUp.completed_at.isnot(None), 1))).label("completed"),
    )
    fu_res = db.execute(fu_stmt).one()

    rem_stmt = select(
        func.count(case((Reminder.is_sent == False, 1))).label("pending"),
        func.count(
            case(
                (
                    and_(
                        Reminder.is_sent == False,
                        Reminder.remind_at >= today_start,
                        Reminder.remind_at <= today_end,
                    ),
                    1,
                )
            )
        ).label("due_today"),
        func.count(
            case(
                (
                    and_(
                        Reminder.is_sent == False,
                        Reminder.remind_at < today_start,
                    ),
                    1,
                )
            )
        ).label("overdue"),
        func.count(
            case(
                (
                    and_(
                        Reminder.is_sent == False,
                        Reminder.remind_at > today_end,
                    ),
                    1,
                )
            )
        ).label("upcoming"),
        func.count(
            case(
                (
                    and_(
                        Reminder.is_sent == False,
                        Reminder.remind_at <= now,
                    ),
                    1,
                )
            )
        ).label("due_now"),
    )
    rem_res = db.execute(rem_stmt).one()

    # Unread notifications count for authenticated user
    unread_notifs_stmt = select(func.count()).select_from(Notification).where(
        Notification.user_id == user_id,
        Notification.is_read == False,
    )
    unread_notifs_count = db.scalar(unread_notifs_stmt) or 0

    # Next actions due today
    next_actions_today_stmt = select(func.count()).select_from(Task).where(
        Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
        Task.next_action_date >= today_start,
        Task.next_action_date <= today_end,
    )
    next_actions_today_count = db.scalar(next_actions_today_stmt) or 0

    # -------------------------------------------------------------------------
    # 3. Workload Breakdowns (Assignees, Clients, Workflows)
    # -------------------------------------------------------------------------
    # By Assignee
    assignee_stmt = (
        select(
            User.id.label("user_id"),
            User.name.label("user_name"),
            func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
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
            ).label("due_today"),
            func.count(
                case(
                    (
                        and_(
                            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                            Task.due_date < today_start,
                        ),
                        1,
                    )
                )
            ).label("overdue"),
            func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed"),
        )
        .outerjoin(User, Task.assigned_user_id == User.id)
        .group_by(User.id, User.name)
    )
    assignee_rows = db.execute(assignee_stmt).all()
    by_assignee: List[AssigneeWorkloadItem] = []
    for row in assignee_rows:
        if row.open_tasks > 0 or row.completed > 0 or row.user_name is not None:
            by_assignee.append(
                AssigneeWorkloadItem(
                    user_id=row.user_id,
                    user_name=row.user_name if row.user_name else "Unassigned",
                    open_tasks=row.open_tasks,
                    due_today=row.due_today,
                    overdue=row.overdue,
                    completed=row.completed,
                )
            )

    # By Client
    client_stmt = (
        select(
            Client.id.label("client_id"),
            Client.name.label("client_name"),
            func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
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
            ).label("due_today"),
            func.count(
                case(
                    (
                        and_(
                            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                            Task.due_date < today_start,
                        ),
                        1,
                    )
                )
            ).label("overdue"),
            func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed"),
        )
        .join(Client, Task.client_id == Client.id)
        .group_by(Client.id, Client.name)
        .order_by(func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).desc())
    )
    client_rows = db.execute(client_stmt).all()
    by_client = [
        ClientWorkloadItem(
            client_id=row.client_id,
            client_name=row.client_name,
            open_tasks=row.open_tasks,
            due_today=row.due_today,
            overdue=row.overdue,
            completed=row.completed,
        )
        for row in client_rows
    ]

    # By Workflow
    workflow_stmt = (
        select(
            Workflow.id.label("workflow_id"),
            Workflow.name.label("workflow_name"),
            func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).label("open_tasks"),
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
            ).label("due_today"),
            func.count(
                case(
                    (
                        and_(
                            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
                            Task.due_date < today_start,
                        ),
                        1,
                    )
                )
            ).label("overdue"),
            func.count(case((Task.status == TaskStatus.COMPLETED, 1))).label("completed"),
        )
        .join(Workflow, Task.workflow_id == Workflow.id)
        .group_by(Workflow.id, Workflow.name)
        .order_by(func.count(case((Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]), 1))).desc())
    )
    workflow_rows = db.execute(workflow_stmt).all()
    by_workflow = [
        WorkflowWorkloadItem(
            workflow_id=row.workflow_id,
            workflow_name=row.workflow_name,
            open_tasks=row.open_tasks,
            due_today=row.due_today,
            overdue=row.overdue,
            completed=row.completed,
        )
        for row in workflow_rows
    ]

    # -------------------------------------------------------------------------
    # 4. Daily Time-Series Trend Aggregations (Created, Completed, Overdue)
    # -------------------------------------------------------------------------
    # Generate contiguous calendar dates for zero-filling gaps
    total_days = (today_end.date() - range_start.date()).days + 1
    date_list = [range_start.date() + timedelta(days=i) for i in range(total_days)]
    trend_map: Dict[str, Dict[str, int]] = {
        d.isoformat(): {"created": 0, "completed": 0, "overdue": 0} for d in date_list
    }

    # Query creation counts grouped by date
    created_trend_stmt = (
        select(
            func.date(Task.created_at).label("day"),
            func.count().label("cnt"),
        )
        .where(Task.created_at >= range_start, Task.created_at <= range_end)
        .group_by(func.date(Task.created_at))
    )
    for r in db.execute(created_trend_stmt).all():
        d_str = str(r.day)
        if d_str in trend_map:
            trend_map[d_str]["created"] = r.cnt

    # Query completion counts grouped by date
    completed_trend_stmt = (
        select(
            func.date(Task.completed_at).label("day"),
            func.count().label("cnt"),
        )
        .where(
            Task.status == TaskStatus.COMPLETED,
            Task.completed_at.isnot(None),
            Task.completed_at >= range_start,
            Task.completed_at <= range_end,
        )
        .group_by(func.date(Task.completed_at))
    )
    for r in db.execute(completed_trend_stmt).all():
        d_str = str(r.day)
        if d_str in trend_map:
            trend_map[d_str]["completed"] = r.cnt

    # Query overdue tasks due on each day
    overdue_trend_stmt = (
        select(
            func.date(Task.due_date).label("day"),
            func.count().label("cnt"),
        )
        .where(
            Task.status.in_([TaskStatus.PENDING, TaskStatus.IN_PROGRESS]),
            Task.due_date.isnot(None),
            Task.due_date >= range_start,
            Task.due_date < today_start,
        )
        .group_by(func.date(Task.due_date))
    )
    for r in db.execute(overdue_trend_stmt).all():
        d_str = str(r.day)
        if d_str in trend_map:
            trend_map[d_str]["overdue"] = r.cnt

    trends: List[DashboardTrendPoint] = [
        DashboardTrendPoint(
            date=d_str,
            created_count=metrics["created"],
            completed_count=metrics["completed"],
            overdue_count=metrics["overdue"],
        )
        for d_str, metrics in sorted(trend_map.items())
    ]

    # -------------------------------------------------------------------------
    # 5. Recent Activity & Notifications Integrations
    # -------------------------------------------------------------------------
    recent_activity_models = get_recent_activity(db=db, limit=10)
    recent_activities = [serialize_task_history(a) for a in recent_activity_models]

    recent_notif_models, _, _ = get_user_notifications(
        db=db,
        user_id=user_id,
        unread_only=False,
        page=1,
        page_size=5,
    )
    from app.schemas.notification import NotificationResponse

    recent_notifications = [NotificationResponse.model_validate(n) for n in recent_notif_models]

    # Attention calculations
    urgent_attention = task_kpis.overdue + task_kpis.near_max + rem_res.due_now + fu_res.overdue
    today_attention = task_kpis.due_today + next_actions_today_count + fu_res.due_today + rem_res.due_today

    return DashboardSummaryResponse(
        time_range=time_range,
        range_start=range_start,
        range_end=range_end,
        kpis=DashboardKpis(
            total_open_tasks=task_kpis.open_tasks,
            due_today_tasks=task_kpis.due_today,
            overdue_tasks=task_kpis.overdue,
            upcoming_tasks=task_kpis.upcoming,
            completed_tasks=task_kpis.completed_count,
            completed_in_range=task_kpis.completed_in_range,
            created_in_range=task_kpis.created_in_range,
            near_max_attempts=task_kpis.near_max,
            max_attempts_reached=task_kpis.max_reached,
            pending_follow_ups=fu_res.pending,
            overdue_follow_ups=fu_res.overdue,
            due_today_follow_ups=fu_res.due_today,
            due_reminders=rem_res.due_now,
            unread_notifications=unread_notifs_count,
        ),
        attention=DashboardAttentionSummary(
            urgent_count=urgent_attention,
            today_count=today_attention,
        ),
        status_distribution=DashboardStatusDistribution(
            pending=task_kpis.pending_count,
            in_progress=task_kpis.in_progress_count,
            completed=task_kpis.completed_count,
            cancelled=task_kpis.cancelled_count,
        ),
        priority_distribution=DashboardPriorityDistribution(
            urgent=task_kpis.urgent_priority,
            high=task_kpis.high_priority,
            medium=task_kpis.medium_priority,
            low=task_kpis.low_priority,
        ),
        attempt_pressure=DashboardAttemptPressure(
            zero_attempts=task_kpis.zero_attempts,
            one_attempt=task_kpis.one_attempt,
            near_max=task_kpis.near_max,
            max_reached=task_kpis.max_reached,
        ),
        workload=DashboardWorkloadBreakdown(
            by_assignee=by_assignee,
            by_client=by_client,
            by_workflow=by_workflow,
        ),
        scheduling=DashboardSchedulingAnalytics(
            follow_ups=FollowUpAnalytics(
                pending=fu_res.pending,
                overdue=fu_res.overdue,
                due_today=fu_res.due_today,
                upcoming=fu_res.upcoming,
                completed=fu_res.completed,
            ),
            reminders=ReminderAnalytics(
                pending=rem_res.pending,
                due_today=rem_res.due_today,
                overdue=rem_res.overdue,
                upcoming=rem_res.upcoming,
            ),
        ),
        trends=trends,
        recent_activities=recent_activities,
        recent_notifications=recent_notifications,
    )
