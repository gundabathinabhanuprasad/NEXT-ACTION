"""Phase 12 backend tests for Notifications, Alerts & Smart Attention System."""

from datetime import datetime, timedelta, timezone
import uuid
from fastapi.testclient import TestClient
import pytest
from sqlalchemy.orm import Session
from app.core.security import create_access_token
from app.db import SessionLocal
from app.main import app
from app.models.enums import TaskPriority, TaskStatus
from app.models.notification import Notification
from app.models.task import Task
from app.services.auth_service import register_user
from app.services.exceptions import NotificationNotFoundError
from app.services.follow_up_service import create_follow_up
from app.services.notification_service import (
    create_notification,
    evaluate_due_notifications,
    get_notification,
    get_unread_count,
    get_user_notifications,
    mark_all_as_read,
    mark_as_read,
)
from app.services.reminder_service import create_reminder
from app.services.task_service import (
    assign_task,
    complete_task,
    create_task,
    record_attempt,
    reopen_task,
)

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


# =========================================================================
# 1. Security & Authentication Tests
# =========================================================================

def test_unauthenticated_notification_endpoints_rejected():
    """Verify that unauthenticated requests to notification APIs return HTTP 401."""
    resp = client.get("/api/v1/notifications")
    assert resp.status_code == 401

    resp = client.get("/api/v1/notifications/unread-count")
    assert resp.status_code == 401

    resp = client.post(f"/api/v1/notifications/{uuid.uuid4()}/read")
    assert resp.status_code == 401

    resp = client.post("/api/v1/notifications/read-all")
    assert resp.status_code == 401

    resp = client.get(f"/api/v1/notifications/{uuid.uuid4()}")
    assert resp.status_code == 401

    resp = client.post("/api/v1/notifications/evaluate")
    assert resp.status_code == 401


def test_user_can_list_own_notifications(db: Session):
    """Authenticated user can list their own notifications, with correct pagination and counts."""
    user = register_user(db, "Alice Notif", f"alice_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    token, _ = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    # Create notifications for Alice
    n1 = create_notification(db, user.id, "task_assigned", "Task Assigned", "You were assigned a task")
    n2 = create_notification(db, user.id, "reminder_due", "Reminder Due", "Your reminder is due")

    resp = client.get("/api/v1/notifications", headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert data["total"] == 2
    assert data["unread_count"] == 2
    assert len(data["items"]) == 2
    ids = [item["id"] for item in data["items"]]
    assert str(n1.id) in ids
    assert str(n2.id) in ids


def test_user_cannot_access_or_read_another_users_notification(db: Session):
    """CRITICAL SECURITY TEST: User A must never access or view User B's notifications."""
    user_a = register_user(db, "User A", f"usera_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user_b = register_user(db, "User B", f"userb_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    token_a, _ = create_access_token(subject=str(user_a.id))
    token_b, _ = create_access_token(subject=str(user_b.id))
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    # Create private notification for User B
    notif_b = create_notification(db, user_b.id, "task_assigned", "Private for B", "Secret message for B")

    # User A tries to list notifications — must NOT see User B's notification
    resp_a_list = client.get("/api/v1/notifications", headers=headers_a)
    assert resp_a_list.status_code == 200
    items_a = resp_a_list.json()["items"]
    assert all(item["id"] != str(notif_b.id) for item in items_a)

    # User A tries to get User B's notification by ID directly — must return 404 NOT FOUND (no leak)
    resp_a_get = client.get(f"/api/v1/notifications/{notif_b.id}", headers=headers_a)
    assert resp_a_get.status_code == 404

    # Service-level check raises NotificationNotFoundError
    with pytest.raises(NotificationNotFoundError):
        get_notification(db, user_id=user_a.id, notification_id=notif_b.id)


def test_user_cannot_mark_another_users_notification_as_read(db: Session):
    """CRITICAL SECURITY TEST: User A cannot mark User B's notification as read."""
    user_a = register_user(db, "User A2", f"usera2_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user_b = register_user(db, "User B2", f"userb2_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    token_a, _ = create_access_token(subject=str(user_a.id))
    token_b, _ = create_access_token(subject=str(user_b.id))
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    notif_b = create_notification(db, user_b.id, "reminder_due", "B Reminder", "Message for B")
    assert notif_b.is_read is False

    # User A attempts to mark User B's notification as read
    resp_mark = client.post(f"/api/v1/notifications/{notif_b.id}/read", headers=headers_a)
    assert resp_mark.status_code == 404

    # Ensure notification remains unread for User B
    db.refresh(notif_b)
    assert notif_b.is_read is False

    # User B can mark it read
    resp_mark_b = client.post(f"/api/v1/notifications/{notif_b.id}/read", headers=headers_b)
    assert resp_mark_b.status_code == 200
    assert resp_mark_b.json()["is_read"] is True


def test_bulk_mark_all_read_isolation(db: Session):
    """Mark all read operates strictly within the authenticated user's scope."""
    user_a = register_user(db, "User A3", f"usera3_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user_b = register_user(db, "User B3", f"userb3_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    token_a, _ = create_access_token(subject=str(user_a.id))
    headers_a = {"Authorization": f"Bearer {token_a}"}

    notif_a1 = create_notification(db, user_a.id, "task_assigned", "A1", "Msg A1")
    notif_a2 = create_notification(db, user_a.id, "task_assigned", "A2", "Msg A2")
    notif_b = create_notification(db, user_b.id, "task_assigned", "B1", "Msg B1")

    # User A calls mark-all-read
    resp = client.post("/api/v1/notifications/read-all", headers=headers_a)
    assert resp.status_code == 200
    assert resp.json()["unread_count"] == 0

    db.refresh(notif_a1)
    db.refresh(notif_a2)
    db.refresh(notif_b)

    assert notif_a1.is_read is True
    assert notif_a2.is_read is True
    # User B's notification MUST remain unread!
    assert notif_b.is_read is False


def test_unread_count_is_user_specific(db: Session):
    """Unread count returns correct values strictly per user."""
    user_a = register_user(db, "User A4", f"usera4_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user_b = register_user(db, "User B4", f"userb4_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    token_a, _ = create_access_token(subject=str(user_a.id))
    token_b, _ = create_access_token(subject=str(user_b.id))
    headers_a = {"Authorization": f"Bearer {token_a}"}
    headers_b = {"Authorization": f"Bearer {token_b}"}

    create_notification(db, user_a.id, "type1", "T1", "M1")
    create_notification(db, user_a.id, "type2", "T2", "M2")
    create_notification(db, user_b.id, "type3", "T3", "M3")

    resp_a = client.get("/api/v1/notifications/unread-count", headers=headers_a)
    assert resp_a.status_code == 200
    assert resp_a.json()["unread_count"] == 2

    resp_b = client.get("/api/v1/notifications/unread-count", headers=headers_b)
    assert resp_b.status_code == 200
    assert resp_b.json()["unread_count"] == 1


# =========================================================================
# 2. Domain Event Generation Tests
# =========================================================================

def test_task_creation_assignment_generates_notification(db: Session):
    """Assigning a user during task creation creates an in-app notification for the assignee."""
    assignee = register_user(db, "Assignee 1", f"as1_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    creator = register_user(db, "Creator 1", f"cr1_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    task = create_task(
        db=db,
        title="Implement Push Engine",
        assigned_user_id=assignee.id,
        created_by_user_id=creator.id,
    )

    notifications, total, unread = get_user_notifications(db, user_id=assignee.id)
    assert total == 1
    assert notifications[0].type == "task_assigned"
    assert notifications[0].task_id == task.id
    assert "Implement Push Engine" in notifications[0].title


def test_task_reassignment_generates_notification(db: Session):
    """Reassigning a task to a different user creates a task_reassigned notification."""
    user1 = register_user(db, "User One", f"u1_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    user2 = register_user(db, "User Two", f"u2_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    actor = register_user(db, "Manager", f"mgr_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    task = create_task(db=db, title="Review Architecture", assigned_user_id=user1.id, created_by_user_id=actor.id)

    # Reassign to user2
    assign_task(db=db, task_id=task.id, assigned_user_id=user2.id, assigned_by_user_id=actor.id)

    notifications_u2, total_u2, _ = get_user_notifications(db, user_id=user2.id)
    assert total_u2 == 1
    assert notifications_u2[0].type == "task_reassigned"
    assert "Review Architecture" in notifications_u2[0].title


def test_task_completion_and_reopen_notifications(db: Session):
    """Completing or reopening a task creates notification for the assignee when actor is someone else."""
    assignee = register_user(db, "Worker", f"w_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    lead = register_user(db, "Tech Lead", f"lead_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    task = create_task(db=db, title="Write Docs", assigned_user_id=assignee.id, created_by_user_id=assignee.id)

    # Lead completes the task
    complete_task(db=db, task_id=task.id, user_id=lead.id)

    notifs, _, _ = get_user_notifications(db, user_id=assignee.id)
    comp_notifs = [n for n in notifs if n.type == "task_completed"]
    assert len(comp_notifs) == 1
    assert "Write Docs" in comp_notifs[0].title

    # Lead reopens the task
    reopen_task(db=db, task_id=task.id, reason="Missing section 4", user_id=lead.id)

    notifs2, _, _ = get_user_notifications(db, user_id=assignee.id)
    reopen_notifs = [n for n in notifs2 if n.type == "task_reopened"]
    assert len(reopen_notifs) == 1
    assert "Missing section 4" in reopen_notifs[0].message


def test_attempt_limit_reached_notification(db: Session):
    """Reaching max attempts generates an attempt_limit_reached notification."""
    assignee = register_user(db, "Agent", f"agent_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    task = create_task(db=db, title="Deploy Release", assigned_user_id=assignee.id, max_attempts=2)

    # Attempt 1
    record_attempt(db=db, task_id=task.id, user_id=assignee.id, notes="First try failed")
    notifs, _, _ = get_user_notifications(db, user_id=assignee.id)
    assert not any(n.type == "attempt_limit_reached" for n in notifs)

    # Attempt 2 (reaches max_attempts)
    record_attempt(db=db, task_id=task.id, user_id=assignee.id, notes="Second try failed")
    notifs2, _, _ = get_user_notifications(db, user_id=assignee.id)
    attempt_notifs = [n for n in notifs2 if n.type == "attempt_limit_reached"]
    assert len(attempt_notifs) == 1
    assert "Max Attempts Reached" in attempt_notifs[0].title


# =========================================================================
# 3. Duplicate Prevention Tests
# =========================================================================

def test_duplicate_prevention_with_dedup_key(db: Session):
    """Creating a notification with an identical dedup_key returns existing without creating duplicate."""
    user = register_user(db, "Dedup User", f"dedup_{uuid.uuid4().hex[:6]}@example.com", "Password123!")

    dedup = "custom_event_key_123"
    n1 = create_notification(db, user.id, "typeA", "Title A", "Message A", dedup_key=dedup)
    n2 = create_notification(db, user.id, "typeA", "Title A", "Message A", dedup_key=dedup)

    assert n1.id == n2.id
    count = get_unread_count(db, user.id)
    assert count == 1


# =========================================================================
# 4. Due / Overdue Evaluation Tests
# =========================================================================

def test_evaluation_generates_notifications_and_prevents_duplicates(db: Session):
    """Evaluation scans due reminders, follow-ups, next-actions, and overdue tasks."""
    user = register_user(db, "Eval User", f"eval_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    token, _ = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}

    past_time = datetime.now(timezone.utc) - timedelta(hours=2)

    # 1. Task with due reminder
    task1 = create_task(db=db, title="Task with Due Reminder", assigned_user_id=user.id)
    create_reminder(db=db, task_id=task1.id, remind_at=past_time, message="Reminder is past due!")

    # 2. Task with due follow-up
    task2 = create_task(db=db, title="Task with Due FollowUp", assigned_user_id=user.id)
    create_follow_up(db=db, task_id=task2.id, scheduled_at=past_time, notes="Follow up on feedback")

    # 3. Task with next action date in the past
    task3 = create_task(db=db, title="Task with Past Next Action", assigned_user_id=user.id, next_action_date=past_time)

    # 4. Overdue task
    task4 = create_task(db=db, title="Task that is Overdue", assigned_user_id=user.id, due_date=past_time)

    # Run evaluation via REST endpoint
    resp = client.post("/api/v1/notifications/evaluate", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["created_count"] >= 4

    # Verify notifications were created for user
    notifs, total, unread = get_user_notifications(db, user_id=user.id)
    types = [n.type for n in notifs]
    assert "reminder_due" in types
    assert "follow_up_due" in types
    assert "next_action_due" in types
    assert "task_overdue" in types

    # Running evaluation a second time should create 0 duplicates!
    resp_again = client.post("/api/v1/notifications/evaluate", headers=headers)
    assert resp_again.status_code == 200
    assert resp_again.json()["created_count"] == 0


def test_task_deletion_preserves_notifications(db: Session):
    """Deleting a task does not delete the notification (task_id is safely SET NULL)."""
    user = register_user(db, "Delete Test User", f"del_{uuid.uuid4().hex[:6]}@example.com", "Password123!")
    task = create_task(db=db, title="Temporary Task", assigned_user_id=user.id)

    notif = create_notification(
        db=db,
        user_id=user.id,
        type="task_assigned",
        title="Assigned to Temporary",
        message="Message",
        task_id=task.id,
    )

    # Delete task
    db.delete(task)
    db.commit()

    # Notification must survive with task_id set to None
    db.refresh(notif)
    assert notif.task_id is None

    # User can still retrieve notification without errors
    fetched = get_notification(db, user_id=user.id, notification_id=notif.id)
    assert fetched.id == notif.id
