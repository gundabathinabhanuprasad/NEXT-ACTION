"""Tests for Phase 29 MongoDB document schemas, repository layer, and index integrity."""

from datetime import datetime, timedelta, timezone
import hashlib
from typing import Generator
import uuid
import pytest
from pydantic import ValidationError
from pymongo import MongoClient
from pymongo.database import Database
from pymongo.errors import DuplicateKeyError

from app.db.mongodb import init_mongo_indexes
from app.documents import (
    ClientDocument,
    EventDocument,
    FollowUpSubDocument,
    NotificationDocument,
    RecurringTaskDocument,
    RecurringTaskExecutionDocument,
    RefreshTokenDocument,
    ReminderSubDocument,
    TaskDocument,
    TaskHistoryDocument,
    TaskPriority,
    TaskStatus,
    TaskTemplateDocument,
    UserDocument,
    UserSettingsDocument,
    WorkflowDocument,
    utcnow,
)
from app.repositories import (
    BaseMongoRepository,
    ClientRepository,
    EventRepository,
    NotificationRepository,
    RecurringTaskExecutionRepository,
    RecurringTaskRepository,
    RefreshTokenRepository,
    TaskHistoryRepository,
    TaskRepository,
    TaskTemplateRepository,
    UserRepository,
    UserSettingsRepository,
    WorkflowRepository,
)

TEST_DB_NAME = "nextaction_phase29_test"
MONGO_TEST_URI = "mongodb://localhost:27017"


@pytest.fixture(scope="module")
def mongo_test_db() -> Generator[Database, None, None]:
    """Provide an isolated, indexed test database against local MongoDB."""
    client = MongoClient(MONGO_TEST_URI, serverSelectionTimeoutMS=2000, tz_aware=True)
    try:
        client.admin.command("ping")
    except Exception as exc:
        pytest.skip(f"Local MongoDB instance not available at {MONGO_TEST_URI}: {exc}")

    db = client[TEST_DB_NAME]
    # Clean slate before tests
    client.drop_database(TEST_DB_NAME)
    init_mongo_indexes(db)

    yield db

    # Teardown: drop test database after module finishes
    client.drop_database(TEST_DB_NAME)
    client.close()


@pytest.fixture(autouse=True)
def clean_test_collections(mongo_test_db: Database):
    """Ensure clean collections between test functions while keeping indexes."""
    yield
    for col_name in mongo_test_db.list_collection_names():
        if not col_name.startswith("system."):
            mongo_test_db[col_name].delete_many({})


# ==============================================================================
# 1. DOCUMENT VALIDATION & SERIALIZATION
# ==============================================================================

def test_document_uuid_and_utc_serialization():
    """Verify document models generate string UUIDs and UTC-aware datetimes."""
    user = UserDocument(name="Agent Smith", email="Agent@Example.Com", password_hash="hashed_pw_123")
    assert isinstance(user.id, str)
    assert len(user.id) == 36
    # Email should be normalized to lowercase
    assert user.email == "agent@example.com"
    assert user.created_at.tzinfo == timezone.utc

    # to_mongo should alias id to _id
    mongo_dict = user.to_mongo()
    assert "_id" in mongo_dict
    assert mongo_dict["_id"] == user.id
    assert "email" in mongo_dict

    # Re-parse from mongo dict
    reloaded = UserDocument.model_validate(mongo_dict)
    assert reloaded.id == user.id
    assert reloaded.email == user.email

    # to_domain exports id
    domain_dict = user.to_domain()
    assert "id" in domain_dict
    assert "_id" not in domain_dict


def test_document_validation_errors():
    """Verify Pydantic validation rejects invalid formats and missing required fields."""
    # Invalid email
    with pytest.raises(ValidationError):
        UserDocument(name="Test", email="not-an-email", password_hash="pw")

    # Invalid task status
    with pytest.raises(ValidationError):
        TaskDocument(title="Test", status="invalid_status")

    # Empty task title
    with pytest.raises(ValidationError):
        TaskDocument(title="")

    # Invalid priority
    with pytest.raises(ValidationError):
        TaskTemplateDocument(name="T1", priority="ultra_high", created_by_user_id=str(uuid.uuid4()))


# ==============================================================================
# 2. USER REPOSITORY & UNIQUE INDEX
# ==============================================================================

def test_user_repository_crud(mongo_test_db: Database):
    """Verify UserRepository CRUD, email lookup normalization, and pagination."""
    repo = UserRepository(db=mongo_test_db)

    user = UserDocument(
        name="Test User",
        email="TestUser@Company.com",
        password_hash="pw",
    )
    created = repo.create(user)
    assert created["id"] == user.id
    assert created["email"] == "testuser@company.com"

    # Lookup by ID
    found = repo.get_by_id(user.id)
    assert found is not None
    assert found["name"] == "Test User"

    # Lookup by case-insensitive email
    by_email = repo.get_by_email("TESTUSER@company.com")
    assert by_email is not None
    assert by_email["id"] == user.id
    assert repo.email_exists("testuser@company.com") is True
    assert repo.email_exists("nonexistent@company.com") is False

    # Update
    updated = repo.update(user.id, {"name": "Updated Name", "is_active": True})
    assert updated is not None
    assert updated["name"] == "Updated Name"

    # Pagination
    items, total = repo.list_users(page=1, page_size=10)
    assert total == 1
    assert len(items) == 1

    # Delete
    assert repo.delete(user.id) is True
    assert repo.get_by_id(user.id) is None


def test_user_unique_email_index(mongo_test_db: Database):
    """Verify MongoDB enforces unique email index on users collection."""
    repo = UserRepository(db=mongo_test_db)
    u1 = UserDocument(name="U1", email="dup@test.com", password_hash="pw1")
    u2 = UserDocument(name="U2", email="dup@test.com", password_hash="pw2")

    repo.create(u1)
    with pytest.raises(DuplicateKeyError):
        repo.create(u2)


# ==============================================================================
# 3. USER SETTINGS REPOSITORY & UPSERT
# ==============================================================================

def test_user_settings_repository(mongo_test_db: Database):
    """Verify UserSettingsRepository atomic upsert and unique user_id index."""
    repo = UserSettingsRepository(db=mongo_test_db)
    user_id = str(uuid.uuid4())

    # Upsert initial settings
    s1 = repo.upsert_for_user(user_id, {"theme": "dark", "enable_email_notifications": False})
    assert s1["user_id"] == user_id
    assert s1["theme"] == "dark"
    assert s1["enable_email_notifications"] is False

    # Fetch
    fetched = repo.get_by_user_id(user_id)
    assert fetched is not None
    assert fetched["theme"] == "dark"

    # Upsert modification
    s2 = repo.upsert_for_user(user_id, {"theme": "light", "notification_frequency": "daily"})
    assert s2["user_id"] == user_id
    assert s2["theme"] == "light"
    assert s2["notification_frequency"] == "daily"
    # Ensure only 1 document exists for this user
    assert repo.count({"user_id": user_id}) == 1

    # Delete
    assert repo.delete_by_user_id(user_id) is True
    assert repo.get_by_user_id(user_id) is None


# ==============================================================================
# 4. CLIENT & WORKFLOW REPOSITORIES
# ==============================================================================

def test_client_and_workflow_repositories(mongo_test_db: Database):
    """Verify ClientRepository and WorkflowRepository CRUD and search."""
    client_repo = ClientRepository(db=mongo_test_db)
    wf_repo = WorkflowRepository(db=mongo_test_db)

    # Client CRUD
    c1 = ClientDocument(name="Acme Corp", company="Acme Inc", email="contact@acme.com")
    c1_res = client_repo.create(c1)
    assert c1_res["name"] == "Acme Corp"

    c2 = ClientDocument(name="Beta LLC", company="Beta Global", email="info@beta.com")
    client_repo.create(c2)

    clients, total = client_repo.list_clients(search="acme")
    assert total == 1
    assert clients[0]["name"] == "Acme Corp"

    # Workflow CRUD
    w1 = WorkflowDocument(name="Onboarding Flow", description="New client flow")
    w1_res = wf_repo.create(w1)
    assert w1_res["name"] == "Onboarding Flow"

    active_wfs = wf_repo.list_active()
    assert len(active_wfs) == 1

    wf_repo.update(w1.id, {"is_active": False})
    assert len(wf_repo.list_active()) == 0


# ==============================================================================
# 5. TASK REPOSITORY (COMPLEX QUERY, ATTEMPT CEILING & EMBEDDED SUBDOCS)
# ==============================================================================

def test_task_repository_crud_and_filters(mongo_test_db: Database):
    """Verify TaskRepository complex filtering, sorting, and pagination."""
    repo = TaskRepository(db=mongo_test_db)
    user_id = str(uuid.uuid4())
    client_id = str(uuid.uuid4())

    now = utcnow()
    t1 = TaskDocument(
        title="Review Q3 Financials",
        description="Detailed review of quarterly reports",
        status=TaskStatus.PENDING,
        priority=TaskPriority.HIGH,
        assigned_user_id=user_id,
        client_id=client_id,
        due_date=now + timedelta(days=2),
        next_action_date=now + timedelta(hours=4),
    )
    t2 = TaskDocument(
        title="Schedule Client Sync",
        description="Call Acme about renewal",
        status=TaskStatus.COMPLETED,
        priority=TaskPriority.LOW,
        assigned_user_id=user_id,
        due_date=now + timedelta(days=10),
    )
    repo.create(t1)
    repo.create(t2)

    # Filter by status and priority
    tasks, count = repo.list_tasks(status=TaskStatus.PENDING, priority=TaskPriority.HIGH)
    assert count == 1
    assert tasks[0]["title"] == "Review Q3 Financials"

    # Filter by assigned user
    tasks, count = repo.list_tasks(assigned_user_id=user_id)
    assert count == 2

    # Filter by search query
    tasks, count = repo.list_tasks(search="Financials")
    assert count == 1
    assert tasks[0]["id"] == t1.id

    # Filter by date ranges
    tasks, count = repo.list_tasks(
        due_from=now,
        due_to=now + timedelta(days=5),
    )
    assert count == 1
    assert tasks[0]["id"] == t1.id


def test_task_attempt_increment_ceiling(mongo_test_db: Database):
    """Verify atomic increment_attempt respects max_attempts boundary."""
    repo = TaskRepository(db=mongo_test_db)
    task = TaskDocument(title="Outreach Call", max_attempts=2, attempt_count=0)
    repo.create(task)

    # 1st attempt: 0 -> 1 (success)
    doc1, ok1 = repo.increment_attempt(task.id, enforce_ceiling=True)
    assert ok1 is True
    assert doc1["attempt_count"] == 1

    # 2nd attempt: 1 -> 2 (success, hits ceiling)
    doc2, ok2 = repo.increment_attempt(task.id, enforce_ceiling=True)
    assert ok2 is True
    assert doc2["attempt_count"] == 2

    # 3rd attempt: 2 >= 2 (rejected, ceiling enforced)
    doc3, ok3 = repo.increment_attempt(task.id, enforce_ceiling=True)
    assert ok3 is False
    assert doc3["attempt_count"] == 2


def test_task_embedded_reminders_and_followups(mongo_test_db: Database):
    """Verify embedded reminders and follow-up subdocuments inside tasks."""
    repo = TaskRepository(db=mongo_test_db)
    task = TaskDocument(title="Multi-stage Project Task")
    repo.create(task)

    # 1. Add embedded reminder
    reminder = ReminderSubDocument(
        remind_at=utcnow() + timedelta(hours=1),
        message="Follow up call required",
    )
    updated = repo.add_reminder(task.id, reminder.to_mongo())
    assert updated is not None
    assert len(updated["reminders"]) == 1
    assert updated["reminders"][0]["id"] == reminder.id

    # 2. Remove reminder
    removed = repo.remove_reminder(task.id, reminder.id)
    assert removed is not None
    assert len(removed["reminders"]) == 0

    # 3. Add embedded follow-up
    follow_up = FollowUpSubDocument(
        notes="Initial customer outreach done, need response",
        scheduled_at=utcnow() + timedelta(days=1),
    )
    updated = repo.add_follow_up(task.id, follow_up.to_mongo())
    assert updated is not None
    assert len(updated["follow_ups"]) == 1
    assert updated["follow_ups"][0]["id"] == follow_up.id
    assert updated["follow_ups"][0]["completed_at"] is None

    # 4. Complete follow-up
    completed = repo.complete_follow_up(task.id, follow_up.id)
    assert completed is not None
    assert completed["follow_ups"][0]["completed_at"] is not None


# ==============================================================================
# 6. TASK HISTORY AUDIT REPOSITORY
# ==============================================================================

def test_task_history_repository(mongo_test_db: Database):
    """Verify TaskHistory audit trail recording and lookup."""
    repo = TaskHistoryRepository(db=mongo_test_db)
    task_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())

    repo.log_history(
        task_id=task_id,
        action="status_change",
        old_value="pending",
        new_value="in_progress",
        reason="Agent started working",
        created_by_user_id=user_id,
    )
    repo.log_history(
        task_id=task_id,
        action="priority_change",
        old_value="medium",
        new_value="high",
        reason="Deadline expedited",
        created_by_user_id=user_id,
    )

    history = repo.list_for_task(task_id)
    assert len(history) == 2
    assert history[0]["action"] == "priority_change"  # Latest first
    assert history[1]["action"] == "status_change"
    assert repo.count_for_task(task_id) == 2

    # Delete
    assert repo.delete_for_task(task_id) == 2
    assert repo.count_for_task(task_id) == 0


# ==============================================================================
# 7. NOTIFICATION REPOSITORY & DEDUPLICATION INDEX
# ==============================================================================

def test_notification_repository_crud(mongo_test_db: Database):
    """Verify NotificationRepository read/unread lifecycle and counts."""
    repo = NotificationRepository(db=mongo_test_db)
    user_id = str(uuid.uuid4())

    n1 = NotificationDocument(
        user_id=user_id,
        type="task_due",
        title="Task Due Soon",
        message="Your task is due in 1 hour.",
    )
    n2 = NotificationDocument(
        user_id=user_id,
        type="system",
        title="System Notice",
        message="Scheduled maintenance tonight.",
    )
    repo.create(n1)
    repo.create(n2)

    assert repo.count_unread(user_id) == 2

    # Mark single as read
    repo.mark_as_read(n1.id)
    assert repo.count_unread(user_id) == 1

    # Mark all read
    repo.mark_all_read(user_id)
    assert repo.count_unread(user_id) == 0


def test_notification_deduplication(mongo_test_db: Database):
    """Verify notification deduplication logic and partial unique index."""
    repo = NotificationRepository(db=mongo_test_db)
    user_id = str(uuid.uuid4())
    dedup_key = "task_overdue_reminder_task_12345"

    # 1. First creation succeeds
    doc1, created1 = repo.create_with_dedup(
        user_id=user_id,
        type_="task_overdue",
        title="Overdue Notice",
        message="Task 12345 is overdue.",
        dedup_key=dedup_key,
    )
    assert created1 is True
    assert doc1["dedup_key"] == dedup_key

    # 2. Duplicate creation is deduplicated and returns existing doc
    doc2, created2 = repo.create_with_dedup(
        user_id=user_id,
        type_="task_overdue",
        title="Overdue Notice 2",
        message="Task 12345 is still overdue.",
        dedup_key=dedup_key,
    )
    assert created2 is False
    assert doc2["id"] == doc1["id"]

    # 3. Direct insert attempting to violate partial unique index raises DuplicateKeyError
    with pytest.raises(DuplicateKeyError):
        repo.create(
            NotificationDocument(
                user_id=user_id,
                type="task_overdue",
                title="Direct Collision",
                message="Duplicate bypass",
                dedup_key=dedup_key,
            )
        )


# ==============================================================================
# 8. REFRESH TOKEN REPOSITORY & REVOCATION
# ==============================================================================

def test_refresh_token_repository(mongo_test_db: Database):
    """Verify RefreshTokenRepository revocation, lookup, and hash uniqueness."""
    repo = RefreshTokenRepository(db=mongo_test_db)
    user_id = str(uuid.uuid4())
    raw_token_1 = "random_refresh_token_string_alpha_123"
    token_hash_1 = hashlib.sha256(raw_token_1.encode()).hexdigest()

    token_doc = RefreshTokenDocument(
        user_id=user_id,
        token_hash=token_hash_1,
        expires_at=utcnow() + timedelta(days=7),
    )
    repo.create(token_doc)

    # Lookup
    found = repo.get_by_token_hash(token_hash_1)
    assert found is not None
    assert found["user_id"] == user_id
    assert found["is_revoked"] is False

    # Unique index violation
    with pytest.raises(DuplicateKeyError):
        repo.create(
            RefreshTokenDocument(
                user_id=user_id,
                token_hash=token_hash_1,
                expires_at=utcnow() + timedelta(days=7),
            )
        )

    # Revoke single token with replacement
    new_token_id = str(uuid.uuid4())
    assert repo.revoke_token(token_hash_1, replaced_by_id=new_token_id) is True
    revoked = repo.get_by_token_hash(token_hash_1)
    assert revoked["is_revoked"] is True
    assert revoked["replaced_by_id"] == new_token_id

    # Active tokens list
    active = repo.list_active_for_user(user_id)
    assert len(active) == 0


# ==============================================================================
# 9. TASK TEMPLATE & RECURRING TASK REPOSITORIES
# ==============================================================================

def test_task_template_repository(mongo_test_db: Database):
    """Verify TaskTemplateRepository blueprint management."""
    repo = TaskTemplateRepository(db=mongo_test_db)
    user_id = str(uuid.uuid4())

    tmpl = TaskTemplateDocument(
        name="Weekly Status Report",
        description="Compile and send weekly numbers",
        priority=TaskPriority.HIGH,
        default_due_offset_days=3,
        created_by_user_id=user_id,
    )
    created = repo.create(tmpl)
    assert created["name"] == "Weekly Status Report"

    items, total = repo.list_templates(is_active=True)
    assert total == 1
    assert items[0]["name"] == "Weekly Status Report"

    assert repo.delete(tmpl.id) is True
    assert repo.get_by_id(tmpl.id) is None


def test_recurring_task_and_execution_idempotency(mongo_test_db: Database):
    """Verify RecurringTask scheduling and RecurringTaskExecution idempotency constraint."""
    rec_repo = RecurringTaskRepository(db=mongo_test_db)
    exec_repo = RecurringTaskExecutionRepository(db=mongo_test_db)
    user_id = str(uuid.uuid4())

    now = utcnow()
    scheduled_slot = datetime(2026, 10, 1, 9, 0, 0, tzinfo=timezone.utc)

    # 1. Recurring task definition
    rec_task = RecurringTaskDocument(
        name="Morning Standup Reminder",
        interval=1,
        start_date=now - timedelta(days=1),
        next_run_at=scheduled_slot,
        created_by_user_id=user_id,
    )
    rec_repo.create(rec_task)

    # Check due tasks
    due = rec_repo.list_due(before_timestamp=scheduled_slot + timedelta(minutes=1))
    assert len(due) == 1
    assert due[0]["id"] == rec_task.id

    # 2. Record execution for slot
    assert exec_repo.is_already_executed(rec_task.id, scheduled_slot) is False

    exec_doc = RecurringTaskExecutionDocument(
        recurring_task_id=rec_task.id,
        scheduled_for=scheduled_slot,
        status="success",
    )
    exec_repo.record_execution(exec_doc)

    assert exec_repo.is_already_executed(rec_task.id, scheduled_slot) is True

    # 3. Duplicate execution attempt triggers unique constraint violation
    with pytest.raises(DuplicateKeyError):
        exec_repo.record_execution(
            RecurringTaskExecutionDocument(
                recurring_task_id=rec_task.id,
                scheduled_for=scheduled_slot,
                status="duplicate_attempt",
            )
        )

    # 4. Advance schedule
    next_slot = scheduled_slot + timedelta(days=1)
    updated = rec_repo.update_next_run(rec_task.id, next_run_at=next_slot, last_run_at=utcnow())
    assert updated["next_run_at"] == next_slot


# ==============================================================================
# 10. EVENT REPOSITORY
# ==============================================================================

def test_event_repository(mongo_test_db: Database):
    """Verify EventRepository range queries and relations."""
    repo = EventRepository(db=mongo_test_db)
    task_id = str(uuid.uuid4())
    client_id = str(uuid.uuid4())

    t0 = utcnow()
    ev1 = EventDocument(
        title="Client Demo",
        start_at=t0 + timedelta(days=1),
        end_at=t0 + timedelta(days=1, hours=1),
        location="Google Meet",
        task_id=task_id,
        client_id=client_id,
    )
    ev2 = EventDocument(
        title="Next Month Strategy",
        start_at=t0 + timedelta(days=30),
        client_id=client_id,
    )
    repo.create(ev1)
    repo.create(ev2)

    # Range query: within 7 days
    events_in_range = repo.list_in_range(start_range=t0, end_range=t0 + timedelta(days=7))
    assert len(events_in_range) == 1
    assert events_in_range[0]["title"] == "Client Demo"

    # Task and Client filters
    assert len(repo.list_for_task(task_id)) == 1
    assert len(repo.list_for_client(client_id)) == 2
