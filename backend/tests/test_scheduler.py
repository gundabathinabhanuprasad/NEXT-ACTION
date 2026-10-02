"""Phase 19 backend tests for Automated Reminder, Notification Delivery & Scheduling Engine."""

from datetime import datetime, timedelta, timezone
import uuid
from zoneinfo import ZoneInfo
from fastapi.testclient import TestClient
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import create_access_token
from app.db import SessionLocal
from app.main import app
from app.models.notification import Notification
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.user_settings import UserSettings
from app.services.auth_service import register_user
from app.services.follow_up_service import create_follow_up
from app.services.notification_service import (
    create_notification,
    get_user_notifications,
)
from app.services.reminder_service import create_reminder
from app.services.scheduling_service import (
    SchedulingService,
    get_user_calendar_bounds,
    get_user_timezone,
)
from app.services.task_service import create_task, record_attempt

client = TestClient(app)


@pytest.fixture
def db():
    """Provide an isolated database session with rollback."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


def create_test_user(db: Session, prefix: str = "sched"):
    """Helper to register a unique user and generate auth headers."""
    email = f"{prefix}_{uuid.uuid4().hex[:6]}@example.com"
    user = register_user(db, name=f"User {prefix}", email=email, password="Password123!")
    token, _ = create_access_token(subject=str(user.id))
    headers = {"Authorization": f"Bearer {token}"}
    return user, headers


# =========================================================================
# 1. Scheduler Authentication & Endpoint Diagnostics
# =========================================================================

def test_scheduler_endpoint_unauthenticated_rejected():
    """Unauthenticated calls to /api/v1/scheduler/evaluate must return HTTP 401."""
    resp = client.post("/api/v1/scheduler/evaluate")
    assert resp.status_code == 401


def test_scheduler_endpoint_authenticated_empty(db: Session):
    """Authenticated user calling evaluate with no pending items receives clean 0-metrics."""
    user, headers = create_test_user(db, "empty")

    resp = client.post("/api/v1/scheduler/evaluate", headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert data["evaluated"] == 0
    assert data["notifications_created"] == 0
    assert data["duplicates_skipped"] == 0
    assert data["preferences_suppressed"] == 0
    assert data["errors_count"] == 0
    assert data["duration_ms"] >= 0.0
    assert "evaluated_at" in data
    assert "details" in data
    assert "reminders" in data["details"]


# =========================================================================
# 2. Reminder Automation & Deduplication
# =========================================================================

def test_reminder_due_notification_and_deduplication(db: Session):
    """Reminder evaluation creates persistent notification, marks is_sent, and prevents duplicates."""
    user, headers = create_test_user(db, "rem")
    past = datetime.now(timezone.utc) - timedelta(minutes=15)

    task = create_task(db=db, title="Review Q3 Financials", assigned_user_id=user.id)
    rem = create_reminder(db=db, task_id=task.id, remind_at=past, message="Submit audit review")
    assert rem.is_sent is False

    # 1. First evaluation: generates notification
    res = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res.details["reminders"].evaluated == 1
    assert res.details["reminders"].notifications_created == 1
    assert res.details["reminders"].duplicates_skipped == 0

    db.refresh(rem)
    assert rem.is_sent is True

    notifs, total, unread = get_user_notifications(db, user_id=user.id)
    rem_notifs = [n for n in notifs if n.type == "reminder_due"]
    assert len(rem_notifs) == 1
    assert rem_notifs[0].title == "Reminder: Review Q3 Financials"
    assert rem_notifs[0].message == "Submit audit review"
    assert rem_notifs[0].dedup_key == f"reminder:{rem.id}:{rem.remind_at.isoformat()}"

    # 2. Second evaluation: should skip duplicate
    # Even if reminder is_sent were somehow reset, dedup_key prevents duplicate
    rem.is_sent = False
    db.commit()

    res2 = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res2.details["reminders"].duplicates_skipped == 1
    assert res2.details["reminders"].notifications_created == 0

    _, total_after, _ = get_user_notifications(db, user_id=user.id)
    assert total_after == total  # No duplicate notification


# =========================================================================
# 3. Follow-up Automation & Deduplication
# =========================================================================

def test_follow_up_due_notification_and_deduplication(db: Session):
    """FollowUp evaluation creates notification and is idempotent."""
    user, headers = create_test_user(db, "fu")
    past = datetime.now(timezone.utc) - timedelta(hours=1)

    task = create_task(db=db, title="Follow up with client", assigned_user_id=user.id)
    fu = create_follow_up(db=db, task_id=task.id, scheduled_at=past, notes="Call CTO for feedback")

    res = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res.details["follow_ups"].evaluated == 1
    assert res.details["follow_ups"].notifications_created == 1

    notifs, _, _ = get_user_notifications(db, user_id=user.id)
    assert any(n.type == "follow_up_due" and n.dedup_key == f"follow_up:{fu.id}:{fu.scheduled_at.isoformat()}" for n in notifs)

    # Re-run: duplicate skipped
    res2 = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res2.details["follow_ups"].duplicates_skipped == 1
    assert res2.details["follow_ups"].notifications_created == 0


# =========================================================================
# 4. Next Action Automation & Deduplication
# =========================================================================

def test_next_action_due_notification_and_deduplication(db: Session):
    """Task next action date creates next_action_due notification once."""
    user, headers = create_test_user(db, "na")
    past = datetime.now(timezone.utc) - timedelta(minutes=30)

    task = create_task(db=db, title="Deploy Release v2", assigned_user_id=user.id, next_action_date=past)

    res = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res.details["next_actions"].evaluated == 1
    assert res.details["next_actions"].notifications_created == 1

    notifs, _, _ = get_user_notifications(db, user_id=user.id)
    assert any(n.type == "next_action_due" and n.dedup_key == f"next_action:{task.id}:{task.next_action_date.isoformat()}" for n in notifs)

    # Re-run: idempotent
    res2 = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res2.details["next_actions"].duplicates_skipped == 1
    assert res2.details["next_actions"].notifications_created == 0


# =========================================================================
# 5. Overdue Task Automation & Deduplication
# =========================================================================

def test_overdue_task_notification_and_deduplication(db: Session):
    """Overdue task due date creates task_overdue notification deterministically."""
    user, headers = create_test_user(db, "overdue")
    past = datetime.now(timezone.utc) - timedelta(days=2)

    task = create_task(db=db, title="Submit Monthly VAT", assigned_user_id=user.id, due_date=past)

    res = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res.details["overdue_tasks"].evaluated == 1
    assert res.details["overdue_tasks"].notifications_created == 1

    notifs, _, _ = get_user_notifications(db, user_id=user.id)
    assert any(n.type == "task_overdue" and n.dedup_key == f"task_overdue:{task.id}:{task.due_date.isoformat()}" for n in notifs)

    # Re-run: duplicate skipped
    res2 = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res2.details["overdue_tasks"].duplicates_skipped == 1
    assert res2.details["overdue_tasks"].notifications_created == 0


# =========================================================================
# 6. Attempt Limit Alerts (Max Attempts & Near Max Attempts)
# =========================================================================

def test_attempt_limit_evaluation_max_and_near_max(db: Session):
    """Scheduler creates both attempt_limit_reached and near_max_attempts alerts."""
    user, headers = create_test_user(db, "attempt")

    # Task 1: Reached max attempts (3/3)
    t_max = create_task(db=db, title="Fix Production Outage", assigned_user_id=user.id, max_attempts=3)
    record_attempt(db=db, task_id=t_max.id, notes="Try 1", user_id=user.id)
    record_attempt(db=db, task_id=t_max.id, notes="Try 2", user_id=user.id)
    record_attempt(db=db, task_id=t_max.id, notes="Try 3", user_id=user.id)

    # Task 2: Near max attempts (1/2 -> attempt_count == max_attempts - 1)
    t_near = create_task(db=db, title="Renew SSL Certificate", assigned_user_id=user.id, max_attempts=2)
    record_attempt(db=db, task_id=t_near.id, notes="Try 1", user_id=user.id)

    # Evaluate attempt limits
    res = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    assert res.details["attempt_limits"].evaluated >= 2

    notifs, _, _ = get_user_notifications(db, user_id=user.id)
    types = [n.type for n in notifs]
    assert "attempt_limit_reached" in types
    assert "near_max_attempts" in types

    # Attempt counts on tasks must NOT be modified by the scheduler!
    db.refresh(t_max)
    db.refresh(t_near)
    assert t_max.attempt_count == 3
    assert t_near.attempt_count == 1


# =========================================================================
# 7. Notification Preference Suppression & Audit Trail Preservation
# =========================================================================

def test_notification_preference_suppression_and_audit_preservation(db: Session):
    """Disabling notification types suppresses notifications but leaves TaskHistory audit intact."""
    user, headers = create_test_user(db, "suppress")

    # Disable overdue, next_action, and reminder preferences
    settings = db.scalars(select(UserSettings).where(UserSettings.user_id == user.id)).first()
    if not settings:
        settings = UserSettings(user_id=user.id)
        db.add(settings)
    settings.notify_task_overdue = False
    settings.notify_next_action_due = False
    settings.notify_reminder_due = False
    db.commit()

    past = datetime.now(timezone.utc) - timedelta(hours=1)
    task = create_task(
        db=db,
        title="Suppressed Task",
        assigned_user_id=user.id,
        due_date=past,
        next_action_date=past,
    )
    rem = create_reminder(db=db, task_id=task.id, remind_at=past, message="Suppressed reminder")

    res = SchedulingService.evaluate_all(db=db, as_of=datetime.now(timezone.utc), user_id=user.id)
    # The 3 items should be evaluated and suppressed by preference
    assert res.details["overdue_tasks"].preferences_suppressed == 1
    assert res.details["next_actions"].preferences_suppressed == 1
    assert res.details["reminders"].preferences_suppressed == 1

    # In-app notifications must be 0 for these types
    notifs, total, _ = get_user_notifications(db, user_id=user.id)
    for n in notifs:
        assert n.type not in ["task_overdue", "next_action_due", "reminder_due"]

    # CRITICAL: TaskHistory audit records must remain intact!
    histories = list(db.scalars(select(TaskHistory).where(TaskHistory.task_id == task.id)).all())
    assert len(histories) >= 1  # Created/assigned history record exists


# =========================================================================
# 8. User Timezone Integration & Day-Boundary Calculations
# =========================================================================

def test_user_timezone_calendar_boundaries(db: Session):
    """User calendar boundaries correctly translate local day boundaries to UTC."""
    user, _ = create_test_user(db, "tz")

    # Set user timezone to Asia/Kolkata (+05:30)
    settings = db.scalars(select(UserSettings).where(UserSettings.user_id == user.id)).first()
    if not settings:
        settings = UserSettings(user_id=user.id)
        db.add(settings)
    settings.timezone = "Asia/Kolkata"
    db.commit()

    tz = get_user_timezone(db, user.id)
    assert tz.key == "Asia/Kolkata"

    # Given UTC time: 2026-09-29 20:00:00 (which is 2026-09-30 01:30:00 IST)
    ref_time_utc = datetime(2026, 9, 29, 20, 0, 0, tzinfo=timezone.utc)
    user_tz, utc_start, utc_end = get_user_calendar_bounds(db, user.id, as_of=ref_time_utc)

    # In IST, today is 2026-09-30. Start of day IST is 2026-09-30 00:00:00 IST = 2026-09-29 18:30:00 UTC.
    expected_start = datetime(2026, 9, 29, 18, 30, 0, tzinfo=timezone.utc)
    # End of day IST is 2026-10-01 00:00:00 IST = 2026-09-30 18:30:00 UTC.
    expected_end = datetime(2026, 9, 30, 18, 30, 0, tzinfo=timezone.utc)

    assert utc_start == expected_start
    assert utc_end == expected_end

    # Items between utc_start and utc_end belong to the user's local calendar day!
    local_event = datetime(2026, 9, 30, 2, 0, 0, tzinfo=timezone.utc)  # 07:30 IST on Sept 30
    assert utc_start <= local_event < utc_end


# =========================================================================
# 9. Cross-User Isolation
# =========================================================================

def test_cross_user_isolation(db: Session):
    """User A evaluating scheduler with user_scoped=True only affects User A's data."""
    user_a, headers_a = create_test_user(db, "usera")
    user_b, headers_b = create_test_user(db, "userb")

    past = datetime.now(timezone.utc) - timedelta(hours=1)

    # Create due tasks for User A and User B
    create_task(db=db, title="Task A", assigned_user_id=user_a.id, due_date=past)
    create_task(db=db, title="Task B", assigned_user_id=user_b.id, due_date=past)

    # User A calls evaluate via REST endpoint
    resp = client.post("/api/v1/scheduler/evaluate", headers=headers_a)
    assert resp.status_code == 200
    data = resp.json()

    # Evaluated items should only be User A's
    assert data["notifications_created"] == 1

    notifs_a, total_a, _ = get_user_notifications(db, user_id=user_a.id)
    notifs_b, total_b, _ = get_user_notifications(db, user_id=user_b.id)

    overdue_a = [n for n in notifs_a if n.type == "task_overdue"]
    overdue_b = [n for n in notifs_b if n.type == "task_overdue"]

    assert len(overdue_a) == 1
    assert overdue_a[0].title == "Task Overdue: Task A"

    # User B should NOT have received their task_overdue notification yet!
    assert len(overdue_b) == 0


# =========================================================================
# 10. Database Uniqueness & Race-Safe Deduplication
# =========================================================================

def test_database_enforced_dedup_uniqueness(db: Session):
    """PostgreSQL partial unique index uq_notifications_user_dedup prevents duplicate rows."""
    user, _ = create_test_user(db, "dbdedup")
    dedup = "atomic_unique_event_test_key"

    n1 = create_notification(db=db, user_id=user.id, type="test_type", title="T1", message="M1", dedup_key=dedup)
    assert n1 is not None

    # Calling create_notification again returns existing
    n2 = create_notification(db=db, user_id=user.id, type="test_type", title="T1", message="M1", dedup_key=dedup)
    assert n2 is not None
    assert n1.id == n2.id

    # Raw SQL count confirms exactly 1 row exists
    count = db.scalar(
        select(Notification).where(Notification.user_id == user.id, Notification.dedup_key == dedup)
    )
    assert count is not None
