"""Comprehensive integration test suite for FastAPI REST API endpoints.

Executes against live PostgreSQL database with JWT authentication.
"""

from datetime import datetime, timedelta, timezone
import uuid
from fastapi.testclient import TestClient
import pytest
from app.db import SessionLocal
from app.main import app
from app.models import Task, TaskHistory, User
from app.services.auth_service import register_user

client = TestClient(app)


@pytest.fixture
def db():
    """Provide a database session for direct inspection."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture
def test_user(db):
    """Create a sample authenticated user and return credentials."""
    email = f"api_user_{uuid.uuid4().hex[:8]}@example.com"
    password = "TestPassword123!"
    user = register_user(db=db, name="API Test Operator", email=email, password=password)
    return user, email, password


@pytest.fixture
def auth_headers(test_user):
    """Provide valid Authorization headers for the authenticated user."""
    user, email, password = test_user
    login_resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert login_resp.status_code == 200
    token = login_resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}, user


# =========================================================================
# A. Task Creation
# =========================================================================
def test_api_task_creation(db, auth_headers):
    """POST /api/v1/tasks creates task, returns 201, persists to DB and writes history."""
    headers, user = auth_headers
    due = (datetime.now(timezone.utc) + timedelta(days=5)).isoformat()
    next_action = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()

    payload = {
        "title": "Prepare Annual Filing",
        "description": "Gather audit documentation",
        "subject_line": "Annual Audit 2026",
        "assigned_user_id": str(user.id),
        "due_date": due,
        "next_action_date": next_action,
        "max_attempts": 2,
    }

    response = client.post("/api/v1/tasks", json=payload, headers=headers)
    assert response.status_code == 201
    data = response.json()

    task_id = uuid.UUID(data["id"])
    assert data["title"] == "Prepare Annual Filing"
    assert data["status"] == "pending"
    assert data["priority"] == "medium"
    assert data["attempt_count"] == 0
    assert data["max_attempts"] == 2
    assert data["assigned_user_id"] == str(user.id)

    # Verify directly in DB
    db_task = db.get(Task, task_id)
    assert db_task is not None
    assert db_task.title == "Prepare Annual Filing"

    # Verify history
    hist_response = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers)
    assert hist_response.status_code == 200
    histories = hist_response.json()
    assert len(histories) >= 1
    assert histories[0]["action"] == "created"


# =========================================================================
# B. Task Retrieval & Listing
# =========================================================================
def test_api_task_retrieval_and_listing(auth_headers):
    """GET /api/v1/tasks/{task_id} and GET /api/v1/tasks."""
    headers, user = auth_headers

    # Create task
    create_resp = client.post("/api/v1/tasks", json={"title": "List Retrieval Test"}, headers=headers)
    assert create_resp.status_code == 201
    task_id = create_resp.json()["id"]

    # Existing task
    get_resp = client.get(f"/api/v1/tasks/{task_id}", headers=headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == task_id

    # Missing task
    missing_id = str(uuid.uuid4())
    missing_resp = client.get(f"/api/v1/tasks/{missing_id}", headers=headers)
    assert missing_resp.status_code == 404
    assert missing_resp.json()["error"] == "TASK_NOT_FOUND"

    # List tasks
    list_resp = client.get("/api/v1/tasks?page=1&page_size=10", headers=headers)
    assert list_resp.status_code == 200
    list_data = list_resp.json()
    assert "items" in list_data
    assert list_data["total"] >= 1


# =========================================================================
# C. Attempt & Max Attempts
# =========================================================================
def test_api_attempts_and_max_attempts_rejection(auth_headers):
    """Test attempt incrementing, max attempt rejection (409), and attempt invariant."""
    headers, user = auth_headers
    create_resp = client.post(
        "/api/v1/tasks",
        json={"title": "Outreach Call", "max_attempts": 2},
        headers=headers,
    )
    task_id = create_resp.json()["id"]

    # 1st attempt -> 200, count=1
    att1_resp = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"notes": "Left voicemail"},
        headers=headers,
    )
    assert att1_resp.status_code == 200
    assert att1_resp.json()["attempt_count"] == 1

    # 2nd attempt -> 200, count=2
    att2_resp = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"notes": "No answer"},
        headers=headers,
    )
    assert att2_resp.status_code == 200
    assert att2_resp.json()["attempt_count"] == 2

    # 3rd attempt -> 409 (MAX_ATTEMPTS_REACHED)
    att3_resp = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"notes": "3rd call attempt"},
        headers=headers,
    )
    assert att3_resp.status_code == 409
    assert att3_resp.json()["error"] == "MAX_ATTEMPTS_REACHED"

    # Verify attempt_count remains 2
    get_resp = client.get(f"/api/v1/tasks/{task_id}", headers=headers)
    assert get_resp.json()["attempt_count"] == 2


# =========================================================================
# D. Authorized Override
# =========================================================================
def test_api_authorized_override(auth_headers):
    """Test override validation (400/422 if reason missing) and successful override (200, count=3)."""
    headers, user = auth_headers
    create_resp = client.post(
        "/api/v1/tasks",
        json={"title": "VIP Escalation", "max_attempts": 2},
        headers=headers,
    )
    task_id = create_resp.json()["id"]

    # Max out attempts
    client.post(f"/api/v1/tasks/{task_id}/attempt", headers=headers)
    client.post(f"/api/v1/tasks/{task_id}/attempt", headers=headers)

    # Override without reason (fails 400 or 422)
    invalid_resp = client.post(
        f"/api/v1/tasks/{task_id}/attempt/override",
        json={"authorized_override": True, "reason": ""},
        headers=headers,
    )
    assert invalid_resp.status_code in [400, 422]

    # Valid override
    valid_resp = client.post(
        f"/api/v1/tasks/{task_id}/attempt/override",
        json={
            "authorized_override": True,
            "reason": "Director approved special follow-up window",
        },
        headers=headers,
    )
    assert valid_resp.status_code == 200
    assert valid_resp.json()["attempt_count"] == 3

    # Verify history contains attempt_override
    hist_resp = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers)
    actions = [h["action"] for h in hist_resp.json()]
    assert "attempt_override" in actions


# =========================================================================
# E. Reminder API
# =========================================================================
def test_api_reminders_attempt_invariant(auth_headers):
    """POST /api/v1/reminders and /send do NOT modify task attempt_count."""
    headers, user = auth_headers
    task_resp = client.post(
        "/api/v1/tasks",
        json={"title": "Task with Reminders", "max_attempts": 2},
        headers=headers,
    )
    task_id = task_resp.json()["id"]
    assert task_resp.json()["attempt_count"] == 0

    remind_at = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    rem_resp = client.post(
        "/api/v1/reminders",
        json={
            "task_id": task_id,
            "remind_at": remind_at,
            "message": "Upcoming deadline alert",
        },
        headers=headers,
    )
    assert rem_resp.status_code == 201
    reminder_id = rem_resp.json()["id"]
    assert rem_resp.json()["is_sent"] is False

    # Verify task attempt count unchanged
    task_check1 = client.get(f"/api/v1/tasks/{task_id}", headers=headers).json()
    assert task_check1["attempt_count"] == 0

    # Process/send reminder
    send_resp = client.post(f"/api/v1/reminders/{reminder_id}/send", headers=headers)
    assert send_resp.status_code == 200
    assert send_resp.json()["is_sent"] is True

    # Verify task attempt count still unchanged
    task_check2 = client.get(f"/api/v1/tasks/{task_id}", headers=headers).json()
    assert task_check2["attempt_count"] == 0

    # Due reminders endpoint
    due_resp = client.get("/api/v1/reminders/due", headers=headers)
    assert due_resp.status_code == 200

    # Task reminders endpoint
    task_rem_resp = client.get(f"/api/v1/tasks/{task_id}/reminders", headers=headers)
    assert task_rem_resp.status_code == 200
    assert len(task_rem_resp.json()) == 1
    assert task_rem_resp.json()[0]["id"] == reminder_id


# =========================================================================
# F. Postponement
# =========================================================================
def test_api_postponement(auth_headers):
    """POST /api/v1/tasks/{task_id}/postpone validation and history preservation."""
    headers, user = auth_headers
    orig_due = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
    new_due = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()

    task_resp = client.post(
        "/api/v1/tasks",
        json={"title": "Postponable Task", "due_date": orig_due},
        headers=headers,
    )
    task_id = task_resp.json()["id"]

    # Missing reason -> 400 or 422
    fail_resp = client.post(
        f"/api/v1/tasks/{task_id}/postpone",
        json={"new_due_date": new_due, "reason": ""},
        headers=headers,
    )
    assert fail_resp.status_code in [400, 422]

    # Valid postponement -> 200
    postpone_resp = client.post(
        f"/api/v1/tasks/{task_id}/postpone",
        json={
            "new_due_date": new_due,
            "reason": "Client travel schedule conflict",
        },
        headers=headers,
    )
    assert postpone_resp.status_code == 200

    # Verify history
    hist_resp = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers)
    postpone_hist = [h for h in hist_resp.json() if h["action"] == "postponed"]
    assert len(postpone_hist) == 1
    assert postpone_hist[0]["reason"] == "Client travel schedule conflict"


# =========================================================================
# G & H. Completion and Reopen
# =========================================================================
def test_api_completion_and_reopen(auth_headers):
    """POST /complete and POST /reopen lifecycle."""
    headers, user = auth_headers
    task_resp = client.post("/api/v1/tasks", json={"title": "Completable Task"}, headers=headers)
    task_id = task_resp.json()["id"]

    # Complete
    comp_resp = client.post(f"/api/v1/tasks/{task_id}/complete", headers=headers)
    assert comp_resp.status_code == 200
    assert comp_resp.json()["status"] == "completed"
    assert comp_resp.json()["completed_at"] is not None

    # Duplicate completion -> 409
    dup_resp = client.post(f"/api/v1/tasks/{task_id}/complete", headers=headers)
    assert dup_resp.status_code == 409
    assert dup_resp.json()["error"] == "TASK_ALREADY_COMPLETED"

    # Reopen without reason -> 400 or 422
    fail_reopen = client.post(f"/api/v1/tasks/{task_id}/reopen", json={"reason": ""}, headers=headers)
    assert fail_reopen.status_code in [400, 422]

    # Reopen with reason -> 200
    reopen_resp = client.post(
        f"/api/v1/tasks/{task_id}/reopen",
        json={"reason": "Additional feedback received"},
        headers=headers,
    )
    assert reopen_resp.status_code == 200
    assert reopen_resp.json()["status"] == "pending"
    assert reopen_resp.json()["completed_at"] is None


# =========================================================================
# I, J, K, L. Status, Priority, Assignment, Subject Line, Next Action
# =========================================================================
def test_api_attribute_transitions(auth_headers):
    """Test updating status, priority, assignment, subject line, next action date."""
    headers, user = auth_headers
    task_resp = client.post("/api/v1/tasks", json={"title": "Transition Task", "priority": "low"}, headers=headers)
    task_id = task_resp.json()["id"]

    # Status
    st_resp = client.post(
        f"/api/v1/tasks/{task_id}/status",
        json={"status": "in_progress", "reason": "Started by operator"},
        headers=headers,
    )
    assert st_resp.status_code == 200
    assert st_resp.json()["status"] == "in_progress"

    # Priority
    prio_resp = client.post(
        f"/api/v1/tasks/{task_id}/priority",
        json={"priority": "urgent", "reason": "Immediate SLA deadline"},
        headers=headers,
    )
    assert prio_resp.status_code == 200
    assert prio_resp.json()["priority"] == "urgent"

    # Assignment
    assign_resp = client.post(
        f"/api/v1/tasks/{task_id}/assign",
        json={"assigned_user_id": str(user.id)},
        headers=headers,
    )
    assert assign_resp.status_code == 200
    assert assign_resp.json()["assigned_user_id"] == str(user.id)

    # Subject Line
    sub_resp = client.post(
        f"/api/v1/tasks/{task_id}/subject-line",
        json={"subject_line": "Updated Urgent Subject"},
        headers=headers,
    )
    assert sub_resp.status_code == 200
    assert sub_resp.json()["subject_line"] == "Updated Urgent Subject"

    # Next Action Date
    next_date = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    na_resp = client.post(
        f"/api/v1/tasks/{task_id}/next-action",
        json={"next_action_date": next_date},
        headers=headers,
    )
    assert na_resp.status_code == 200


# =========================================================================
# M. Follow-Up Endpoints
# =========================================================================
def test_api_follow_up_endpoints(auth_headers):
    """POST, GET, and complete follow-up endpoints."""
    headers, user = auth_headers
    task_resp = client.post("/api/v1/tasks", json={"title": "Follow Up Base Task"}, headers=headers)
    task_id = task_resp.json()["id"]

    scheduled = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    create_resp = client.post(
        "/api/v1/follow-ups",
        json={
            "task_id": task_id,
            "scheduled_at": scheduled,
            "notes": "Follow up with client director",
        },
        headers=headers,
    )
    assert create_resp.status_code == 201
    follow_up_id = create_resp.json()["id"]

    # Get follow-up
    get_resp = client.get(f"/api/v1/follow-ups/{follow_up_id}", headers=headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["notes"] == "Follow up with client director"

    # Missing follow-up -> 404
    missing_resp = client.get(f"/api/v1/follow-ups/{uuid.uuid4()}", headers=headers)
    assert missing_resp.status_code == 404
    assert missing_resp.json()["error"] == "FOLLOW_UP_NOT_FOUND"

    # Complete follow-up
    comp_resp = client.post(
        f"/api/v1/follow-ups/{follow_up_id}/complete",
        json={"notes": "Call finished"},
        headers=headers,
    )
    assert comp_resp.status_code == 200
    assert comp_resp.json()["completed_at"] is not None

    # List task follow-ups
    list_resp = client.get(f"/api/v1/tasks/{task_id}/follow-ups", headers=headers)
    assert list_resp.status_code == 200
    assert len(list_resp.json()) == 1

    # List all follow-ups via GET /api/v1/follow-ups
    all_follow_ups_resp = client.get("/api/v1/follow-ups", headers=headers)
    assert all_follow_ups_resp.status_code == 200
    assert len(all_follow_ups_resp.json()) >= 1

    # Filter follow-ups by completion
    completed_resp = client.get("/api/v1/follow-ups?is_completed=true", headers=headers)
    assert completed_resp.status_code == 200
    assert all(f["completed_at"] is not None for f in completed_resp.json())


# =========================================================================
# N. General Update (PATCH)
# =========================================================================
def test_api_patch_task(auth_headers):
    """PATCH /api/v1/tasks/{task_id} updates basic fields."""
    headers, user = auth_headers
    task_resp = client.post("/api/v1/tasks", json={"title": "Original Title"}, headers=headers)
    task_id = task_resp.json()["id"]

    patch_resp = client.patch(
        f"/api/v1/tasks/{task_id}",
        json={"title": "Updated Title", "description": "New description"},
        headers=headers,
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["title"] == "Updated Title"
    assert patch_resp.json()["description"] == "New description"


# =========================================================================
# O. Recent Activity Logs
# =========================================================================
def test_api_recent_activity(auth_headers):
    """GET /api/v1/tasks/activity/recent retrieves chronological task activity."""
    headers, user = auth_headers
    # Perform a task action to generate activity
    task_resp = client.post("/api/v1/tasks", json={"title": "Activity Task Log"}, headers=headers)
    task_id = task_resp.json()["id"]

    client.post(f"/api/v1/tasks/{task_id}/attempt", headers=headers)

    act_resp = client.get("/api/v1/tasks/activity/recent?limit=10", headers=headers)
    assert act_resp.status_code == 200
    activities = act_resp.json()
    assert isinstance(activities, list)
    assert len(activities) >= 1
    actions = [a["action"] for a in activities]
    assert "attempt" in actions or "created" in actions

