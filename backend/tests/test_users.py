"""Phase 10 — Users, Assignment & Team Workspace backend tests."""

import uuid
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.core.security import create_access_token, get_password_hash
from app.db import SessionLocal
from app.main import app
from app.models.enums import TaskPriority, TaskStatus
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.user import User
from app.services.auth_service import register_user
from app.services.task_service import assign_task, create_task, get_task_history, list_tasks
from app.services.user_service import get_user_by_id, list_users
from app.services.exceptions import InactiveUserError, UserNotFoundError


client = TestClient(app)


@pytest.fixture
def db():
    """Provide a database session."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


def test_unauthenticated_user_endpoints_rejected():
    """Unauthenticated requests to /api/v1/users must return 401."""
    resp = client.get("/api/v1/users")
    assert resp.status_code == 401

    resp_single = client.get(f"/api/v1/users/{uuid.uuid4()}")
    assert resp_single.status_code == 401


def test_user_listing_and_safe_fields(db: Session):
    """Authenticated user can list team members; password_hash is never exposed."""
    user_a = register_user(db, "Alice Smith", f"alice_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user_b = register_user(db, "Bob Jones", f"bob_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    token, _ = create_access_token(subject=str(user_a.id))
    headers = {"Authorization": f"Bearer {token}"}

    resp = client.get("/api/v1/users", headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert "items" in data
    assert "total" in data
    assert data["total"] >= 2

    # Verify no password_hash or secret keys are present in any item
    for item in data["items"]:
        assert "password_hash" not in item
        assert "password" not in item
        assert "token" not in item
        assert "id" in item
        assert "name" in item
        assert "email" in item
        assert "is_active" in item
        assert "created_at" in item
        assert "updated_at" in item


def test_user_search_and_active_filtering(db: Session):
    """User listing supports search by name or email, and filtering by active status."""
    unique_tag = uuid.uuid4().hex[:8]
    u1 = register_user(db, f"UniqueDev_{unique_tag}", f"dev_{unique_tag}@team.io", "Pass12345!")
    u2 = register_user(db, f"UniqueTester_{unique_tag}", f"tester_{unique_tag}@team.io", "Pass12345!")

    token, _ = create_access_token(subject=str(u1.id))
    headers = {"Authorization": f"Bearer {token}"}

    # Search by name substring
    resp = client.get(f"/api/v1/users?search=UniqueTester_{unique_tag}", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    assert data["items"][0]["email"] == f"tester_{unique_tag}@team.io"

    # Search by email substring
    resp_email = client.get(f"/api/v1/users?search=dev_{unique_tag}", headers=headers)
    assert resp_email.status_code == 200
    assert resp_email.json()["total"] == 1

    # Inactive user filtering
    u2.is_active = False
    db.commit()

    resp_active = client.get(f"/api/v1/users?search={unique_tag}&is_active=true", headers=headers)
    assert resp_active.status_code == 200
    assert resp_active.json()["total"] == 1
    assert resp_active.json()["items"][0]["id"] == str(u1.id)

    resp_inactive = client.get(f"/api/v1/users?search={unique_tag}&is_active=false", headers=headers)
    assert resp_inactive.status_code == 200
    assert resp_inactive.json()["total"] == 1
    assert resp_inactive.json()["items"][0]["id"] == str(u2.id)


def test_single_user_lookup(db: Session):
    """Authenticated user can fetch a single user profile safely."""
    user = register_user(db, "Carol White", f"carol_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    token, _ = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    resp = client.get(f"/api/v1/users/{user.id}", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == str(user.id)
    assert data["name"] == "Carol White"
    assert "password_hash" not in data


def test_actor_vs_assignee_separation_on_task_creation(db: Session):
    """Actor (authenticated user) creates task assigned to another user (assignee)."""
    actor = register_user(db, "Actor Admin", f"admin_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    assignee = register_user(db, "Assignee Worker", f"worker_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    token, _ = create_access_token(subject=str(actor.id))
    headers = {"Authorization": f"Bearer {token}"}

    payload = {
        "title": "Phase 10 Workspace Task",
        "description": "Multi-user task assignment test",
        "assigned_user_id": str(assignee.id),
        "priority": "high",
    }
    resp = client.post("/api/v1/tasks", json=payload, headers=headers)
    assert resp.status_code == 201
    data = resp.json()
    task_id = data["id"]
    assert data["assigned_user_id"] == str(assignee.id)

    # Verify history has actor as created_by_user_id
    history_resp = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers)
    assert history_resp.status_code == 200
    histories = history_resp.json()
    assert len(histories) >= 1
    assert histories[0]["action"] == "created"
    assert histories[0]["created_by_user_id"] == str(actor.id)


def test_reassignment_and_history_audit(db: Session):
    """Reassigning task records actor identity and old/new assignee values."""
    actor = register_user(db, "Manager A", f"mgr_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user_b = register_user(db, "Dev B", f"devb_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user_c = register_user(db, "Dev C", f"devc_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    task = create_task(
        db=db,
        title="Reassignment Test Task",
        assigned_user_id=user_b.id,
        created_by_user_id=actor.id,
    )

    token, _ = create_access_token(subject=str(actor.id))
    headers = {"Authorization": f"Bearer {token}"}

    # Reassign to User C
    resp = client.post(
        f"/api/v1/tasks/{task.id}/assign",
        json={"assigned_user_id": str(user_c.id)},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["assigned_user_id"] == str(user_c.id)

    # Verify audit history
    history_resp = client.get(f"/api/v1/tasks/{task.id}/history", headers=headers)
    assert history_resp.status_code == 200
    histories = history_resp.json()
    reassigned_logs = [h for h in histories if h["action"] == "reassigned"]
    assert len(reassigned_logs) == 1
    assert reassigned_logs[0]["created_by_user_id"] == str(actor.id)
    assert reassigned_logs[0]["old_value"] == str(user_b.id)
    assert reassigned_logs[0]["new_value"] == str(user_c.id)


def test_assignment_to_inactive_or_nonexistent_user_rejected(db: Session):
    """Assigning to nonexistent or inactive user returns error."""
    actor = register_user(db, "Lead", f"lead_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    inactive_user = register_user(db, "Inactive", f"inactive_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    inactive_user.is_active = False
    db.commit()

    task = create_task(db=db, title="Active Assignee Invariant", created_by_user_id=actor.id)

    token, _ = create_access_token(subject=str(actor.id))
    headers = {"Authorization": f"Bearer {token}"}

    # Nonexistent user
    fake_id = uuid.uuid4()
    resp_fake = client.post(
        f"/api/v1/tasks/{task.id}/assign",
        json={"assigned_user_id": str(fake_id)},
        headers=headers,
    )
    assert resp_fake.status_code == 404

    # Inactive user
    resp_inactive = client.post(
        f"/api/v1/tasks/{task.id}/assign",
        json={"assigned_user_id": str(inactive_user.id)},
        headers=headers,
    )
    assert resp_inactive.status_code in (400, 401, 409)


def test_unassigned_filter_in_tasks_api(db: Session):
    """GET /api/v1/tasks?unassigned=true retrieves only tasks with no assignee."""
    user = register_user(db, "Filter Test User", f"filter_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    t_assigned = create_task(db=db, title="Assigned 1", assigned_user_id=user.id, created_by_user_id=user.id)
    t_unassigned = create_task(db=db, title="Unassigned 1", assigned_user_id=None, created_by_user_id=user.id)

    token, _ = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    resp = client.get("/api/v1/tasks?unassigned=true", headers=headers)
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert any(item["id"] == str(t_unassigned.id) for item in items)
    assert all(item["assigned_user_id"] is None for item in items)
