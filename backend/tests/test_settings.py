"""Unit and integration tests for Settings, Personalization & System Configuration (Phase 18)."""

from datetime import datetime, timezone
import uuid
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.models.client import Client
from app.models.task import Task
from app.models.user import User
from app.models.workflow import Workflow
from app.services.notification_service import evaluate_due_notifications, get_user_notifications
from app.services.reminder_service import create_reminder
from app.services.settings_service import get_user_settings
from app.services.task_service import assign_task, create_task


def get_user_headers(client: TestClient, prefix: str, name: str, password: str = "Password123!"):
    """Helper to register and login a user with unique email and return Authorization headers."""
    email = f"{prefix}_{uuid.uuid4().hex[:8]}@nextaction.local"
    reg = client.post("/api/v1/auth/register", json={"name": name, "email": email, "password": password})
    assert reg.status_code == 201
    login = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert login.status_code == 200
    token = login.json()["access_token"]
    user_id = reg.json()["id"]
    return {"Authorization": f"Bearer {token}"}, user_id


def test_unauthenticated_settings_endpoints_rejected(client: TestClient):
    """Verify all settings endpoints require Bearer JWT authentication."""
    # GET /settings
    res = client.get("/api/v1/settings")
    assert res.status_code == 401

    # PATCH /settings
    res = client.patch("/api/v1/settings", json={"theme": "dark"})
    assert res.status_code == 401

    # POST /settings/reset
    res = client.post("/api/v1/settings/reset")
    assert res.status_code == 401


def test_get_settings_auto_provisioning_and_defaults(client: TestClient, db: Session):
    """Verify first GET auto-provisions default settings for the authenticated user."""
    headers, user_id = get_user_headers(client, "alice_settings", "Alice Settings")

    # Fetch settings
    res = client.get("/api/v1/settings", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert data["timezone"] == "UTC"
    assert data["date_format"] == "YYYY-MM-DD"
    assert data["time_format"] == "24h"
    assert data["first_day_of_week"] == "monday"
    assert data["theme"] == "system"
    assert data["compact_mode"] is False
    assert data["default_task_priority"] == "medium"
    assert data["default_task_status_filter"] == "all"
    assert data["default_task_sort"] == "due_date"
    assert data["default_task_sort_order"] == "asc"
    assert data["default_max_attempts"] == 3
    assert data["default_page_size"] == 20
    assert data["default_dashboard_time_range"] == "last_7_days"
    assert data["default_report_date_range"] == "last_7_days"
    assert data["default_report_type"] == "task_summary"
    assert data["default_export_format"] == "csv"

    # All notification flags default to True
    assert data["notify_task_assigned"] is True
    assert data["notify_task_reassigned"] is True
    assert data["notify_reminder_due"] is True
    assert data["notify_follow_up_due"] is True
    assert data["notify_next_action_due"] is True
    assert data["notify_task_overdue"] is True
    assert data["notify_attempt_limit_reached"] is True
    assert data["notify_task_completed"] is True
    assert data["notify_task_reopened"] is True


def test_patch_settings_partial_update(client: TestClient, db: Session):
    """Verify PATCH modifies only explicitly supplied fields while preserving others."""
    headers, user_id = get_user_headers(client, "bob_settings", "Bob Settings")

    patch_payload = {
        "timezone": "Asia/Kolkata",
        "theme": "dark",
        "compact_mode": True,
        "default_task_priority": "urgent",
        "default_max_attempts": 5,
        "notify_task_assigned": False,
    }
    res = client.patch("/api/v1/settings", headers=headers, json=patch_payload)
    assert res.status_code == 200
    data = res.json()

    # Updated fields
    assert data["timezone"] == "Asia/Kolkata"
    assert data["theme"] == "dark"
    assert data["compact_mode"] is True
    assert data["default_task_priority"] == "urgent"
    assert data["default_max_attempts"] == 5
    assert data["notify_task_assigned"] is False

    # Preserved fields
    assert data["date_format"] == "YYYY-MM-DD"
    assert data["time_format"] == "24h"
    assert data["default_page_size"] == 20
    assert data["notify_task_completed"] is True


def test_settings_validation_errors(client: TestClient):
    """Verify validation constraints on timezone, enums, and numerical ranges."""
    headers, _ = get_user_headers(client, "charlie_val", "Charlie Validation")

    # 1. Invalid timezone
    res = client.patch("/api/v1/settings", headers=headers, json={"timezone": "Invalid/Fake_Zone"})
    assert res.status_code == 422
    assert "timezone" in str(res.json())

    # 2. Invalid theme
    res = client.patch("/api/v1/settings", headers=headers, json={"theme": "neon_punk"})
    assert res.status_code == 422

    # 3. Invalid date_format
    res = client.patch("/api/v1/settings", headers=headers, json={"date_format": "YYYY/MM/DD"})
    assert res.status_code == 422

    # 4. Invalid time_format
    res = client.patch("/api/v1/settings", headers=headers, json={"time_format": "48h"})
    assert res.status_code == 422

    # 5. Invalid default_max_attempts (< 1 or > 10)
    res = client.patch("/api/v1/settings", headers=headers, json={"default_max_attempts": 0})
    assert res.status_code == 422
    res = client.patch("/api/v1/settings", headers=headers, json={"default_max_attempts": 11})
    assert res.status_code == 422

    # 6. Invalid default_page_size
    res = client.patch("/api/v1/settings", headers=headers, json={"default_page_size": 35})
    assert res.status_code == 422


def test_valid_iana_timezones(client: TestClient):
    """Verify various standard IANA timezones are accepted."""
    headers, _ = get_user_headers(client, "dave_tz", "Dave TZ")

    valid_timezones = [
        "UTC",
        "Asia/Kolkata",
        "America/New_York",
        "Europe/London",
        "Asia/Dubai",
        "Asia/Tokyo",
        "Australia/Sydney",
        "America/Los_Angeles",
    ]

    for tz in valid_timezones:
        res = client.patch("/api/v1/settings", headers=headers, json={"timezone": tz})
        assert res.status_code == 200
        assert res.json()["timezone"] == tz


def test_reset_user_settings(client: TestClient):
    """Verify POST /api/v1/settings/reset restores system defaults."""
    headers, _ = get_user_headers(client, "eve_reset", "Eve Reset")

    # Modify multiple settings
    client.patch(
        "/api/v1/settings",
        headers=headers,
        json={
            "timezone": "America/Chicago",
            "theme": "dark",
            "default_task_priority": "urgent",
            "default_max_attempts": 7,
            "notify_task_assigned": False,
        },
    )

    # Call reset
    res = client.post("/api/v1/settings/reset", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert data["timezone"] == "UTC"
    assert data["theme"] == "system"
    assert data["default_task_priority"] == "medium"
    assert data["default_max_attempts"] == 3
    assert data["notify_task_assigned"] is True


def test_cross_user_isolation(client: TestClient):
    """Verify users cannot see or mutate each other's preferences."""
    # User 1
    headers1, _ = get_user_headers(client, "user1_iso", "User One")

    # User 2
    headers2, _ = get_user_headers(client, "user2_iso", "User Two")

    # User 1 updates theme to dark and timezone to Asia/Kolkata
    client.patch(
        "/api/v1/settings",
        headers=headers1,
        json={"theme": "dark", "timezone": "Asia/Kolkata"},
    )

    # User 2 checks their settings - should still be default
    res2 = client.get("/api/v1/settings", headers=headers2)
    assert res2.status_code == 200
    assert res2.json()["theme"] == "system"
    assert res2.json()["timezone"] == "UTC"

    # User 1 checks their settings - should be their own
    res1 = client.get("/api/v1/settings", headers=headers1)
    assert res1.status_code == 200
    assert res1.json()["theme"] == "dark"
    assert res1.json()["timezone"] == "Asia/Kolkata"


def test_notification_preference_suppression(client: TestClient, db: Session):
    """Verify that disabling a notification preference suppresses in-app notifications without affecting audit logs."""
    # Register user
    headers, user_id = get_user_headers(client, "grace_notif", "Grace Notif")

    # Disable assignment and reminder notifications
    client.patch(
        "/api/v1/settings",
        headers=headers,
        json={"notify_task_assigned": False, "notify_reminder_due": False},
    )

    # Create client & workflow
    c_res = client.post("/api/v1/clients", headers=headers, json={"name": "Notif Client"})
    client_id = c_res.json()["id"]
    w_res = client.post("/api/v1/workflows", headers=headers, json={"name": "Notif Workflow"})
    workflow_id = w_res.json()["id"]

    # 1. Create a task assigned to Grace
    t_res = client.post(
        "/api/v1/tasks",
        headers=headers,
        json={
            "title": "Suppressed Assignment Task",
            "client_id": client_id,
            "workflow_id": workflow_id,
            "assigned_user_id": user_id,
        },
    )
    assert t_res.status_code == 201
    task_id = t_res.json()["id"]

    # Check Grace's notifications - notify_task_assigned was False, so no notification created!
    notifs, total, unread = get_user_notifications(db, user_id=db.get(User, user_id).id)
    assert not any(n.type == "task_assigned" for n in notifs)

    # 2. Create due reminder for this task
    now = datetime.now(timezone.utc)
    create_reminder(
        db,
        task_id=db.get(Task, task_id).id,
        remind_at=now,
        message="Urgent Reminder",
    )

    # Evaluate due notifications
    eval_count = evaluate_due_notifications(db, as_of=now)
    # The reminder is evaluated, but since notify_reminder_due is False, no alert was added
    notifs_after, _, _ = get_user_notifications(db, user_id=db.get(User, user_id).id)
    assert not any(n.type == "reminder_due" for n in notifs_after)

    # 3. But Task History audit trail IS preserved!
    hist_res = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers)
    assert hist_res.status_code == 200
    histories = hist_res.json()
    assert isinstance(histories, list)
    assert len(histories) >= 1  # created/assigned is logged in history
