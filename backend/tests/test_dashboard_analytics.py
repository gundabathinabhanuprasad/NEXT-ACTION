"""Tests for Phase 16: Advanced Dashboard, Productivity Analytics & Workload Insights."""

from datetime import datetime, timedelta, timezone
import uuid
from fastapi.testclient import TestClient
import pytest
from app.core.security import create_access_token
from app.main import app
from app.models.client import Client
from app.models.enums import TaskPriority, TaskStatus
from app.models.follow_up import FollowUp
from app.models.notification import Notification
from app.models.reminder import Reminder
from app.models.task import Task
from app.models.user import User
from app.models.workflow import Workflow

client = TestClient(app)


@pytest.fixture
def test_dashboard_environment(db):
    """Seed comprehensive test operational data for dashboard analytics verification."""
    # 1. Users
    user_a = User(
        name="Dashboard Analyst A",
        email=f"analyst_a_{uuid.uuid4().hex[:6]}@example.com",
        password_hash="hashed_pw",
        is_active=True,
    )
    user_b = User(
        name="Dashboard Analyst B",
        email=f"analyst_b_{uuid.uuid4().hex[:6]}@example.com",
        password_hash="hashed_pw",
        is_active=True,
    )
    db.add_all([user_a, user_b])
    db.flush()

    # 2. Clients & Workflows
    c1 = Client(name=f"Enterprise Alpha {uuid.uuid4().hex[:6]}")
    c2 = Client(name=f"Beta Holdings {uuid.uuid4().hex[:6]}")
    w1 = Workflow(name=f"Audit Workflow {uuid.uuid4().hex[:6]}")
    w2 = Workflow(name=f"Onboarding Workflow {uuid.uuid4().hex[:6]}")
    db.add_all([c1, c2, w1, w2])
    db.flush()

    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    # 3. Tasks with varying statuses, priorities, due dates, and attempts
    t1_overdue = Task(
        title="Overdue Urgent Task",
        status=TaskStatus.PENDING,
        priority=TaskPriority.URGENT,
        due_date=today_start - timedelta(days=2),
        client_id=c1.id,
        workflow_id=w1.id,
        assigned_user_id=user_a.id,
        attempt_count=1,
        max_attempts=2,  # near max
    )
    t2_due_today = Task(
        title="Due Today High Task",
        status=TaskStatus.IN_PROGRESS,
        priority=TaskPriority.HIGH,
        due_date=today_start + timedelta(hours=4),
        next_action_date=today_start + timedelta(hours=2),
        client_id=c1.id,
        workflow_id=w1.id,
        assigned_user_id=user_a.id,
        attempt_count=0,
        max_attempts=3,
    )
    t3_upcoming = Task(
        title="Upcoming Medium Task",
        status=TaskStatus.PENDING,
        priority=TaskPriority.MEDIUM,
        due_date=today_start + timedelta(days=5),
        client_id=c2.id,
        workflow_id=w2.id,
        assigned_user_id=user_b.id,
        attempt_count=2,
        max_attempts=2,  # max reached
    )
    t4_completed = Task(
        title="Recently Completed Task",
        status=TaskStatus.COMPLETED,
        priority=TaskPriority.LOW,
        due_date=today_start - timedelta(days=1),
        completed_at=now - timedelta(hours=1),
        client_id=c2.id,
        workflow_id=w2.id,
        assigned_user_id=user_b.id,
        attempt_count=1,
        max_attempts=3,
    )
    t5_unassigned = Task(
        title="Unassigned Open Task",
        status=TaskStatus.PENDING,
        priority=TaskPriority.LOW,
        due_date=today_start + timedelta(days=3),
        client_id=c1.id,
        workflow_id=w1.id,
        assigned_user_id=None,
        attempt_count=0,
        max_attempts=2,
    )
    db.add_all([t1_overdue, t2_due_today, t3_upcoming, t4_completed, t5_unassigned])
    db.flush()

    # 4. Follow-ups
    fu_pending_overdue = FollowUp(
        task_id=t1_overdue.id,
        scheduled_at=today_start - timedelta(days=1),
        completed_at=None,
    )
    fu_pending_today = FollowUp(
        task_id=t2_due_today.id,
        scheduled_at=today_start + timedelta(hours=5),
        completed_at=None,
    )
    fu_completed = FollowUp(
        task_id=t4_completed.id,
        scheduled_at=today_start - timedelta(days=3),
        completed_at=now - timedelta(hours=2),
    )
    db.add_all([fu_pending_overdue, fu_pending_today, fu_completed])

    # 5. Reminders
    rem_due_now = Reminder(
        task_id=t1_overdue.id,
        remind_at=now - timedelta(minutes=15),
        message="Urgent overdue reminder",
        is_sent=False,
    )
    rem_upcoming = Reminder(
        task_id=t3_upcoming.id,
        remind_at=now + timedelta(days=2),
        message="Upcoming reminder",
        is_sent=False,
    )
    db.add_all([rem_due_now, rem_upcoming])

    # 6. Notifications
    notif_unread = Notification(
        user_id=user_a.id,
        title="Alert for User A",
        message="Important alert",
        type="task_assigned",
        is_read=False,
    )
    notif_read = Notification(
        user_id=user_a.id,
        title="Read alert",
        message="Read message",
        type="task_completed",
        is_read=True,
    )
    notif_user_b = Notification(
        user_id=user_b.id,
        title="Alert for User B",
        message="User B message",
        type="task_assigned",
        is_read=False,
    )
    db.add_all([notif_unread, notif_read, notif_user_b])
    db.commit()

    return {
        "user_a": user_a,
        "user_b": user_b,
        "client_1": c1,
        "client_2": c2,
        "workflow_1": w1,
        "workflow_2": w2,
        "task_overdue": t1_overdue,
        "task_due_today": t2_due_today,
        "task_upcoming": t3_upcoming,
        "task_completed": t4_completed,
        "task_unassigned": t5_unassigned,
    }


def test_unauthenticated_dashboard_summary_rejected():
    """Unauthenticated GET /api/v1/dashboard/summary must return 401."""
    resp = client.get("/api/v1/dashboard/summary")
    assert resp.status_code == 401


def test_dashboard_summary_kpis_and_distributions(test_dashboard_environment):
    """Verify aggregated Core KPIs, status distributions, priority distributions, and attempt pressure."""
    env = test_dashboard_environment
    user_a = env["user_a"]
    token, _ = create_access_token(user_a.id)
    headers = {"Authorization": f"Bearer {token}"}

    resp = client.get("/api/v1/dashboard/summary?time_range=last_7_days", headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    # Time range metadata
    assert data["time_range"] == "last_7_days"
    assert "range_start" in data
    assert "range_end" in data

    # Core KPIs
    kpis = data["kpis"]
    assert kpis["total_open_tasks"] >= 4  # t1, t2, t3, t5
    assert kpis["due_today_tasks"] >= 1  # t2
    assert kpis["overdue_tasks"] >= 1  # t1
    assert kpis["upcoming_tasks"] >= 2  # t3, t5
    assert kpis["completed_tasks"] >= 1  # t4
    assert kpis["near_max_attempts"] >= 1  # t1
    assert kpis["max_attempts_reached"] >= 1  # t3
    assert kpis["pending_follow_ups"] >= 2
    assert kpis["overdue_follow_ups"] >= 1
    assert kpis["due_today_follow_ups"] >= 1
    assert kpis["due_reminders"] >= 1
    assert kpis["unread_notifications"] == 1  # user_a only has 1 unread notification

    # Status Distribution
    status_dist = data["status_distribution"]
    assert status_dist["pending"] >= 3
    assert status_dist["in_progress"] >= 1
    assert status_dist["completed"] >= 1

    # Priority Distribution
    priority_dist = data["priority_distribution"]
    assert priority_dist["urgent"] >= 1
    assert priority_dist["high"] >= 1
    assert priority_dist["medium"] >= 1
    assert priority_dist["low"] >= 1

    # Attempt Pressure
    attempt_press = data["attempt_pressure"]
    assert attempt_press["zero_attempts"] >= 2
    assert attempt_press["one_attempt"] >= 1
    assert attempt_press["near_max"] >= 1
    assert attempt_press["max_reached"] >= 1


def test_dashboard_workload_breakdowns(test_dashboard_environment):
    """Verify workload distributions grouped by assignee, client, and workflow."""
    env = test_dashboard_environment
    user_a = env["user_a"]
    user_b = env["user_b"]
    c1 = env["client_1"]
    w1 = env["workflow_1"]

    token, _ = create_access_token(user_a.id)
    headers = {"Authorization": f"Bearer {token}"}

    resp = client.get("/api/v1/dashboard/summary", headers=headers)
    assert resp.status_code == 200
    workload = resp.json()["workload"]

    # Assignee workload
    by_assignee = workload["by_assignee"]
    assert len(by_assignee) >= 2
    # Check user_a workload
    user_a_item = next(item for item in by_assignee if item.get("user_id") == str(user_a.id))
    assert user_a_item["user_name"] == user_a.name
    assert user_a_item["open_tasks"] >= 2
    assert user_a_item["overdue"] >= 1
    assert user_a_item["due_today"] >= 1

    # Check unassigned workload
    unassigned_item = next(item for item in by_assignee if item.get("user_id") is None)
    assert unassigned_item["user_name"] == "Unassigned"
    assert unassigned_item["open_tasks"] >= 1

    # Client workload
    by_client = workload["by_client"]
    assert len(by_client) >= 2
    c1_item = next(item for item in by_client if item["client_id"] == str(c1.id))
    assert c1_item["client_name"] == c1.name
    assert c1_item["open_tasks"] >= 3  # t1, t2, t5

    # Workflow workload
    by_workflow = workload["by_workflow"]
    assert len(by_workflow) >= 2
    w1_item = next(item for item in by_workflow if item["workflow_id"] == str(w1.id))
    assert w1_item["workflow_name"] == w1.name
    assert w1_item["open_tasks"] >= 3


def test_dashboard_scheduling_and_attention(test_dashboard_environment):
    """Verify follow-up and reminder scheduling analytics alongside attention aggregates."""
    env = test_dashboard_environment
    user_a = env["user_a"]
    token, _ = create_access_token(user_a.id)
    headers = {"Authorization": f"Bearer {token}"}

    resp = client.get("/api/v1/dashboard/summary", headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    # Attention summary
    attention = data["attention"]
    assert attention["urgent_count"] >= 3  # overdue + near max + due reminder + overdue follow-up
    assert attention["today_count"] >= 2  # due today task + next action today + due today follow-up

    # Scheduling analytics
    sched = data["scheduling"]
    assert sched["follow_ups"]["pending"] >= 2
    assert sched["follow_ups"]["overdue"] >= 1
    assert sched["follow_ups"]["due_today"] >= 1
    assert sched["follow_ups"]["completed"] >= 1

    assert sched["reminders"]["pending"] >= 2
    assert sched["reminders"]["due_today"] >= 1 or sched["reminders"]["overdue"] >= 1


def test_dashboard_time_ranges_and_trends(test_dashboard_environment):
    """Verify 7-day, 30-day, today, and this_month time ranges return gap-free trend sequences."""
    env = test_dashboard_environment
    user_a = env["user_a"]
    token, _ = create_access_token(user_a.id)
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Last 7 days
    resp_7 = client.get("/api/v1/dashboard/summary?time_range=last_7_days", headers=headers)
    assert resp_7.status_code == 200
    trends_7 = resp_7.json()["trends"]
    assert len(trends_7) == 7
    for pt in trends_7:
        assert "date" in pt
        assert pt["created_count"] >= 0
        assert pt["completed_count"] >= 0
        assert pt["overdue_count"] >= 0

    # 2. Last 30 days
    resp_30 = client.get("/api/v1/dashboard/summary?time_range=last_30_days", headers=headers)
    assert resp_30.status_code == 200
    trends_30 = resp_30.json()["trends"]
    assert len(trends_30) == 30

    # 3. Today
    resp_today = client.get("/api/v1/dashboard/summary?time_range=today", headers=headers)
    assert resp_today.status_code == 200
    trends_today = resp_today.json()["trends"]
    assert len(trends_today) == 1

    # 4. This Month
    resp_month = client.get("/api/v1/dashboard/summary?time_range=this_month", headers=headers)
    assert resp_month.status_code == 200
    assert len(resp_month.json()["trends"]) >= 1

    # 5. Invalid time range returns 422
    resp_invalid = client.get("/api/v1/dashboard/summary?time_range=invalid_range", headers=headers)
    assert resp_invalid.status_code == 422


def test_dashboard_user_isolation(test_dashboard_environment):
    """Verify user-specific data like unread notifications is scoped properly to authenticated user."""
    env = test_dashboard_environment
    user_a = env["user_a"]
    user_b = env["user_b"]

    token_a, _ = create_access_token(user_a.id)
    token_b, _ = create_access_token(user_b.id)

    resp_a = client.get("/api/v1/dashboard/summary", headers={"Authorization": f"Bearer {token_a}"})
    resp_b = client.get("/api/v1/dashboard/summary", headers={"Authorization": f"Bearer {token_b}"})

    assert resp_a.status_code == 200
    assert resp_b.status_code == 200

    # User A has 1 unread notification, User B has 1 unread notification with different title/id
    assert resp_a.json()["kpis"]["unread_notifications"] == 1
    assert resp_b.json()["kpis"]["unread_notifications"] == 1
    notifs_a = resp_a.json()["recent_notifications"]
    assert any(n["title"] == "Alert for User A" for n in notifs_a)
    assert not any(n["title"] == "Alert for User B" for n in notifs_a)
