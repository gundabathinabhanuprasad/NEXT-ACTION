"""Comprehensive test suite for NextAction Phase 2 database domain models."""

import uuid
from datetime import datetime, timezone
import pytest
from sqlalchemy import select
from app.db import SessionLocal
from app.models import (
    Client,
    Event,
    FollowUp,
    Reminder,
    Task,
    TaskHistory,
    TaskPriority,
    TaskStatus,
    User,
    Workflow,
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


def test_user_creation(db):
    """Test 1: Create and retrieve a User entity."""
    unique_email = f"user_{uuid.uuid4().hex[:8]}@example.com"
    user = User(name="Alice Developer", email=unique_email)
    db.add(user)
    db.commit()
    db.refresh(user)

    assert isinstance(user.id, uuid.UUID)
    assert user.name == "Alice Developer"
    assert user.email == unique_email
    assert user.created_at is not None
    assert user.updated_at is not None


def test_client_creation(db):
    """Test 2: Create and retrieve a Client entity."""
    client = Client(
        name="Acme Corp",
        company="Acme Global Inc",
        email="contact@acme.com",
        phone="+1-555-0199",
        notes="Key enterprise client",
    )
    db.add(client)
    db.commit()
    db.refresh(client)

    assert isinstance(client.id, uuid.UUID)
    assert client.name == "Acme Corp"
    assert client.company == "Acme Global Inc"


def test_workflow_creation(db):
    """Test 3: Create and retrieve a Workflow entity."""
    workflow = Workflow(
        name="Onboarding Workflow",
        description="Standard onboarding procedure",
        is_active=True,
    )
    db.add(workflow)
    db.commit()
    db.refresh(workflow)

    assert isinstance(workflow.id, uuid.UUID)
    assert workflow.name == "Onboarding Workflow"
    assert workflow.is_active is True


def test_task_creation_with_defaults(db):
    """Test 4: Task creation with business defaults (attempt_count=0, max_attempts=2)."""
    task = Task(
        title="Review Architecture Proposal",
        description="Review Phase 2 database architecture",
        subject_line="Architecture Review",
    )
    db.add(task)
    db.commit()
    db.refresh(task)

    assert isinstance(task.id, uuid.UUID)
    assert task.title == "Review Architecture Proposal"
    assert task.status == TaskStatus.PENDING
    assert task.priority == TaskPriority.MEDIUM
    assert task.attempt_count == 0
    assert task.max_attempts == 2
    assert task.workflow_id is None
    assert task.client_id is None
    assert task.assigned_user_id is None


def test_task_relationships(db):
    """Tests 5, 6, 7: Task relationship with Client, Workflow, and User."""
    user = User(name="Bob Manager", email=f"bob_{uuid.uuid4().hex[:8]}@example.com")
    client = Client(name="Initech LLC")
    workflow = Workflow(name="Quarterly Review")
    db.add_all([user, client, workflow])
    db.commit()

    task = Task(
        title="Complete Quarterly Audit",
        workflow=workflow,
        client=client,
        assigned_user=user,
        status=TaskStatus.IN_PROGRESS,
        priority=TaskPriority.HIGH,
        due_date=datetime.now(timezone.utc),
    )
    db.add(task)
    db.commit()
    db.refresh(task)

    assert task.workflow.id == workflow.id
    assert task.client.id == client.id
    assert task.assigned_user.id == user.id

    # Verify back-populates
    assert task in user.assigned_tasks
    assert task in client.tasks
    assert task in workflow.tasks


def test_follow_up_relationship(db):
    """Test 8: Follow-up attached to a task."""
    task = Task(title="Schedule discovery call")
    db.add(task)
    db.commit()

    follow_up = FollowUp(
        task=task,
        scheduled_at=datetime.now(timezone.utc),
        notes="Follow up with discovery call notes",
    )
    db.add(follow_up)
    db.commit()
    db.refresh(task)

    assert len(task.follow_ups) == 1
    assert task.follow_ups[0].notes == "Follow up with discovery call notes"
    assert task.follow_ups[0].task_id == task.id


def test_reminder_relationship_and_attempt_count_invariant(db):
    """Test 9: Reminder attached to task and verify reminder does NOT alter attempt_count."""
    task = Task(title="Task with reminders", attempt_count=0)
    db.add(task)
    db.commit()

    reminder = Reminder(
        task=task,
        remind_at=datetime.now(timezone.utc),
        message="Upcoming due date alert",
    )
    db.add(reminder)
    db.commit()
    db.refresh(task)

    assert len(task.reminders) == 1
    assert task.reminders[0].message == "Upcoming due date alert"
    assert task.reminders[0].is_sent is False
    # Verify reminder does NOT alter attempt_count
    assert task.attempt_count == 0


def test_event_relationship(db):
    """Test 10: Event linked to a Task and Client."""
    client = Client(name="Global Corp")
    task = Task(title="Prepare Presentation")
    db.add_all([client, task])
    db.commit()

    event = Event(
        title="Kickoff Meeting",
        description="Project kickoff and stakeholder alignment",
        start_at=datetime.now(timezone.utc),
        location="Room 101 / Google Meet",
        task=task,
        client=client,
    )
    db.add(event)
    db.commit()
    db.refresh(event)

    assert event.task_id == task.id
    assert event.client_id == client.id
    assert event.task.title == "Prepare Presentation"
    assert event.client.name == "Global Corp"


def test_task_history_relationship(db):
    """Test 11: TaskHistory tracking changes on a task."""
    user = User(name="Auditor User", email=f"auditor_{uuid.uuid4().hex[:8]}@example.com")
    task = Task(title="Audited Task")
    db.add_all([user, task])
    db.commit()

    history = TaskHistory(
        task=task,
        action="status_changed",
        old_value="pending",
        new_value="in_progress",
        reason="Work commenced by assignee",
        created_by_user=user,
    )
    db.add(history)
    db.commit()
    db.refresh(task)

    assert len(task.histories) == 1
    assert task.histories[0].action == "status_changed"
    assert task.histories[0].created_by_user_id == user.id
    assert task.histories[0].created_by_user.name == "Auditor User"


def test_task_history_preservation_on_task_delete(db):
    """Test dedicated historical preservation: verify TaskHistory survives Task deletion with task_id set to NULL."""
    user = User(name="History Preserver", email=f"preserver_{uuid.uuid4().hex[:8]}@example.com")
    task = Task(title="Task to be Archived", assigned_user=user)
    db.add_all([user, task])
    db.commit()

    history = TaskHistory(
        task=task,
        action="postponed",
        old_value="2026-10-01T00:00:00Z",
        new_value="2026-10-15T00:00:00Z",
        reason="Client requested extension for review",
        created_by_user=user,
    )
    db.add(history)
    db.commit()

    task_id = task.id
    history_id = history.id
    user_id = user.id

    # 4. Delete the Task
    db.delete(task)
    db.commit()

    # 5. Verify the TaskHistory record still exists
    preserved_history = db.get(TaskHistory, history_id)
    assert preserved_history is not None

    # 6. Verify task_id became NULL
    assert preserved_history.task_id is None

    # 7. Verify old_value, new_value, action, reason, and created_at remain intact
    assert preserved_history.action == "postponed"
    assert preserved_history.old_value == "2026-10-01T00:00:00Z"
    assert preserved_history.new_value == "2026-10-15T00:00:00Z"
    assert preserved_history.reason == "Client requested extension for review"
    assert preserved_history.created_by_user_id == user_id
    assert preserved_history.created_at is not None


def test_cascade_delete_task(db):
    """Verify deleting a task cascades to follow-ups and reminders, sets task_id to NULL on histories, and preserves parents."""
    user = User(name="User A", email=f"usera_{uuid.uuid4().hex[:8]}@example.com")
    client = Client(name="Client A")
    workflow = Workflow(name="Workflow A")
    db.add_all([user, client, workflow])
    db.commit()

    task = Task(
        title="Deletable Task",
        client=client,
        workflow=workflow,
        assigned_user=user,
    )
    db.add(task)
    db.commit()

    follow_up = FollowUp(task=task, scheduled_at=datetime.now(timezone.utc))
    reminder = Reminder(task=task, remind_at=datetime.now(timezone.utc), message="Alert")
    history = TaskHistory(task=task, action="created", created_by_user=user)
    db.add_all([follow_up, reminder, history])
    db.commit()

    task_id = task.id
    follow_up_id = follow_up.id
    reminder_id = reminder.id
    history_id = history.id

    # Delete task
    db.delete(task)
    db.commit()

    # Operational children must be cascade deleted
    assert db.get(FollowUp, follow_up_id) is None
    assert db.get(Reminder, reminder_id) is None

    # Historical audit records must survive with task_id=None
    persisted_history = db.get(TaskHistory, history_id)
    assert persisted_history is not None
    assert persisted_history.task_id is None
    assert persisted_history.action == "created"

    # Parents must remain intact (no cascading upward)
    assert db.get(User, user.id) is not None
    assert db.get(Client, client.id) is not None
    assert db.get(Workflow, workflow.id) is not None

