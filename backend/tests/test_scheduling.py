"""Phase 11 backend tests for Reminders, Follow-Ups, and Action Scheduling."""

from datetime import datetime, timedelta, timezone
import uuid
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.models.enums import TaskPriority, TaskStatus
from app.models.reminder import Reminder
from app.models.follow_up import FollowUp
from app.services.reminder_service import (
    create_reminder,
    delete_reminder,
    get_reminder,
    list_due_reminders,
    list_reminders,
    list_task_reminders,
    process_reminder,
)
from app.services.follow_up_service import (
    complete_follow_up,
    create_follow_up,
    delete_follow_up,
    get_follow_up,
    list_follow_ups,
    list_task_follow_ups,
)
from app.services.task_service import create_task, get_task, get_task_history, update_next_action_date

client = TestClient(app)


# =========================================================================
# 1-5. Reminder Service & Invariant Tests
# =========================================================================

def test_reminder_creation_retrieval_and_listing(db):
    """Verify creating, getting, and listing reminders with filters."""
    task = create_task(db=db, title="Task with Reminders")
    task2 = create_task(db=db, title="Second Task")

    remind_time = datetime.now(timezone.utc) + timedelta(hours=2)
    rem1 = create_reminder(db=db, task_id=task.id, remind_at=remind_time, message="Reminder 1")
    rem2 = create_reminder(db=db, task_id=task.id, remind_at=remind_time + timedelta(hours=1), message="Reminder 2")
    rem3 = create_reminder(db=db, task_id=task2.id, remind_at=remind_time, message="Reminder 3")

    # Get single
    fetched = get_reminder(db=db, reminder_id=rem1.id)
    assert fetched.id == rem1.id
    assert fetched.message == "Reminder 1"
    assert fetched.is_sent is False

    # List all
    all_rems = list_reminders(db=db)
    rem_ids = [r.id for r in all_rems]
    assert rem1.id in rem_ids
    assert rem2.id in rem_ids
    assert rem3.id in rem_ids

    # List by task
    task1_rems = list_task_reminders(db=db, task_id=task.id)
    assert len(task1_rems) == 2
    assert rem3.id not in [r.id for r in task1_rems]

    # Process rem1
    process_reminder(db=db, reminder_id=rem1.id)
    sent_rems = list_reminders(db=db, is_sent=True)
    assert rem1.id in [r.id for r in sent_rems]
    assert rem2.id not in [r.id for r in sent_rems]

    # Unsent rems
    unsent_rems = list_reminders(db=db, is_sent=False)
    assert rem1.id not in [r.id for r in unsent_rems]
    assert rem2.id in [r.id for r in unsent_rems]


def test_reminder_send_and_invariant(db):
    """CRITICAL INVARIANT: Creating and sending reminders must NEVER alter task attempt_count or status."""
    task = create_task(db=db, title="Reminder Invariant Task", max_attempts=3)
    initial_attempts = task.attempt_count
    initial_status = task.status

    # Create reminder
    rem = create_reminder(
        db=db,
        task_id=task.id,
        remind_at=datetime.now(timezone.utc) + timedelta(minutes=30),
        message="Follow-up ping",
    )
    db.refresh(task)
    assert task.attempt_count == initial_attempts
    assert task.status == initial_status

    # Send reminder
    sent = process_reminder(db=db, reminder_id=rem.id)
    assert sent.is_sent is True

    db.refresh(task)
    assert task.attempt_count == initial_attempts
    assert task.max_attempts == 3
    assert task.status == initial_status


def test_reminder_deletion(db):
    """Verify deleting a reminder removes it cleanly."""
    task = create_task(db=db, title="Task for Deletion")
    rem = create_reminder(
        db=db,
        task_id=task.id,
        remind_at=datetime.now(timezone.utc) + timedelta(hours=1),
        message="To be deleted",
    )
    rem_id = rem.id
    delete_reminder(db=db, reminder_id=rem_id)

    with pytest.raises(Exception):
        get_reminder(db=db, reminder_id=rem_id)


# =========================================================================
# 6-11. Follow-Up Service & Invariant Tests
# =========================================================================

def test_follow_up_lifecycle_and_listing(db):
    """Verify follow-up creation, retrieval, listing, completion, and deletion."""
    task = create_task(db=db, title="Follow-up Lifecycle Task")
    scheduled = datetime.now(timezone.utc) + timedelta(days=2)

    fu1 = create_follow_up(db=db, task_id=task.id, scheduled_at=scheduled, notes="Call client manager")
    fu2 = create_follow_up(db=db, task_id=task.id, scheduled_at=scheduled + timedelta(days=1), notes="Send invoice")

    # Get single
    fetched = get_follow_up(db=db, follow_up_id=fu1.id)
    assert fetched.id == fu1.id
    assert fetched.notes == "Call client manager"
    assert fetched.completed_at is None

    # List by task
    task_fus = list_task_follow_ups(db=db, task_id=task.id)
    assert len(task_fus) == 2

    # Complete fu1
    comp_time = datetime.now(timezone.utc)
    completed = complete_follow_up(db=db, follow_up_id=fu1.id, completed_at=comp_time, notes="Completed: Call made")
    assert completed.completed_at is not None
    assert completed.notes == "Completed: Call made"

    # Filter is_completed
    completed_list = list_follow_ups(db=db, is_completed=True)
    assert fu1.id in [f.id for f in completed_list]
    assert fu2.id not in [f.id for f in completed_list]

    pending_list = list_follow_ups(db=db, is_completed=False)
    assert fu2.id in [f.id for f in pending_list]
    assert fu1.id not in [f.id for f in pending_list]

    # Delete fu2
    fu2_id = fu2.id
    delete_follow_up(db=db, follow_up_id=fu2_id)
    with pytest.raises(Exception):
        get_follow_up(db=db, follow_up_id=fu2_id)


def test_follow_up_invariant_task_preserved(db):
    """CRITICAL INVARIANT: Creating and completing follow-ups must NOT change task attempt_count or auto-complete task."""
    task = create_task(db=db, title="Follow-up Invariant Task", max_attempts=4)
    initial_attempts = task.attempt_count
    initial_status = task.status

    fu = create_follow_up(
        db=db,
        task_id=task.id,
        scheduled_at=datetime.now(timezone.utc) + timedelta(days=1),
        notes="Pre-meeting check",
    )
    db.refresh(task)
    assert task.attempt_count == initial_attempts
    assert task.status == initial_status

    complete_follow_up(db=db, follow_up_id=fu.id)
    db.refresh(task)
    assert task.attempt_count == initial_attempts
    assert task.status == initial_status
    assert task.status != TaskStatus.COMPLETED


# =========================================================================
# 12-14. Next Action Scheduling & API Tests
# =========================================================================

def test_next_action_scheduling_and_audit(db):
    """Verify updating next action date updates the task and logs audit history."""
    task = create_task(db=db, title="Next Action Scheduling Task")
    assert task.next_action_date is None

    action_date = datetime.now(timezone.utc) + timedelta(days=3)
    updated = update_next_action_date(db=db, task_id=task.id, next_action_date=action_date)
    assert updated.next_action_date == action_date

    histories = get_task_history(db=db, task_id=task.id)
    action_events = [h for h in histories if h.action == "next_action_date_changed"]
    assert len(action_events) >= 1
    assert action_events[-1].new_value == action_date.isoformat()


def test_api_scheduling_endpoints(auth_headers):
    """Test full HTTP API for Reminders, Follow-Ups, and Next Actions."""
    headers, user = auth_headers

    # 1. Create task
    task_res = client.post("/api/v1/tasks", json={"title": "E2E Scheduling Task"}, headers=headers)
    assert task_res.status_code == 201
    task_id = task_res.json()["id"]

    # 2. Next Action Date update via API
    next_date = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
    na_res = client.post(f"/api/v1/tasks/{task_id}/next-action", json={"next_action_date": next_date}, headers=headers)
    assert na_res.status_code == 200
    assert na_res.json()["next_action_date"] is not None

    # Filter tasks by has_next_action
    tasks_with_na = client.get("/api/v1/tasks?has_next_action=true", headers=headers)
    assert tasks_with_na.status_code == 200
    assert task_id in [t["id"] for t in tasks_with_na.json()["items"]]

    # 3. Create Reminder via API
    rem_date = (datetime.now(timezone.utc) + timedelta(hours=4)).isoformat()
    rem_res = client.post(
        "/api/v1/reminders",
        json={"task_id": task_id, "remind_at": rem_date, "message": "API Reminder Test"},
        headers=headers,
    )
    assert rem_res.status_code == 201
    reminder_id = rem_res.json()["id"]
    assert rem_res.json()["is_sent"] is False

    # List Reminders via GET /api/v1/reminders
    rems_list_res = client.get("/api/v1/reminders", headers=headers)
    assert rems_list_res.status_code == 200
    assert reminder_id in [r["id"] for r in rems_list_res.json()]

    # Filter by task
    rems_task_res = client.get(f"/api/v1/reminders?task_id={task_id}", headers=headers)
    assert rems_task_res.status_code == 200
    assert len(rems_task_res.json()) >= 1

    # Send Reminder via API
    send_res = client.post(f"/api/v1/reminders/{reminder_id}/send", headers=headers)
    assert send_res.status_code == 200
    assert send_res.json()["is_sent"] is True

    # Invariant check on Task via API
    t_check = client.get(f"/api/v1/tasks/{task_id}", headers=headers)
    assert t_check.json()["attempt_count"] == 0
    assert t_check.json()["status"] == "pending"

    # Delete Reminder via DELETE /api/v1/reminders/{id}
    del_rem_res = client.delete(f"/api/v1/reminders/{reminder_id}", headers=headers)
    assert del_rem_res.status_code == 204

    # 4. Create Follow-Up via API
    fu_date = (datetime.now(timezone.utc) + timedelta(days=5)).isoformat()
    fu_res = client.post(
        "/api/v1/follow-ups",
        json={"task_id": task_id, "scheduled_at": fu_date, "notes": "API Follow-up Test"},
        headers=headers,
    )
    assert fu_res.status_code == 201
    follow_up_id = fu_res.json()["id"]
    assert fu_res.json()["completed_at"] is None

    # List Follow-ups via GET /api/v1/follow-ups
    fus_list_res = client.get("/api/v1/follow-ups", headers=headers)
    assert fus_list_res.status_code == 200
    assert follow_up_id in [f["id"] for f in fus_list_res.json()]

    # Complete Follow-up via API
    comp_fu_res = client.post(
        f"/api/v1/follow-ups/{follow_up_id}/complete",
        json={"notes": "Follow-up completed successfully"},
        headers=headers,
    )
    assert comp_fu_res.status_code == 200
    assert comp_fu_res.json()["completed_at"] is not None

    # Invariant check: Task is still pending and attempt_count is 0
    t_check2 = client.get(f"/api/v1/tasks/{task_id}", headers=headers)
    assert t_check2.json()["attempt_count"] == 0
    assert t_check2.json()["status"] == "pending"

    # Delete Follow-Up via DELETE /api/v1/follow-ups/{id}
    del_fu_res = client.delete(f"/api/v1/follow-ups/{follow_up_id}", headers=headers)
    assert del_fu_res.status_code == 204
