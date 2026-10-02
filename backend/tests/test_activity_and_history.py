"""Phase 15 backend tests for Activity Timeline, Audit Logging, and Task History."""

from datetime import datetime, timedelta, timezone
import uuid
import pytest
from fastapi.testclient import TestClient
from app.core.security import create_access_token
from app.main import app
from app.models.enums import RecurrenceType, TaskPriority, TaskStatus
from app.models.user import User
from app.services.auth_service import register_user
from app.services.history_service import (
    get_recent_activity,
    get_task_history,
    list_activity,
    log_history,
    serialize_task_history,
)
from app.services.recurring_task_service import create_recurring_task, evaluate_recurring_tasks
from app.services.task_service import (
    assign_task,
    change_priority,
    change_status,
    complete_task,
    create_task,
    postpone_task,
    record_attempt,
    reopen_task,
    update_next_action_date,
    update_subject_line,
)
from app.services.task_template_service import create_task_from_template, create_task_template

client = TestClient(app)


def _auth_headers(user: User) -> dict:
    token, _ = create_access_token(subject=str(user.id))
    return {"Authorization": f"Bearer {token}"}


def test_unauthenticated_history_and_activity_rejected(db):
    """Unauthenticated requests to history and activity endpoints must be rejected with 401."""
    random_id = uuid.uuid4()
    resp1 = client.get(f"/api/v1/tasks/{random_id}/history")
    assert resp1.status_code == 401

    resp2 = client.get("/api/v1/activity")
    assert resp2.status_code == 401

    resp3 = client.get("/api/v1/tasks/activity/recent")
    assert resp3.status_code == 401


def test_task_history_serialization_with_actors_and_metadata(db):
    """Verify history serialization enriches records with actor names, emails, task titles, diffs, and reasons."""
    uid = uuid.uuid4().hex[:8]
    user1 = register_user(db, name="Alice Timeline", email=f"alice_{uid}@nextaction.local", password="Password123!")
    user2 = register_user(db, name="Bob Worker", email=f"bob_{uid}@nextaction.local", password="Password123!")

    # 1. Create task
    task = create_task(
        db=db,
        title="Comprehensive Audit Task",
        description="Testing complete audit logging",
        created_by_user_id=user1.id,
    )

    # 2. Priority change
    change_priority(db, task_id=task.id, new_priority=TaskPriority.URGENT, user_id=user1.id, reason="Client escalated")

    # 3. Status change
    change_status(db, task_id=task.id, new_status=TaskStatus.IN_PROGRESS, user_id=user2.id, reason="Started work")

    # 4. Assign task
    assign_task(db, task_id=task.id, assigned_user_id=user2.id, assigned_by_user_id=user1.id)

    # 5. Record attempt with override
    record_attempt(db, task_id=task.id, user_id=user2.id, notes="First call went to voicemail")

    # 6. Postpone task
    new_due = datetime.now(timezone.utc) + timedelta(days=5)
    postpone_task(db, task_id=task.id, new_due_date=new_due, reason="Waiting for client documents", user_id=user2.id)

    # 7. Update next action date
    next_action = datetime.now(timezone.utc) + timedelta(days=2)
    update_next_action_date(db, task_id=task.id, next_action_date=next_action, user_id=user2.id)

    # 8. Complete task
    complete_task(db, task_id=task.id, user_id=user2.id)

    # 9. Reopen task
    reopen_task(db, task_id=task.id, reason="Additional changes requested by stakeholder", user_id=user1.id)

    # 10. Update subject line
    update_subject_line(db, task_id=task.id, subject_line="Urgent follow-up required", user_id=user1.id)

    # Fetch history via API
    headers = _auth_headers(user1)
    resp = client.get(f"/api/v1/tasks/{task.id}/history", headers=headers)
    assert resp.status_code == 200
    history_data = resp.json()

    assert len(history_data) >= 10
    actions = [h["action"] for h in history_data]
    assert "created" in actions
    assert "priority_changed" in actions
    assert "status_changed" in actions
    assert "reassigned" in actions
    assert "attempt" in actions
    assert "postponed" in actions
    assert "next_action_date_changed" in actions
    assert "completed" in actions
    assert "reopened" in actions
    assert "subject_line_changed" in actions

    # Check actor enrichment
    postpone_entry = next(h for h in history_data if h["action"] == "postponed")
    assert postpone_entry["actor_name"] == "Bob Worker"
    assert postpone_entry["actor_email"] == f"bob_{uid}@nextaction.local"
    assert postpone_entry["task_title"] == "Comprehensive Audit Task"
    assert postpone_entry["reason"] == "Waiting for client documents"
    assert postpone_entry["new_value"] is not None

    reopen_entry = next(h for h in history_data if h["action"] == "reopened")
    assert reopen_entry["actor_name"] == "Alice Timeline"
    assert reopen_entry["actor_email"] == f"alice_{uid}@nextaction.local"
    assert reopen_entry["reason"] == "Additional changes requested by stakeholder"


def test_task_history_with_former_user_and_system_actor(db):
    """Former users (unresolvable user reference) should render as 'Former user' and None user ID should render as 'System'."""
    task = create_task(db=db, title="Task with deleted actor")

    # Action with no user (system)
    hist_sys = log_history(
        db=db,
        task_id=task.id,
        action="system_auto_cleanup",
        new_value="cleaned",
        created_by_user_id=None,
    )
    db.commit()

    # Verify system serialization
    serialized_sys = serialize_task_history(hist_sys)
    assert serialized_sys.actor_name == "System"
    assert serialized_sys.actor_email is None

    # Transient history with unresolvable/former user reference
    from app.models.task_history import TaskHistory
    former_hist = TaskHistory(
        id=uuid.uuid4(),
        task_id=task.id,
        action="legacy_action",
        created_by_user_id=uuid.uuid4(),
        created_at=datetime.now(timezone.utc),
    )
    serialized_former = serialize_task_history(former_hist)
    assert serialized_former.actor_name == "Former user"
    assert serialized_former.actor_email is None


def test_task_history_filtering_and_ordering(db):
    """Test filtering task history by action, actor, ordering, and pagination."""
    uid = uuid.uuid4().hex[:8]
    user = register_user(db, name="Filter User", email=f"filter_{uid}@nextaction.local", password="Password123!")
    headers = _auth_headers(user)

    task = create_task(db=db, title="Filtering History Task", created_by_user_id=user.id)
    change_priority(db, task_id=task.id, new_priority=TaskPriority.HIGH, user_id=user.id)
    change_status(db, task_id=task.id, new_status=TaskStatus.IN_PROGRESS, user_id=user.id)
    record_attempt(db, task_id=task.id, user_id=user.id, notes="Work attempt 1")

    # Filter by action=priority_changed
    resp_action = client.get(f"/api/v1/tasks/{task.id}/history?action=priority_changed", headers=headers)
    assert resp_action.status_code == 200
    action_items = resp_action.json()
    assert len(action_items) == 1
    assert action_items[0]["action"] == "priority_changed"

    # Filter by actor_id
    resp_actor = client.get(f"/api/v1/tasks/{task.id}/history?actor_id={user.id}", headers=headers)
    assert resp_actor.status_code == 200
    assert len(resp_actor.json()) >= 4

    # Ordering: desc
    resp_desc = client.get(f"/api/v1/tasks/{task.id}/history?order=desc", headers=headers)
    assert resp_desc.status_code == 200
    desc_items = resp_desc.json()
    assert desc_items[0]["action"] == "attempt"

    # Pagination: page=1, page_size=2
    resp_page = client.get(f"/api/v1/tasks/{task.id}/history?page=1&page_size=2", headers=headers)
    assert resp_page.status_code == 200
    assert len(resp_page.json()) == 2


def test_global_activity_endpoint_filtering_and_pagination(db):
    """Test GET /api/v1/activity pagination, filtering, and eager loading."""
    uid = uuid.uuid4().hex[:8]
    user = register_user(db, name="Global Act User", email=f"global_act_{uid}@nextaction.local", password="Password123!")
    headers = _auth_headers(user)

    task1 = create_task(db=db, title="Global Act Task 1", created_by_user_id=user.id)
    task2 = create_task(db=db, title="Global Act Task 2", created_by_user_id=user.id)

    change_priority(db, task_id=task1.id, new_priority=TaskPriority.URGENT, user_id=user.id)
    complete_task(db, task_id=task2.id, user_id=user.id)

    # Query all activity
    resp = client.get("/api/v1/activity?page=1&page_size=10", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert "items" in data
    assert "total" in data
    assert data["total"] >= 4
    assert len(data["items"]) <= 10

    # Filter by task_id
    resp_task = client.get(f"/api/v1/activity?task_id={task1.id}", headers=headers)
    assert resp_task.status_code == 200
    task_data = resp_task.json()
    assert all(item["task_id"] == str(task1.id) for item in task_data["items"])

    # Filter by action=completed
    resp_completed = client.get("/api/v1/activity?action=completed", headers=headers)
    assert resp_completed.status_code == 200
    completed_data = resp_completed.json()
    assert any(item["action"] == "completed" and item["task_id"] == str(task2.id) for item in completed_data["items"])


def test_recent_activity_backward_compatibility(db):
    """GET /api/v1/tasks/activity/recent must remain backward compatible with limit parameter."""
    uid = uuid.uuid4().hex[:8]
    user = register_user(db, name="Recent Act User", email=f"recent_act_{uid}@nextaction.local", password="Password123!")
    headers = _auth_headers(user)

    task = create_task(db=db, title="Recent Activity Compatibility Task", created_by_user_id=user.id)
    change_status(db, task_id=task.id, new_status=TaskStatus.IN_PROGRESS, user_id=user.id)

    resp = client.get("/api/v1/tasks/activity/recent?limit=5", headers=headers)
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    assert len(items) >= 2
    assert "actor_name" in items[0]
    assert "task_title" in items[0]


def test_template_and_recurrence_history_audit(db):
    """Verify tasks created from templates and recurrence generate rich traceable history records."""
    uid = uuid.uuid4().hex[:8]
    user = register_user(db, name="Traceability User", email=f"trace_{uid}@nextaction.local", password="Password123!")

    # Template
    template = create_task_template(
        db=db,
        name="Standard Setup Template",
        created_by_user_id=user.id,
        priority=TaskPriority.HIGH,
    )
    tmpl_task = create_task_from_template(
        db=db,
        template_id=template.id,
        created_by_user_id=user.id,
        title="Template Instantiated Task",
    )

    tmpl_hist = get_task_history(db=db, task_id=tmpl_task.id)
    tmpl_serialized = [serialize_task_history(h) for h in tmpl_hist]
    create_tmpl_event = next(h for h in tmpl_serialized if h.action == "created_from_template")
    assert create_tmpl_event.actor_name == "Traceability User"
    assert "Standard Setup Template" in (create_tmpl_event.new_value or "")

    # Recurrence
    past_start = datetime.now(timezone.utc) - timedelta(hours=1)
    rec = create_recurring_task(
        db=db,
        name="Scheduled Daily Sync",
        start_date=past_start,
        created_by_user_id=user.id,
        recurrence_type=RecurrenceType.DAILY,
    )
    _, _, created_tasks = evaluate_recurring_tasks(db=db, max_evaluations=10)
    rec_task = next(t for t in created_tasks if t.recurring_task_id == rec.id)

    rec_hist = get_task_history(db=db, task_id=rec_task.id)
    rec_serialized = [serialize_task_history(h) for h in rec_hist]
    rec_event = next(h for h in rec_serialized if h.action == "generated_from_recurrence")
    assert "Scheduled Daily Sync" in (rec_event.new_value or "")


def test_nonexistent_task_history_returns_404(db):
    """Requesting history for a nonexistent task ID must return 404."""
    uid = uuid.uuid4().hex[:8]
    user = register_user(db, name="NotFound User", email=f"notfound_{uid}@nextaction.local", password="Password123!")
    headers = _auth_headers(user)

    random_id = uuid.uuid4()
    resp = client.get(f"/api/v1/tasks/{random_id}/history", headers=headers)
    assert resp.status_code == 404
