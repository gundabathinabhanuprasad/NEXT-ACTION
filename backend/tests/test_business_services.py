"""Comprehensive test suite for NextAction Phase 3 Business Logic Services.

Executed against live PostgreSQL container.
"""

from datetime import datetime, timedelta, timezone
import json
import uuid
import pytest
from sqlalchemy import select
from app.db import SessionLocal
from app.models import (
    Client,
    FollowUp,
    Reminder,
    Task,
    TaskHistory,
    TaskPriority,
    TaskStatus,
    User,
    Workflow,
)
from app.services import (
    FollowUpNotFoundError,
    InvalidTaskDateError,
    MaxAttemptsReachedError,
    OverrideReasonRequiredError,
    PostponementReasonRequiredError,
    ReminderNotFoundError,
    ReopenReasonRequiredError,
    TaskAlreadyCompletedError,
    TaskCancelledError,
    TaskCompletedError,
    TaskNotCompletedError,
    TaskNotFoundError,
    assign_task,
    change_priority,
    change_status,
    complete_follow_up,
    complete_task,
    create_follow_up,
    create_reminder,
    create_task,
    get_follow_up,
    get_reminder,
    get_task,
    list_due_reminders,
    list_task_follow_ups,
    postpone_task,
    process_reminder,
    record_attempt,
    reopen_task,
    update_next_action_date,
    update_subject_line,
)


@pytest.fixture
def db():
    """Provide a database session that rolls back after each test."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture
def test_user(db):
    """Create a sample user for testing."""
    user = User(
        name="Business Operator",
        email=f"operator_{uuid.uuid4().hex[:8]}@example.com",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# =========================================================================
# 1 & 2: Task Creation & Task Creation History
# =========================================================================
def test_task_creation_and_history(db, test_user):
    """Verify task creation sets business defaults and records initial history."""
    due = datetime.now(timezone.utc) + timedelta(days=3)
    next_action = datetime.now(timezone.utc) + timedelta(days=1)

    task = create_task(
        db=db,
        title="Prepare Q3 Review",
        description="Compile financial highlights",
        subject_line="Q3 Financials",
        assigned_user_id=test_user.id,
        due_date=due,
        next_action_date=next_action,
        max_attempts=2,
    )

    assert isinstance(task.id, uuid.UUID)
    assert task.title == "Prepare Q3 Review"
    assert task.status == TaskStatus.PENDING
    assert task.priority == TaskPriority.MEDIUM
    assert task.attempt_count == 0
    assert task.max_attempts == 2
    assert task.assigned_user_id == test_user.id

    # Verify history entry
    histories = list(db.scalars(select(TaskHistory).where(TaskHistory.task_id == task.id)).all())
    assert len(histories) == 1
    assert histories[0].action == "created"
    assert histories[0].created_by_user_id == test_user.id
    payload = json.loads(histories[0].new_value)
    assert payload["title"] == "Prepare Q3 Review"
    assert payload["status"] == "pending"


# =========================================================================
# 3, 4, 5, 6: Attempts & Max Attempts Rejection
# =========================================================================
def test_attempts_and_max_attempts_rejection(db, test_user):
    """Verify normal attempts increment counter until max_attempts is reached, then reject."""
    task = create_task(
        db=db,
        title="Client Outreach Call",
        max_attempts=2,
        assigned_user_id=test_user.id,
    )

    # 3: First attempt
    task = record_attempt(db, task_id=task.id, user_id=test_user.id, notes="First call went to voicemail")
    assert task.attempt_count == 1

    # 4: Second attempt
    task = record_attempt(db, task_id=task.id, user_id=test_user.id, notes="Second call - left follow-up message")
    assert task.attempt_count == 2

    # 5: Third attempt rejected
    with pytest.raises(MaxAttemptsReachedError) as exc_info:
        record_attempt(db, task_id=task.id, user_id=test_user.id, notes="Third call attempt")
    assert "Maximum attempts reached" in str(exc_info.value)

    # 6: Verify attempt count remains unchanged after rejection
    db.refresh(task)
    assert task.attempt_count == 2

    # Verify histories count: 1 created + 2 attempts = 3 total (no 3rd attempt history)
    histories = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id)
            .order_by(TaskHistory.created_at.asc())
        ).all()
    )
    assert len(histories) == 3
    assert histories[1].action == "attempt"
    assert histories[1].new_value == "1"
    assert histories[2].action == "attempt"
    assert histories[2].new_value == "2"


# =========================================================================
# 7 & 8: Authorized Override
# =========================================================================
def test_authorized_override_and_reason_requirement(db, test_user):
    """Verify authorized override allows additional attempt with reason and rejects without reason."""
    task = create_task(
        db=db,
        title="High Priority Escalation",
        max_attempts=2,
    )
    # Reach max attempts
    record_attempt(db, task_id=task.id, notes="Attempt 1")
    record_attempt(db, task_id=task.id, notes="Attempt 2")
    assert task.attempt_count == 2

    # 8: Override without reason must fail
    with pytest.raises(OverrideReasonRequiredError):
        record_attempt(
            db,
            task_id=task.id,
            authorized_override=True,
            override_reason="",
        )
    with pytest.raises(OverrideReasonRequiredError):
        record_attempt(
            db,
            task_id=task.id,
            authorized_override=True,
            override_reason=None,
        )
    db.refresh(task)
    assert task.attempt_count == 2

    # 7: Authorized override with valid reason succeeds
    task = record_attempt(
        db,
        task_id=task.id,
        user_id=test_user.id,
        authorized_override=True,
        override_reason="Executive approval granted for additional follow-up attempt",
    )
    assert task.attempt_count == 3

    # Verify override history
    override_hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "attempt_override")
        ).all()
    )
    assert len(override_hist) == 1
    assert override_hist[0].old_value == "2"
    assert override_hist[0].new_value == "3"
    assert override_hist[0].reason == "Executive approval granted for additional follow-up attempt"
    assert override_hist[0].created_by_user_id == test_user.id


# =========================================================================
# 9 & 10: Reminder Attempt-Count Invariant
# =========================================================================
def test_reminder_attempt_count_invariant(db):
    """Verify creating and processing reminders does NOT modify Task.attempt_count."""
    task = create_task(db=db, title="Reminder Test Task", max_attempts=2)
    assert task.attempt_count == 0

    # 9: Create reminder
    remind_time = datetime.now(timezone.utc) + timedelta(hours=2)
    reminder = create_reminder(
        db=db,
        task_id=task.id,
        remind_at=remind_time,
        message="Important deadline approaching",
    )
    db.refresh(task)
    assert reminder.is_sent is False
    assert task.attempt_count == 0  # Invariant check

    # 10: Process reminder
    processed = process_reminder(db=db, reminder_id=reminder.id)
    assert processed.is_sent is True
    db.refresh(task)
    assert task.attempt_count == 0  # Invariant check

    # Verify list due reminders
    due = list_due_reminders(db=db, as_of=datetime.now(timezone.utc) + timedelta(hours=3))
    assert reminder.id not in [r.id for r in due if r.is_sent]


# =========================================================================
# 11 & 12: Postponement
# =========================================================================
def test_postponement_rules(db, test_user):
    """Verify postponement requires a reason and preserves original due date in history."""
    orig_due = datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc)
    new_due = datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc)

    task = create_task(db=db, title="Contract Signing", due_date=orig_due)

    # 11: Missing reason rejected
    with pytest.raises(PostponementReasonRequiredError):
        postpone_task(db, task_id=task.id, new_due_date=new_due, reason="")

    with pytest.raises(PostponementReasonRequiredError):
        postpone_task(db, task_id=task.id, new_due_date=new_due, reason="   ")

    # 12: Postpone with valid reason
    task = postpone_task(
        db=db,
        task_id=task.id,
        new_due_date=new_due,
        reason="Client requested additional legal review window",
        user_id=test_user.id,
    )
    assert task.due_date == new_due

    # Verify history preserved original due date
    postpone_hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "postponed")
        ).all()
    )
    assert len(postpone_hist) == 1
    assert postpone_hist[0].old_value == orig_due.isoformat()
    assert postpone_hist[0].new_value == new_due.isoformat()
    assert postpone_hist[0].reason == "Client requested additional legal review window"
    assert postpone_hist[0].created_by_user_id == test_user.id


# =========================================================================
# 13: Next Action Date Update
# =========================================================================
def test_next_action_date_update(db, test_user):
    """Verify updating next_action_date updates model and records history."""
    task = create_task(db=db, title="Prospecting")
    assert task.next_action_date is None

    new_action_date = datetime.now(timezone.utc) + timedelta(days=2)
    task = update_next_action_date(
        db=db,
        task_id=task.id,
        next_action_date=new_action_date,
        user_id=test_user.id,
    )
    assert task.next_action_date == new_action_date

    hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "next_action_date_changed")
        ).all()
    )
    assert len(hist) == 1
    assert hist[0].old_value == "None"
    assert hist[0].new_value == new_action_date.isoformat()


# =========================================================================
# 14 & 15: Task Completion & Duplicate Rejection
# =========================================================================
def test_task_completion_and_duplicate_rejection(db, test_user):
    """Verify task completion sets status/timestamp, and duplicate completion is rejected."""
    task = create_task(db=db, title="Deliver Final Report")

    # 14: Complete task
    task = complete_task(db=db, task_id=task.id, user_id=test_user.id)
    assert task.status == TaskStatus.COMPLETED
    assert task.completed_at is not None

    hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "completed")
        ).all()
    )
    assert len(hist) == 1
    assert hist[0].created_by_user_id == test_user.id

    # 15: Duplicate completion rejected
    with pytest.raises(TaskAlreadyCompletedError):
        complete_task(db=db, task_id=task.id, user_id=test_user.id)


# =========================================================================
# 16: Reopen Completed Task
# =========================================================================
def test_reopen_completed_task(db, test_user):
    """Verify completed task can be reopened with mandatory reason."""
    task = create_task(db=db, title="Audit File")
    complete_task(db=db, task_id=task.id, user_id=test_user.id)

    # Reopen without reason rejected
    with pytest.raises(ReopenReasonRequiredError):
        reopen_task(db=db, task_id=task.id, reason="", user_id=test_user.id)

    # Reopen with reason succeeds
    task = reopen_task(
        db=db,
        task_id=task.id,
        reason="Missing auditor signature on page 4",
        user_id=test_user.id,
    )
    assert task.status == TaskStatus.PENDING
    assert task.completed_at is None

    # Cannot reopen a non-completed task
    with pytest.raises(TaskNotCompletedError):
        reopen_task(db=db, task_id=task.id, reason="Again", user_id=test_user.id)


# =========================================================================
# 17: Status Change
# =========================================================================
def test_status_change(db, test_user):
    """Verify controlled status transitions and history tracking."""
    task = create_task(db=db, title="Process Batch")
    assert task.status == TaskStatus.PENDING

    task = change_status(
        db=db,
        task_id=task.id,
        new_status=TaskStatus.IN_PROGRESS,
        user_id=test_user.id,
        reason="Processing started by worker",
    )
    assert task.status == TaskStatus.IN_PROGRESS

    hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "status_changed")
        ).all()
    )
    assert len(hist) == 1
    assert hist[0].old_value == "pending"
    assert hist[0].new_value == "in_progress"
    assert hist[0].reason == "Processing started by worker"


# =========================================================================
# 18: Priority Change
# =========================================================================
def test_priority_change(db, test_user):
    """Verify priority transitions and history tracking."""
    task = create_task(db=db, title="System Update", priority=TaskPriority.LOW)
    assert task.priority == TaskPriority.LOW

    task = change_priority(
        db=db,
        task_id=task.id,
        new_priority=TaskPriority.URGENT,
        user_id=test_user.id,
        reason="Production bug requires immediate hotfix",
    )
    assert task.priority == TaskPriority.URGENT

    hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "priority_changed")
        ).all()
    )
    assert len(hist) == 1
    assert hist[0].old_value == "low"
    assert hist[0].new_value == "urgent"


# =========================================================================
# 19: Assignment Change
# =========================================================================
def test_assignment_change(db, test_user):
    """Verify assigning and reassigning users and history recording."""
    user2 = User(name="Worker Two", email=f"worker2_{uuid.uuid4().hex[:8]}@example.com")
    db.add(user2)
    db.commit()

    task = create_task(db=db, title="Customer Support Ticket", assigned_user_id=test_user.id)
    assert task.assigned_user_id == test_user.id

    task = assign_task(
        db=db,
        task_id=task.id,
        assigned_user_id=user2.id,
        assigned_by_user_id=test_user.id,
    )
    assert task.assigned_user_id == user2.id

    hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "reassigned")
        ).all()
    )
    assert len(hist) == 1
    assert hist[0].old_value == str(test_user.id)
    assert hist[0].new_value == str(user2.id)
    assert hist[0].created_by_user_id == test_user.id


# =========================================================================
# 20: Subject Line Change
# =========================================================================
def test_subject_line_change(db, test_user):
    """Verify subject line changes and history recording."""
    task = create_task(db=db, title="Email outreach", subject_line="Introduction")
    assert task.subject_line == "Introduction"

    task = update_subject_line(
        db=db,
        task_id=task.id,
        subject_line="Revised: Follow-up regarding Q3 Partnership",
        user_id=test_user.id,
    )
    assert task.subject_line == "Revised: Follow-up regarding Q3 Partnership"

    hist = list(
        db.scalars(
            select(TaskHistory)
            .where(TaskHistory.task_id == task.id, TaskHistory.action == "subject_line_changed")
        ).all()
    )
    assert len(hist) == 1
    assert hist[0].old_value == "Introduction"
    assert hist[0].new_value == "Revised: Follow-up regarding Q3 Partnership"


# =========================================================================
# 21: Missing Task Error
# =========================================================================
def test_missing_task_raises_domain_error(db):
    """Verify calling services with a non-existent task_id raises TaskNotFoundError."""
    random_id = uuid.uuid4()
    with pytest.raises(TaskNotFoundError):
        get_task(db, random_id)

    with pytest.raises(TaskNotFoundError):
        record_attempt(db, random_id)

    with pytest.raises(TaskNotFoundError):
        complete_task(db, random_id)


# =========================================================================
# 22: Invalid Task State Errors (Attempt on Completed/Cancelled Task)
# =========================================================================
def test_invalid_task_state_errors(db):
    """Verify actions on completed or cancelled tasks are rejected."""
    task = create_task(db=db, title="Completed State Task")
    complete_task(db=db, task_id=task.id)

    # Attempt on completed task
    with pytest.raises(TaskCompletedError):
        record_attempt(db, task_id=task.id)

    # Postpone on completed task
    with pytest.raises(TaskCompletedError):
        postpone_task(
            db,
            task_id=task.id,
            new_due_date=datetime.now(timezone.utc) + timedelta(days=1),
            reason="Postpone completed",
        )

    # Cancelled task
    task2 = create_task(db=db, title="Cancelled State Task")
    change_status(db=db, task_id=task2.id, new_status=TaskStatus.CANCELLED)

    with pytest.raises(TaskCancelledError):
        record_attempt(db, task_id=task2.id)

    with pytest.raises(TaskCancelledError):
        complete_task(db=db, task_id=task2.id)


# =========================================================================
# 23: Transaction Rollback on Failure
# =========================================================================
def test_transaction_rollback_on_failure(db):
    """Verify that when a business operation fails, uncommitted changes roll back cleanly."""
    task = create_task(db=db, title="Rollback Invariant Task", max_attempts=1)
    record_attempt(db=db, task_id=task.id, notes="First attempt")
    assert task.attempt_count == 1

    # Attempting second normal attempt raises MaxAttemptsReachedError
    with pytest.raises(MaxAttemptsReachedError):
        record_attempt(db=db, task_id=task.id, notes="Failed second attempt")

    # Verify no partial history or attempt count was persisted
    db.expire_all()
    reloaded_task = db.get(Task, task.id)
    assert reloaded_task.attempt_count == 1

    histories = list(db.scalars(select(TaskHistory).where(TaskHistory.task_id == task.id)).all())
    assert len(histories) == 2  # created + 1 attempt


# =========================================================================
# 24: Reminder & FollowUp NotFound Domain Exceptions
# =========================================================================
def test_reminder_and_follow_up_not_found(db):
    """Verify missing reminder or follow-up raises proper domain exceptions."""
    random_id = uuid.uuid4()
    with pytest.raises(ReminderNotFoundError):
        get_reminder(db, random_id)

    with pytest.raises(ReminderNotFoundError):
        process_reminder(db, random_id)

    with pytest.raises(FollowUpNotFoundError):
        get_follow_up(db, random_id)

    with pytest.raises(FollowUpNotFoundError):
        complete_follow_up(db, random_id)


# =========================================================================
# 25: Follow-Up Service Lifecycle
# =========================================================================
def test_follow_up_service_lifecycle(db):
    """Verify follow-up creation, retrieval, and completion."""
    task = create_task(db=db, title="Follow Up Task")
    scheduled = datetime.now(timezone.utc) + timedelta(days=2)

    follow_up = create_follow_up(
        db=db,
        task_id=task.id,
        scheduled_at=scheduled,
        notes="Schedule second round interview",
    )
    assert follow_up.task_id == task.id
    assert follow_up.completed_at is None

    # Retrieve
    retrieved = get_follow_up(db=db, follow_up_id=follow_up.id)
    assert retrieved.id == follow_up.id

    # Complete
    completed = complete_follow_up(
        db=db,
        follow_up_id=follow_up.id,
        notes="Interview conducted successfully",
    )
    assert completed.completed_at is not None
    assert completed.notes == "Interview conducted successfully"

    # List
    all_follow_ups = list_task_follow_ups(db=db, task_id=task.id)
    assert len(all_follow_ups) == 1


# =========================================================================
# 26: Task History Survives Task Deletion
# =========================================================================
def test_task_history_survives_task_deletion_service_level(db, test_user):
    """Verify TaskHistory is preserved when a Task is removed."""
    task = create_task(db=db, title="Audit Life Cycle Task", assigned_user_id=test_user.id)
    record_attempt(db=db, task_id=task.id, notes="Initial attempt")

    task_id = task.id
    histories = list(db.scalars(select(TaskHistory).where(TaskHistory.task_id == task_id)).all())
    assert len(histories) == 2  # created + attempt
    history_ids = [h.id for h in histories]

    # Delete task directly
    db.delete(task)
    db.commit()

    # Verify histories still exist with task_id=None
    for hid in history_ids:
        h = db.get(TaskHistory, hid)
        assert h is not None
        assert h.task_id is None
        assert h.created_by_user_id == test_user.id or h.action == "attempt"

