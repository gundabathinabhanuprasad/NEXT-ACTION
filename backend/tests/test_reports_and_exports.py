"""Tests for Phase 17: Reports, Exports & Management Insights."""

import csv
from datetime import datetime, timedelta, timezone
import io
import json
import uuid
from fastapi.testclient import TestClient
import pytest
from app.core.security import create_access_token
from app.main import app
from app.models.client import Client
from app.models.enums import TaskPriority, TaskStatus
from app.models.follow_up import FollowUp
from app.models.reminder import Reminder
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.user import User
from app.models.workflow import Workflow

client = TestClient(app)


@pytest.fixture
def test_reports_env(db):
    """Seed comprehensive operational domain data for report and export validation."""
    tag = uuid.uuid4().hex[:8]

    # 1. Users
    user_a = User(
        name=f"Report Admin A {tag}",
        email=f"report_admin_a_{tag}@example.com",
        password_hash="hashed_pw_123",
        is_active=True,
    )
    user_b = User(
        name=f"Report Operator B {tag}",
        email=f"report_op_b_{tag}@example.com",
        password_hash="hashed_pw_456",
        is_active=True,
    )
    db.add_all([user_a, user_b])
    db.flush()

    # 2. Clients & Workflows
    c1 = Client(name=f"Acme Corp {tag}")
    c2 = Client(name=f"Globex Ltd {tag}")
    w1 = Workflow(name=f"Customer Support {tag}")
    w2 = Workflow(name=f"Financial Audit {tag}")
    db.add_all([c1, c2, w1, w2])
    db.flush()

    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    # 3. Tasks
    # t1: Overdue Urgent under c1, w1, user_a
    t1 = Task(
        title=f"Urgent Server Migration, Phase 1 {tag}",
        description="Migrate cluster nodes with \"special quotes\" & unicode: 🚀",
        subject_line=f"[CRITICAL] Migration {tag}",
        status=TaskStatus.PENDING,
        priority=TaskPriority.URGENT,
        due_date=today_start - timedelta(days=3),
        client_id=c1.id,
        workflow_id=w1.id,
        assigned_user_id=user_a.id,
        attempt_count=1,
        max_attempts=2,  # near max
        created_at=today_start - timedelta(days=5),
    )
    # t2: Due today High under c1, w1, user_a
    t2 = Task(
        title=f"Client Contract Review {tag}",
        description="Verify billing clauses",
        subject_line=f"Contract Q3 {tag}",
        status=TaskStatus.IN_PROGRESS,
        priority=TaskPriority.HIGH,
        due_date=today_start + timedelta(hours=23),
        next_action_date=today_start + timedelta(hours=22),
        client_id=c1.id,
        workflow_id=w1.id,
        assigned_user_id=user_a.id,
        attempt_count=0,
        max_attempts=3,
        created_at=today_start - timedelta(days=2),
    )
    # t3: Upcoming Medium under c2, w2, user_b
    t3 = Task(
        title=f"Quarterly Tax Filing {tag}",
        description="Review deductions",
        status=TaskStatus.PENDING,
        priority=TaskPriority.MEDIUM,
        due_date=today_start + timedelta(days=7),
        client_id=c2.id,
        workflow_id=w2.id,
        assigned_user_id=user_b.id,
        attempt_count=3,
        max_attempts=3,  # max reached
        created_at=today_start - timedelta(days=1),
    )
    # t4: Completed Low under c2, w2, user_b
    t4 = Task(
        title=f"Weekly Team Standup Notes {tag}",
        description="Publish meeting notes",
        status=TaskStatus.COMPLETED,
        priority=TaskPriority.LOW,
        due_date=today_start - timedelta(days=1),
        completed_at=now - timedelta(hours=2),
        client_id=c2.id,
        workflow_id=w2.id,
        assigned_user_id=user_b.id,
        attempt_count=1,
        max_attempts=2,
        created_at=today_start - timedelta(days=3),
    )
    # t5: Unassigned Cancelled under c1
    t5 = Task(
        title=f"Deprecated Feature Audit {tag}",
        status=TaskStatus.CANCELLED,
        priority=TaskPriority.LOW,
        due_date=today_start + timedelta(days=10),
        client_id=c1.id,
        workflow_id=w1.id,
        assigned_user_id=None,
        attempt_count=0,
        max_attempts=2,
        created_at=today_start - timedelta(days=4),
    )
    db.add_all([t1, t2, t3, t4, t5])
    db.flush()

    # 4. Activity Logs
    h1 = TaskHistory(
        task_id=t1.id,
        action="created",
        new_value=json.dumps({"title": t1.title}),
        created_by_user_id=user_a.id,
        created_at=today_start - timedelta(days=5),
    )
    h2 = TaskHistory(
        task_id=t1.id,
        action="attempt",
        old_value="0",
        new_value="1",
        reason="First attempt failed due to network timeout",
        created_by_user_id=user_a.id,
        created_at=today_start - timedelta(days=2),
    )
    h3 = TaskHistory(
        task_id=t4.id,
        action="completed",
        old_value="in_progress",
        new_value="completed",
        reason="Action finalized cleanly",
        created_by_user_id=user_b.id,
        created_at=now - timedelta(hours=2),
    )
    db.add_all([h1, h2, h3])

    # 5. Reminders & Follow-ups
    rem1 = Reminder(
        task_id=t1.id,
        remind_at=now - timedelta(hours=1),
        message=f"Urgent migration reminder {tag}",
        is_sent=False,
    )
    rem2 = Reminder(
        task_id=t2.id,
        remind_at=now + timedelta(hours=2),
        message=f"Upcoming contract alert {tag}",
        is_sent=True,
    )
    fu1 = FollowUp(
        task_id=t1.id,
        scheduled_at=today_start - timedelta(days=1),
        completed_at=None,
        notes=f"Check with DevOps team {tag}",
    )
    fu2 = FollowUp(
        task_id=t4.id,
        scheduled_at=today_start - timedelta(days=2),
        completed_at=now - timedelta(hours=1),
        notes=f"Follow up with attendees completed {tag}",
    )
    db.add_all([rem1, rem2, fu1, fu2])

    db.commit()

    token_a, _ = create_access_token(user_a.id)
    token_b, _ = create_access_token(user_b.id)

    return {
        "tag": tag,
        "user_a": user_a,
        "user_b": user_b,
        "token_a": token_a,
        "token_b": token_b,
        "c1": c1,
        "c2": c2,
        "w1": w1,
        "w2": w2,
        "t1": t1,
        "t2": t2,
        "t3": t3,
        "t4": t4,
        "t5": t5,
    }


# =============================================================================
# 1. Authentication & Security Isolation Tests
# =============================================================================

def test_unauthenticated_reports_rejected():
    """Unauthenticated requests to all report endpoints must return 401 Unauthorized."""
    endpoints = [
        "/api/v1/reports/task-summary",
        "/api/v1/reports/tasks",
        "/api/v1/reports/productivity",
        "/api/v1/reports/workload",
        "/api/v1/reports/activity",
        "/api/v1/reports/reminders-followups",
        "/api/v1/reports/export?report_type=task_summary",
        "/api/v1/reports/tasks/export",
        "/api/v1/reports/activity/export",
        "/api/v1/reports/workload/export",
    ]
    for ep in endpoints:
        res = client.get(ep)
        assert res.status_code == 401, f"Expected 401 for {ep}, got {res.status_code}"


# =============================================================================
# 2. Task Summary Report Tests
# =============================================================================

def test_task_summary_report_correctness(test_reports_env):
    """Verify aggregated Task Summary metrics calculated inside PostgreSQL."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    c1_id = str(test_reports_env["c1"].id)

    # Filter by client_id c1 (has t1: overdue pending, t2: due today in_progress, t5: cancelled)
    res = client.get(f"/api/v1/reports/task-summary?client_id={c1_id}", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert data["total_tasks"] == 3
    assert data["open_tasks"] == 2  # t1 (pending), t2 (in_progress)
    assert data["completed_tasks"] == 0
    assert data["cancelled_tasks"] == 1  # t5
    assert data["overdue_tasks"] == 1  # t1
    assert data["due_today_tasks"] == 1  # t2
    assert data["upcoming_tasks"] == 1  # t2 is due in the future today
    assert data["near_max_attempts"] == 1  # t1 (1/2)

    assert data["status_breakdown"]["pending"] == 1
    assert data["status_breakdown"]["in_progress"] == 1
    assert data["status_breakdown"]["completed"] == 0
    assert data["status_breakdown"]["cancelled"] == 1

    assert data["priority_breakdown"]["urgent"] == 1
    assert data["priority_breakdown"]["high"] == 1
    assert data["priority_breakdown"]["low"] == 1


# =============================================================================
# 3. Task Detail Report Filtering & Pagination Tests
# =============================================================================

def test_task_detail_report_filtering_and_pagination(test_reports_env):
    """Verify detailed paginated task list report with server-side filters."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    c1_id = str(test_reports_env["c1"].id)
    c2_id = str(test_reports_env["c2"].id)

    # 1. Filter by client c1
    res = client.get(f"/api/v1/reports/tasks?client_id={c1_id}&page=1&page_size=10", headers=headers)
    assert res.status_code == 200
    c1_data = res.json()
    assert c1_data["total"] == 3
    assert len(c1_data["items"]) == 3

    # 2. Filter by status=completed under c2
    res = client.get(f"/api/v1/reports/tasks?client_id={c2_id}&status=completed", headers=headers)
    assert res.status_code == 200
    comp_data = res.json()
    assert comp_data["total"] == 1
    assert "Weekly Team Standup Notes" in comp_data["items"][0]["title"]
    assert comp_data["items"][0]["client_name"] is not None

    # 3. Search filter
    res = client.get(f"/api/v1/reports/tasks?client_id={c1_id}&search=Migration", headers=headers)
    assert res.status_code == 200
    search_data = res.json()
    assert search_data["total"] == 1
    assert "Urgent Server Migration, Phase 1" in search_data["items"][0]["title"]

    # 4. Overdue filter
    res = client.get(f"/api/v1/reports/tasks?client_id={c1_id}&overdue=true", headers=headers)
    assert res.status_code == 200
    ov_data = res.json()
    assert ov_data["total"] == 1
    assert "Urgent Server Migration, Phase 1" in ov_data["items"][0]["title"]

    # 5. Unassigned filter
    res = client.get(f"/api/v1/reports/tasks?client_id={c1_id}&unassigned=true", headers=headers)
    assert res.status_code == 200
    unassigned_data = res.json()
    assert unassigned_data["total"] == 1
    assert "Deprecated Feature Audit" in unassigned_data["items"][0]["title"]


# =============================================================================
# 4. Productivity Report Tests
# =============================================================================

def test_productivity_report_calculations_and_zero_buckets(test_reports_env):
    """Verify daily productivity trends with zero-filled date preservation."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    c2_id = str(test_reports_env["c2"].id)
    now = datetime.now(timezone.utc)
    d_from = (now - timedelta(days=6)).strftime("%Y-%m-%dT00:00:00Z")
    d_to = now.strftime("%Y-%m-%dT23:59:59Z")

    res = client.get(f"/api/v1/reports/productivity?client_id={c2_id}&date_from={d_from}&date_to={d_to}", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert "daily_trends" in data
    assert len(data["daily_trends"]) == 7  # Exactly 7 days represented including zero days
    assert data["total_created"] == 2  # t3 and t4
    assert data["total_completed"] == 1  # t4 completed
    assert data["overall_completion_rate"] == 50.0  # 1/2 = 50.0%

    # Verify each daily point structure
    for pt in data["daily_trends"]:
        assert "date" in pt
        assert "created_count" in pt
        assert "completed_count" in pt
        assert "overdue_count" in pt
        assert "completion_rate" in pt


# =============================================================================
# 5. Workload Report Tests
# =============================================================================

def test_workload_report_breakdowns(test_reports_env):
    """Verify multi-dimensional workload metrics across Assignees, Clients, Workflows."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    res = client.get("/api/v1/reports/workload", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert "by_assignee" in data
    assert "by_client" in data
    assert "by_workflow" in data

    # Check user_a metrics
    user_a_items = [a for a in data["by_assignee"] if a["id"] == str(test_reports_env["user_a"].id)]
    assert len(user_a_items) == 1
    assert user_a_items[0]["open_tasks"] == 2  # t1, t2
    assert user_a_items[0]["due_today_tasks"] == 1
    assert user_a_items[0]["overdue_tasks"] == 1

    # Check user_b metrics
    user_b_items = [b for b in data["by_assignee"] if b["id"] == str(test_reports_env["user_b"].id)]
    assert len(user_b_items) == 1
    assert user_b_items[0]["open_tasks"] == 1  # t3
    assert user_b_items[0]["completed_tasks"] == 1  # t4

    # Check Client c1
    c1_items = [c for c in data["by_client"] if c["id"] == str(test_reports_env["c1"].id)]
    assert len(c1_items) == 1
    assert c1_items[0]["open_tasks"] == 2
    assert c1_items[0]["total_tasks"] == 3


# =============================================================================
# 6. Activity / Audit Report Tests
# =============================================================================

def test_activity_audit_report(test_reports_env):
    """Verify activity audit report with action taxonomy counts and actor resolution."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    t1_id = str(test_reports_env["t1"].id)

    res = client.get(f"/api/v1/reports/activity?task_id={t1_id}", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert data["total"] == 2  # h1 (created), h2 (attempt)
    assert len(data["items"]) == 2

    # Check h2 attempt details
    attempt_entry = next(i for i in data["items"] if i["action"] == "attempt")
    assert attempt_entry["old_value"] == "0"
    assert attempt_entry["new_value"] == "1"
    assert "First attempt failed" in attempt_entry["reason"]
    assert attempt_entry["actor_name"] == test_reports_env["user_a"].name


# =============================================================================
# 7. Reminders & Follow-ups Report Tests
# =============================================================================

def test_reminders_and_followups_report(test_reports_env):
    """Verify reminders and follow-ups queue statistics and item linkages."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    c1_id = str(test_reports_env["c1"].id)
    res = client.get(f"/api/v1/reports/reminders-followups?client_id={c1_id}", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert "summary" in data
    assert data["summary"]["reminders_total"] >= 1
    assert data["summary"]["follow_ups_total"] >= 1
    assert len(data["reminders"]) >= 1
    assert len(data["follow_ups"]) >= 1

    # Check item details
    rem = next(r for r in data["reminders"] if r["task_id"] == str(test_reports_env["t1"].id))
    assert rem["message"] == f"Urgent migration reminder {test_reports_env['tag']}"
    assert rem["is_sent"] is False


# =============================================================================
# 8. Report Filter Validation Tests
# =============================================================================

def test_report_filter_validations(test_reports_env):
    """Invalid date ranges and sort fields must return 422 Unprocessable Entity."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}

    # 1. Invalid date range (date_from > date_to)
    d_from = "2026-12-31T00:00:00Z"
    d_to = "2026-01-01T00:00:00Z"
    res = client.get(f"/api/v1/reports/tasks?date_from={d_from}&date_to={d_to}", headers=headers)
    assert res.status_code == 422
    assert "date_from cannot be strictly later than date_to" in res.json()["detail"]

    # 2. Invalid sort_by field
    res = client.get("/api/v1/reports/tasks?sort_by=malicious_sql_column", headers=headers)
    assert res.status_code == 422
    assert "Invalid sort_by field" in res.json()["detail"]


# =============================================================================
# 9. CSV & JSON Export Tests
# =============================================================================

def test_csv_export_format_and_unicode_safety(test_reports_env):
    """Verify UTF-8 CSV exports with RFC-4180 compliance, quotes escaping, and security isolation."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    c1_id = str(test_reports_env["c1"].id)

    # 1. Export Task Detail CSV for Client 1
    res = client.get(f"/api/v1/reports/tasks/export?client_id={c1_id}&format=csv", headers=headers)
    assert res.status_code == 200
    assert "text/csv" in res.headers["Content-Type"]
    assert "attachment; filename=" in res.headers["Content-Disposition"]

    csv_content = res.content.decode("utf-8-sig")  # Handles BOM
    reader = csv.reader(io.StringIO(csv_content))
    rows = list(reader)

    # Check header
    header = rows[0]
    assert "Task ID" in header
    assert "Title" in header
    assert "Status" in header
    assert "Client Name" in header

    # Verify no sensitive password/hash fields in headers or rows
    for h in header:
        assert "password" not in h.lower()
        assert "token" not in h.lower()
        assert "secret" not in h.lower()

    # Check rows content & Unicode preservation
    full_text = res.text
    assert "Urgent Server Migration, Phase 1" in full_text
    assert "🚀" in full_text
    assert "special quotes" in full_text

    # 2. Export Task Summary CSV
    res_sum = client.get(f"/api/v1/reports/export?report_type=task_summary&client_id={c1_id}&format=csv", headers=headers)
    assert res_sum.status_code == 200
    assert "Total Tasks" in res_sum.text

    # 3. Export Productivity CSV
    res_prod = client.get(f"/api/v1/reports/export?report_type=productivity&client_id={c1_id}&format=csv", headers=headers)
    assert res_prod.status_code == 200
    assert "Productivity Summary" in res_prod.text

    # 4. Export Workload CSV
    res_wl = client.get("/api/v1/reports/workload/export?format=csv", headers=headers)
    assert res_wl.status_code == 200
    assert "WORKLOAD BY ASSIGNEE" in res_wl.text

    # 5. Export Activity CSV
    t1_id = str(test_reports_env["t1"].id)
    res_act = client.get(f"/api/v1/reports/activity/export?task_id={t1_id}&format=csv", headers=headers)
    assert res_act.status_code == 200
    assert "Activity ID" in res_act.text


def test_json_export_format(test_reports_env):
    """Verify JSON on-demand export returns structured, secure report payload."""
    headers = {"Authorization": f"Bearer {test_reports_env['token_a']}"}
    c1_id = str(test_reports_env["c1"].id)

    res = client.get(f"/api/v1/reports/export?report_type=task_detail&client_id={c1_id}&format=json", headers=headers)
    assert res.status_code == 200
    assert "application/json" in res.headers["Content-Type"]
    assert "attachment; filename=" in res.headers["Content-Disposition"]

    payload = res.json()
    assert payload["report_type"] == "task_detail"
    assert "generated_at" in payload
    assert "data" in payload
    assert "items" in payload["data"]
    assert len(payload["data"]["items"]) == 3


# =============================================================================
# 10. Empty Dataset Resilience Test
# =============================================================================

def test_empty_dataset_handling(db):
    """Isolated empty client query should return zero-valued report models without throwing errors."""
    fresh_user = User(
        name="Empty DB User",
        email=f"empty_{uuid.uuid4().hex[:6]}@example.com",
        password_hash="pw",
        is_active=True,
    )
    empty_client = Client(name=f"Empty Client {uuid.uuid4().hex[:6]}")
    db.add_all([fresh_user, empty_client])
    db.commit()

    token, _ = create_access_token(fresh_user.id)
    headers = {"Authorization": f"Bearer {token}"}
    c_id = str(empty_client.id)

    # Summary
    res = client.get(f"/api/v1/reports/task-summary?client_id={c_id}", headers=headers)
    assert res.status_code == 200
    assert res.json()["total_tasks"] == 0

    # Productivity
    res = client.get(f"/api/v1/reports/productivity?client_id={c_id}", headers=headers)
    assert res.status_code == 200
    assert res.json()["overall_completion_rate"] == 0.0
    assert res.json()["total_created"] == 0
    assert res.json()["total_completed"] == 0

    # Tasks
    res = client.get(f"/api/v1/reports/tasks?client_id={c_id}", headers=headers)
    assert res.status_code == 200
    assert res.json()["total"] == 0
    assert res.json()["items"] == []
