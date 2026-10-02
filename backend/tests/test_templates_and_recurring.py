"""Phase 14 backend test suite for Task Templates, Recurring Tasks, and Workflow Automation."""

from datetime import datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.models.client import Client
from app.models.enums import RecurrenceType, TaskPriority, TaskStatus
from app.models.notification import Notification
from app.models.recurring_task import RecurringTask, RecurringTaskExecution
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.task_template import TaskTemplate
from app.models.user import User
from app.models.workflow import Workflow
from app.services.auth_service import register_user
from app.services.recurring_task_service import compute_next_run, evaluate_recurring_tasks


@pytest.fixture
def auth_headers_user1(client: TestClient, db: Session) -> dict:
    """Register and authenticate User 1."""
    email = f"user1_phase14_{datetime.now().timestamp()}@example.com"
    register_user(db, name="User One", email=email, password="Password123!")
    res = client.post("/api/v1/auth/login", json={"email": email, "password": "Password123!"})
    token = res.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers_user2(client: TestClient, db: Session) -> dict:
    """Register and authenticate User 2."""
    email = f"user2_phase14_{datetime.now().timestamp()}@example.com"
    register_user(db, name="User Two", email=email, password="Password123!")
    res = client.post("/api/v1/auth/login", json={"email": email, "password": "Password123!"})
    token = res.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def test_client_entity(db: Session) -> Client:
    c = Client(name=f"Template Client {datetime.now().timestamp()}")
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


@pytest.fixture
def test_workflow_entity(db: Session) -> Workflow:
    w = Workflow(name=f"Template Workflow {datetime.now().timestamp()}", is_active=True)
    db.add(w)
    db.commit()
    db.refresh(w)
    return w


def test_unauthenticated_template_and_recurrence_apis_rejected(client: TestClient):
    """Verify all template and recurring endpoints reject unauthenticated requests with 401."""
    assert client.post("/api/v1/task-templates", json={"name": "Test"}).status_code == 401
    assert client.get("/api/v1/task-templates").status_code == 401
    assert client.post("/api/v1/recurring-tasks", json={"name": "Rec"}).status_code == 401
    assert client.get("/api/v1/recurring-tasks").status_code == 401
    assert client.post("/api/v1/recurring-tasks/evaluate").status_code == 401


def test_task_template_crud_and_creator_isolation(
    client: TestClient,
    auth_headers_user1: dict,
    auth_headers_user2: dict,
    test_client_entity: Client,
    test_workflow_entity: Workflow,
):
    """Test TaskTemplate creation, retrieval, updates, and creator-based authorization."""
    # 1. Create Template by User 1
    create_payload = {
        "name": "Standard Onboarding",
        "description": "Onboarding checklist for new enterprise clients",
        "subject_line": "Welcome to NextAction",
        "client_id": str(test_client_entity.id),
        "workflow_id": str(test_workflow_entity.id),
        "priority": "high",
        "max_attempts": 3,
        "default_due_offset_days": 5,
        "default_next_action_offset_days": 1,
        "is_active": True,
    }
    create_res = client.post("/api/v1/task-templates", json=create_payload, headers=auth_headers_user1)
    assert create_res.status_code == 201, create_res.text
    template_data = create_res.json()
    template_id = template_data["id"]
    assert template_data["name"] == "Standard Onboarding"
    assert template_data["priority"] == "high"
    assert template_data["default_due_offset_days"] == 5

    # 2. List Templates by User 2 (shared discovery)
    list_res = client.get("/api/v1/task-templates", headers=auth_headers_user2)
    assert list_res.status_code == 200
    assert any(t["id"] == template_id for t in list_res.json()["items"])

    # 3. Search Templates by keyword
    search_res = client.get("/api/v1/task-templates?search=Onboarding", headers=auth_headers_user1)
    assert search_res.status_code == 200
    assert any(t["id"] == template_id for t in search_res.json()["items"])

    # 4. User 2 cannot update User 1's template (403 Forbidden)
    update_res_unauth = client.patch(
        f"/api/v1/task-templates/{template_id}",
        json={"name": "Hacked Template"},
        headers=auth_headers_user2,
    )
    assert update_res_unauth.status_code == 403

    # 5. User 1 can update own template
    update_res = client.patch(
        f"/api/v1/task-templates/{template_id}",
        json={"name": "Updated Enterprise Onboarding", "priority": "urgent"},
        headers=auth_headers_user1,
    )
    assert update_res.status_code == 200
    assert update_res.json()["name"] == "Updated Enterprise Onboarding"
    assert update_res.json()["priority"] == "urgent"

    # 6. User 2 cannot delete User 1's template (403 Forbidden)
    del_res_unauth = client.delete(f"/api/v1/task-templates/{template_id}", headers=auth_headers_user2)
    assert del_res_unauth.status_code == 403

    # 7. User 1 can delete own template
    del_res = client.delete(f"/api/v1/task-templates/{template_id}", headers=auth_headers_user1)
    assert del_res.status_code == 204


def test_create_task_from_template_with_offsets_and_overrides(
    client: TestClient,
    auth_headers_user1: dict,
    test_client_entity: Client,
    test_workflow_entity: Workflow,
    db: Session,
):
    """Test generating a concrete Task from a Template, verifying offset math, overrides, and history."""
    # Create Template
    create_res = client.post(
        "/api/v1/task-templates",
        json={
            "name": "Weekly Check-in",
            "description": "Weekly progress review",
            "subject_line": "Weekly Review",
            "client_id": str(test_client_entity.id),
            "workflow_id": str(test_workflow_entity.id),
            "priority": "medium",
            "max_attempts": 2,
            "default_due_offset_days": 7,
            "default_next_action_offset_days": 2,
        },
        headers=auth_headers_user1,
    )
    template_id = create_res.json()["id"]

    # 1. Create Task using defaults
    gen_res = client.post(
        f"/api/v1/task-templates/{template_id}/create-task",
        json={},
        headers=auth_headers_user1,
    )
    assert gen_res.status_code == 201
    task_data = gen_res.json()
    task_id = task_data["id"]
    assert task_data["title"] == "Weekly Check-in"
    assert task_data["template_id"] == template_id
    assert task_data["due_date"] is not None
    assert task_data["next_action_date"] is not None

    # Check TaskHistory
    history = db.query(TaskHistory).filter(TaskHistory.task_id == task_id).all()
    assert any(h.action == "created_from_template" for h in history)

    # 2. Create Task with explicit overrides
    custom_due = (datetime.now(timezone.utc) + timedelta(days=14)).isoformat()
    gen_custom_res = client.post(
        f"/api/v1/task-templates/{template_id}/create-task",
        json={
            "title": "Custom Client Check-in",
            "priority": "urgent",
            "due_date": custom_due,
        },
        headers=auth_headers_user1,
    )
    assert gen_custom_res.status_code == 201
    custom_task = gen_custom_res.json()
    assert custom_task["title"] == "Custom Client Check-in"
    assert custom_task["priority"] == "urgent"
    assert custom_task["template_id"] == template_id


def test_recurrence_date_math_calculations():
    """Unit test compute_next_run for daily, weekly, and monthly end-of-month calendar handling."""
    base_time = datetime(2026, 1, 31, 10, 0, 0, tzinfo=timezone.utc)

    # Daily (+1 day) -> Feb 1
    next_daily = compute_next_run(base_time, RecurrenceType.DAILY, interval=1)
    assert next_daily == datetime(2026, 2, 1, 10, 0, 0, tzinfo=timezone.utc)

    # Weekly (+2 weeks) -> Feb 14
    next_weekly = compute_next_run(base_time, RecurrenceType.WEEKLY, interval=2)
    assert next_weekly == datetime(2026, 2, 14, 10, 0, 0, tzinfo=timezone.utc)

    # Monthly from Jan 31 (+1 month) -> Clamped to Feb 28 (non-leap year 2026)
    next_monthly = compute_next_run(base_time, RecurrenceType.MONTHLY, interval=1)
    assert next_monthly.month == 2
    assert next_monthly.day == 28

    # Monthly from Jan 31 (+3 months) -> April 30 (clamped to 30 days)
    next_monthly_apr = compute_next_run(base_time, RecurrenceType.MONTHLY, interval=3)
    assert next_monthly_apr.month == 4
    assert next_monthly_apr.day == 30


def test_recurring_task_lifecycle_and_idempotent_evaluation(
    client: TestClient,
    auth_headers_user1: dict,
    auth_headers_user2: dict,
    db: Session,
):
    """Test RecurringTask CRUD, evaluation, duplicate prevention, and next_run advancement."""
    past_start = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
    future_end = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()

    # 1. Create Recurring Task
    rec_res = client.post(
        "/api/v1/recurring-tasks",
        json={
            "name": "Daily Invoice Sweep",
            "description": "Scan and reconcile all pending invoices",
            "recurrence_type": "daily",
            "interval": 1,
            "start_date": past_start,
            "end_date": future_end,
            "due_offset_days": 1,
            "next_action_offset_days": 0,
            "priority": "high",
        },
        headers=auth_headers_user1,
    )
    assert rec_res.status_code == 201
    rec_data = rec_res.json()
    rec_id = rec_data["id"]
    assert rec_data["name"] == "Daily Invoice Sweep"
    assert rec_data["is_active"] is True

    # 2. User 2 cannot modify User 1's recurring task
    unauth_update = client.patch(
        f"/api/v1/recurring-tasks/{rec_id}",
        json={"name": "Tampered Recurrence"},
        headers=auth_headers_user2,
    )
    assert unauth_update.status_code == 403

    # 3. Evaluate recurring tasks (First run: generates exactly 1 task)
    eval_res1 = client.post(
        "/api/v1/recurring-tasks/evaluate",
        json={"max_evaluations": 10},
        headers=auth_headers_user1,
    )
    assert eval_res1.status_code == 200
    eval_data1 = eval_res1.json()
    assert eval_data1["tasks_created"] >= 1
    created_task = next(t for t in eval_data1["created_tasks"] if t["title"] == "Daily Invoice Sweep")
    assert created_task["recurring_task_id"] == rec_id

    # Check TaskHistory for recurrence generation
    history = db.query(TaskHistory).filter(TaskHistory.task_id == created_task["id"]).all()
    assert any(h.action == "generated_from_recurrence" for h in history)

    # 4. Immediate re-evaluation must NOT create duplicates (Idempotency check)
    eval_res2 = client.post(
        "/api/v1/recurring-tasks/evaluate",
        json={"max_evaluations": 10},
        headers=auth_headers_user1,
    )
    assert eval_res2.status_code == 200
    # No duplicate task should be created for the same recurrence
    tasks_for_rec = db.query(Task).filter(Task.recurring_task_id == rec_id).all()
    assert len(tasks_for_rec) == 1

    # 5. Verify next_run_at advanced into the future
    rec_db = db.get(RecurringTask, rec_id)
    assert rec_db.last_run_at is not None
    assert rec_db.next_run_at > datetime.now(timezone.utc)

    # 6. Delete Recurring Task
    del_res = client.delete(f"/api/v1/recurring-tasks/{rec_id}", headers=auth_headers_user1)
    assert del_res.status_code == 204


def test_invalid_template_references_rejected(
    client: TestClient,
    auth_headers_user1: dict,
    db: Session,
):
    """Verify template creation rejects nonexistent client, workflow, or inactive user."""
    fake_id = "00000000-0000-0000-0000-000000000000"

    # Nonexistent client
    res1 = client.post(
        "/api/v1/task-templates",
        json={"name": "Bad Client", "client_id": fake_id},
        headers=auth_headers_user1,
    )
    assert res1.status_code == 404

    # Nonexistent workflow
    res2 = client.post(
        "/api/v1/task-templates",
        json={"name": "Bad Workflow", "workflow_id": fake_id},
        headers=auth_headers_user1,
    )
    assert res2.status_code == 404

    # Inactive user
    inactive_user = register_user(
        db,
        name="Inactive Person",
        email=f"inactive_{datetime.now().timestamp()}@example.com",
        password="Password123!",
    )
    inactive_user.is_active = False
    db.commit()

    res3 = client.post(
        "/api/v1/task-templates",
        json={"name": "Bad User", "assigned_user_id": str(inactive_user.id)},
        headers=auth_headers_user1,
    )
    assert res3.status_code == 401


def test_invalid_recurrence_rules_rejected(
    client: TestClient,
    auth_headers_user1: dict,
):
    """Verify invalid intervals and invalid dates are rejected with 400 or 422."""
    now_iso = datetime.now(timezone.utc).isoformat()
    past_iso = (datetime.now(timezone.utc) - timedelta(days=10)).isoformat()

    # Interval 0 (rejected by Pydantic ge=1 -> 422)
    res1 = client.post(
        "/api/v1/recurring-tasks",
        json={"name": "Zero Interval", "interval": 0, "start_date": now_iso},
        headers=auth_headers_user1,
    )
    assert res1.status_code == 422

    # end_date before start_date (rejected by domain -> 400)
    res2 = client.post(
        "/api/v1/recurring-tasks",
        json={
            "name": "Invalid End Date",
            "interval": 1,
            "start_date": now_iso,
            "end_date": past_iso,
        },
        headers=auth_headers_user1,
    )
    assert res2.status_code == 400


def test_recurrence_with_assigned_user_generates_notification(
    client: TestClient,
    auth_headers_user1: dict,
    db: Session,
):
    """Verify generated recurring tasks generate assignment notifications for assignees."""
    assignee = register_user(
        db,
        name="Assignee Person",
        email=f"assignee_{datetime.now().timestamp()}@example.com",
        password="Password123!",
    )
    past_start = (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat()

    rec_res = client.post(
        "/api/v1/recurring-tasks",
        json={
            "name": "Assigned Recurring Duty",
            "assigned_user_id": str(assignee.id),
            "start_date": past_start,
            "recurrence_type": "daily",
        },
        headers=auth_headers_user1,
    )
    assert rec_res.status_code == 201

    eval_res = client.post(
        "/api/v1/recurring-tasks/evaluate",
        json={"max_evaluations": 10},
        headers=auth_headers_user1,
    )
    assert eval_res.status_code == 200

    # Verify notification created for assignee
    notif = db.query(Notification).filter(Notification.user_id == assignee.id).first()
    assert notif is not None
    assert "Assigned Recurring Duty" in notif.title

