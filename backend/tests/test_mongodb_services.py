"""Phase 30 — Dedicated MongoDB Service-Layer & Dual-Engine Dispatch Tests.

Verifies persistence engine abstraction, centralized dispatch, and full business
logic parity across Task, User, Client, Workflow, History, Notification, Settings,
Reminder, Follow-Up, and Token persistence boundaries against an isolated local MongoDB test database.
"""

from datetime import datetime, timedelta, timezone
from typing import Generator
import uuid
import pytest
from pymongo import MongoClient
from pymongo.database import Database

from app.core.config import settings
from app.db.mongodb import init_mongo_indexes
from app.models.enums import TaskPriority, TaskStatus
from app.persistence.constants import EngineType
from app.persistence.context import get_active_engine, override_engine
from app.persistence.gateway import PersistenceGateway, get_persistence_gateway
from app.persistence.mongodb import (
    MongoClientService,
    MongoFollowUpService,
    MongoHistoryService,
    MongoNotificationService,
    MongoReminderService,
    MongoSettingsService,
    MongoTaskService,
    MongoUserService,
    MongoWorkflowService,
)
from app.persistence.postgres import PostgresTaskService
from app.repositories import (
    ClientRepository,
    NotificationRepository,
    RefreshTokenRepository,
    TaskHistoryRepository,
    TaskRepository,
    UserRepository,
    UserSettingsRepository,
    WorkflowRepository,
)
from app.schemas.settings import UserSettingsUpdate
from app.services.exceptions import (
    ClientNotFoundError,
    FollowUpNotFoundError,
    InactiveUserError,
    InvalidCredentialsError,
    InvalidStatusTransitionError,
    InvalidTaskDateError,
    MaxAttemptsReachedError,
    NextActionDomainError,
    NotificationNotFoundError,
    OverrideReasonRequiredError,
    PostponementReasonRequiredError,
    RefreshTokenExpiredError,
    RefreshTokenNotFoundError,
    RefreshTokenRevokedError,
    ReminderNotFoundError,
    ReopenReasonRequiredError,
    TaskAlreadyCompletedError,
    TaskCancelledError,
    TaskCompletedError,
    TaskNotCompletedError,
    TaskNotFoundError,
    UserAlreadyExistsError,
    UserNotFoundError,
    WorkflowNotFoundError,
)

TEST_DB_NAME = "nextaction_phase30_test"
MONGO_TEST_URI = "mongodb://localhost:27017"


@pytest.fixture(scope="module")
def mongo_test_db() -> Generator[Database, None, None]:
    """Provide an isolated, indexed test database against local MongoDB."""
    client = MongoClient(MONGO_TEST_URI, serverSelectionTimeoutMS=2000, tz_aware=True)
    try:
        client.admin.command("ping")
    except Exception as exc:
        pytest.skip(f"Local MongoDB instance not available at {MONGO_TEST_URI}: {exc}")

    client.drop_database(TEST_DB_NAME)
    db = client[TEST_DB_NAME]
    init_mongo_indexes(db)
    yield db
    client.drop_database(TEST_DB_NAME)
    client.close()


@pytest.fixture
def mongo_services(mongo_test_db: Database):
    """Instantiate MongoDB service adapters bound to isolated test database collections."""
    user_repo = UserRepository(db=mongo_test_db)
    client_repo = ClientRepository(db=mongo_test_db)
    workflow_repo = WorkflowRepository(db=mongo_test_db)
    settings_repo = UserSettingsRepository(db=mongo_test_db)
    task_repo = TaskRepository(db=mongo_test_db)
    history_repo = TaskHistoryRepository(db=mongo_test_db)
    notif_repo = NotificationRepository(db=mongo_test_db)
    token_repo = RefreshTokenRepository(db=mongo_test_db)

    task_svc = MongoTaskService(
        task_repo=task_repo,
        history_repo=history_repo,
        user_repo=user_repo,
        client_repo=client_repo,
        workflow_repo=workflow_repo,
    )
    user_svc = MongoUserService(
        user_repo=user_repo,
        settings_repo=settings_repo,
        token_repo=token_repo,
    )
    client_svc = MongoClientService(client_repo=client_repo)
    workflow_svc = MongoWorkflowService(workflow_repo=workflow_repo)
    settings_svc = MongoSettingsService(settings_repo=settings_repo, user_repo=user_repo)
    notif_svc = MongoNotificationService(notif_repo=notif_repo, settings_repo=settings_repo)
    reminder_svc = MongoReminderService(task_repo=task_repo)
    follow_up_svc = MongoFollowUpService(task_repo=task_repo)
    history_svc = MongoHistoryService(
        history_repo=history_repo, task_repo=task_repo, user_repo=user_repo
    )

    return {
        "task": task_svc,
        "user": user_svc,
        "client": client_svc,
        "workflow": workflow_svc,
        "settings": settings_svc,
        "notif": notif_svc,
        "reminder": reminder_svc,
        "follow_up": follow_up_svc,
        "history": history_svc,
    }


# ==============================================================================
# 1. ENGINE SELECTION & DISPATCH TESTS
# ==============================================================================

def test_default_engine_selection():
    """Verify that PostgreSQL is the default active engine when no override is active."""
    assert get_active_engine() == EngineType.POSTGRESQL.value
    gateway = get_persistence_gateway()
    assert gateway.active_engine == EngineType.POSTGRESQL.value
    assert gateway.is_postgresql is True
    assert gateway.is_mongodb is False
    assert isinstance(gateway.task_service, PostgresTaskService)


def test_explicit_mongodb_engine_selection(monkeypatch):
    """Verify explicit selection of MongoDB via context override when enabled."""
    monkeypatch.setattr(settings, "MONGODB_ENABLED", True)
    with override_engine(EngineType.MONGODB.value):
        assert get_active_engine() == EngineType.MONGODB.value
        gateway = get_persistence_gateway()
        assert gateway.active_engine == EngineType.MONGODB.value
        assert gateway.is_mongodb is True
        assert gateway.is_postgresql is False
        assert isinstance(gateway.task_service, MongoTaskService)


def test_invalid_engine_rejection():
    """Verify that an unsupported engine value is rejected immediately."""
    with pytest.raises(ValueError, match="Unsupported persistence engine"):
        get_active_engine("unsupported_engine_xyz")

    with pytest.raises(ValueError, match="Invalid persistence engine override"):
        with override_engine("invalid_db"):
            pass


def test_mongodb_disabled_safety_control(monkeypatch):
    """Verify MongoDB persistence cannot be activated if MONGODB_ENABLED=False."""
    monkeypatch.setattr(settings, "MONGODB_ENABLED", False)
    with pytest.raises(RuntimeError, match="MONGODB_ENABLED is False"):
        get_active_engine(EngineType.MONGODB.value)


# ==============================================================================
# 2. USER SERVICE BOUNDARY (MONGODB)
# ==============================================================================

def test_mongo_user_crud_and_auth(mongo_services):
    """Test user registration, email uniqueness, authentication, and UUID lookup."""
    user_svc = mongo_services["user"]

    # 1. Register User
    user = user_svc.register_user(
        name="Alice Engineer",
        email="Alice@Example.com",
        password="SecurePassword123!",
    )
    assert user.name == "Alice Engineer"
    assert user.email == "alice@example.com"  # Normalized lowercase
    assert user.is_active is True

    # 2. Duplicate Email Rejection
    with pytest.raises(UserAlreadyExistsError):
        user_svc.register_user(
            name="Alice Duplicate",
            email="ALICE@example.com",
            password="AnotherPassword123!",
        )

    # 3. Successful Authentication
    auth_user = user_svc.authenticate_user(
        email="alice@example.com",
        password="SecurePassword123!",
    )
    assert auth_user.id == user.id

    # 4. Invalid Password Rejection
    with pytest.raises(InvalidCredentialsError):
        user_svc.authenticate_user(
            email="alice@example.com",
            password="WrongPassword!",
        )

    # 5. Lookup by ID and Email
    by_id = user_svc.get_user_by_id(user_id=user.id)
    assert by_id.id == user.id

    by_email = user_svc.get_user_by_email(email="alice@example.com")
    assert by_email is not None
    assert by_email.id == user.id

    # 6. Change Password
    user_svc.change_password(
        user_id=user.id,
        old_password="SecurePassword123!",
        new_password="NewSecurePassword456!",
    )
    # Auth with new password succeeds
    user_svc.authenticate_user(
        email="alice@example.com",
        password="NewSecurePassword456!",
    )


# ==============================================================================
# 3. CLIENT & WORKFLOW SERVICE BOUNDARY (MONGODB)
# ==============================================================================

def test_mongo_client_crud(mongo_services):
    """Test client CRUD operations and text search via service boundary."""
    client_svc = mongo_services["client"]

    # Create
    client = client_svc.create_client(
        name="Acme Corporation",
        company="Acme Global",
        email="contact@acme.org",
        phone="+1234567890",
        notes="Strategic account",
    )
    assert client.name == "Acme Corporation"

    # Get
    fetched = client_svc.get_client(client_id=client.id)
    assert fetched.id == client.id

    # Update
    updated = client_svc.update_client(
        client_id=client.id,
        company="Acme Industries",
        notes="Updated notes",
    )
    assert updated.company == "Acme Industries"
    assert updated.notes == "Updated notes"

    # Search and paginate
    items, total = client_svc.list_clients(search="Industries", page=1, page_size=10)
    assert total >= 1
    assert any(c.id == client.id for c in items)

    # Delete
    assert client_svc.delete_client(client_id=client.id) is True
    with pytest.raises(ClientNotFoundError):
        client_svc.get_client(client_id=client.id)


def test_mongo_workflow_crud(mongo_services):
    """Test workflow CRUD operations and active status filtering."""
    workflow_svc = mongo_services["workflow"]

    # Create
    wf = workflow_svc.create_workflow(
        name="Customer Onboarding",
        description="Standard onboarding flow",
        is_active=True,
    )
    assert wf.name == "Customer Onboarding"

    # Update
    updated = workflow_svc.update_workflow(
        workflow_id=wf.id,
        description="Updated onboarding flow",
        is_active=False,
    )
    assert updated.description == "Updated onboarding flow"
    assert updated.is_active is False

    # List inactive
    items, total = workflow_svc.list_workflows(is_active=False)
    assert total >= 1
    assert any(w.id == wf.id for w in items)

    # Delete
    assert workflow_svc.delete_workflow(workflow_id=wf.id) is True
    with pytest.raises(WorkflowNotFoundError):
        workflow_svc.get_workflow(workflow_id=wf.id)


# ==============================================================================
# 4. TASK SERVICE BOUNDARY — CRUD, ATTRIBUTES & INVARIANTS (MONGODB)
# ==============================================================================

def test_mongo_task_lifecycle(mongo_services):
    """Test task creation, updates, status transitions, and history generation."""
    task_svc = mongo_services["task"]
    user_svc = mongo_services["user"]

    user = user_svc.register_user(
        name="Bob Worker",
        email=f"bob_{uuid.uuid4().hex[:6]}@example.com",
        password="Password123!",
    )

    now = datetime.now(timezone.utc)
    due = now + timedelta(days=3)
    next_action = now + timedelta(days=1)

    # 1. Create Task
    task = task_svc.create_task(
        title="Prepare Q3 Review",
        description="Review financial projections",
        subject_line="Q3 Financials",
        assigned_user_id=user.id,
        status=TaskStatus.PENDING,
        priority=TaskPriority.HIGH,
        due_date=due,
        next_action_date=next_action,
        max_attempts=2,
    )
    assert task.title == "Prepare Q3 Review"
    assert task.priority == TaskPriority.HIGH
    assert task.attempt_count == 0
    assert task.max_attempts == 2

    # 2. General Update
    updated = task_svc.update_task(
        task_id=task.id,
        title="Prepare Q3 Financial Review",
        description="Expanded description",
        subject_line="Financials Q3 Update",
    )
    assert updated.title == "Prepare Q3 Financial Review"
    assert updated.subject_line == "Financials Q3 Update"

    # 3. Status Transition
    in_progress = task_svc.change_status(
        task_id=task.id,
        new_status=TaskStatus.IN_PROGRESS,
        reason="Work initiated",
    )
    assert in_progress.status == TaskStatus.IN_PROGRESS

    # 4. Priority Transition
    urgent = task_svc.change_priority(
        task_id=task.id,
        new_priority=TaskPriority.URGENT,
        reason="Deadline moved up",
    )
    assert urgent.priority == TaskPriority.URGENT

    # 5. Next Action Date Update
    new_next_action = now + timedelta(days=2)
    with_action = task_svc.update_next_action_date(
        task_id=task.id,
        next_action_date=new_next_action,
    )
    assert with_action.next_action_date is not None


def test_mongo_task_date_validation(mongo_services):
    """Test date parameter validation rejecting invalid types."""
    task_svc = mongo_services["task"]
    with pytest.raises(InvalidTaskDateError):
        task_svc.create_task(title="Invalid Date Task", due_date="not-a-datetime")  # type: ignore


# ==============================================================================
# 5. ATTEMPT INVARIANTS, CEILING & AUTHORIZED OVERRIDE (MONGODB)
# ==============================================================================

def test_mongo_task_attempt_increments_and_ceiling(mongo_services):
    """Test atomic attempt counting, ceiling enforcement, and authorized override."""
    task_svc = mongo_services["task"]

    task = task_svc.create_task(
        title="Attempt Limit Invariant Test",
        max_attempts=2,
    )
    assert task.attempt_count == 0

    # First attempt: succeeds (0 -> 1)
    t1 = task_svc.record_attempt(task_id=task.id, notes="First attempt made")
    assert t1.attempt_count == 1

    # Second attempt: succeeds (1 -> 2, reaching max_attempts)
    t2 = task_svc.record_attempt(task_id=task.id, notes="Second attempt made")
    assert t2.attempt_count == 2

    # Third attempt without override: REJECTED with MaxAttemptsReachedError
    with pytest.raises(MaxAttemptsReachedError) as exc_info:
        task_svc.record_attempt(task_id=task.id, notes="Third unauthorized attempt")
    assert exc_info.value.attempt_count == 2
    assert exc_info.value.max_attempts == 2

    # Attempt with override missing reason: REJECTED
    with pytest.raises(OverrideReasonRequiredError):
        task_svc.record_attempt(
            task_id=task.id,
            authorized_override=True,
            override_reason="",
        )

    # Attempt with valid authorized override: SUCCEEDS (2 -> 3)
    t3 = task_svc.record_attempt(
        task_id=task.id,
        authorized_override=True,
        override_reason="VP approved additional attempt due to technical blocker",
    )
    assert t3.attempt_count == 3


# ==============================================================================
# 6. POSTPONEMENT, COMPLETION & REOPEN INVARIANTS (MONGODB)
# ==============================================================================

def test_mongo_task_postponement(mongo_services):
    """Test postponement preserves original due date in history and requires reason."""
    task_svc = mongo_services["task"]
    hist_svc = mongo_services["history"]

    original_due = datetime.now(timezone.utc) + timedelta(days=2)
    task = task_svc.create_task(title="Postpone Test", due_date=original_due)

    new_due = original_due + timedelta(days=5)

    # Missing reason rejected
    with pytest.raises(PostponementReasonRequiredError):
        task_svc.postpone_task(task_id=task.id, new_due_date=new_due, reason="")

    # Valid postponement
    postponed = task_svc.postpone_task(
        task_id=task.id,
        new_due_date=new_due,
        reason="Client requested extension",
    )
    assert postponed.due_date.replace(microsecond=0) == new_due.replace(microsecond=0)

    # Verify history logged old and new values
    history = hist_svc.get_task_history(task_id=task.id, action="postponed")
    assert len(history) == 1
    assert history[0].reason == "Client requested extension"
    assert history[0].old_value is not None


def test_mongo_task_completion_and_reopen(mongo_services):
    """Test task completion, completion immutability, and reopen invariants."""
    task_svc = mongo_services["task"]

    task = task_svc.create_task(title="Complete and Reopen Test")

    # Complete
    completed = task_svc.complete_task(task_id=task.id)
    assert completed.status == TaskStatus.COMPLETED
    assert completed.completed_at is not None

    # Completing already completed task raises error
    with pytest.raises(TaskAlreadyCompletedError):
        task_svc.complete_task(task_id=task.id)

    # Attempting a completed task raises TaskCompletedError
    with pytest.raises(TaskCompletedError):
        task_svc.record_attempt(task_id=task.id)

    # Reopening without reason rejected
    with pytest.raises(ReopenReasonRequiredError):
        task_svc.reopen_task(task_id=task.id, reason="")

    # Valid reopen
    reopened = task_svc.reopen_task(
        task_id=task.id,
        reason="Quality inspection failed",
    )
    assert reopened.status == TaskStatus.PENDING
    assert reopened.completed_at is None

    # Reopening an already pending task raises TaskNotCompletedError
    with pytest.raises(TaskNotCompletedError):
        task_svc.reopen_task(task_id=task.id, reason="Another reopen")


# ==============================================================================
# 7. TASK FILTERING & PAGINATION (MONGODB)
# ==============================================================================

def test_mongo_task_search_filters_and_pagination(mongo_services):
    """Test multi-criteria filtering, text search, sorting, and pagination."""
    task_svc = mongo_services["task"]

    # Seed unique tasks
    unique_suffix = uuid.uuid4().hex[:6]
    t1 = task_svc.create_task(
        title=f"Alpha Task {unique_suffix}",
        priority=TaskPriority.HIGH,
        status=TaskStatus.PENDING,
    )
    t2 = task_svc.create_task(
        title=f"Beta Task {unique_suffix}",
        priority=TaskPriority.LOW,
        status=TaskStatus.IN_PROGRESS,
    )

    # 1. Filter by priority
    items, total = task_svc.list_tasks(priority=TaskPriority.HIGH, page=1, page_size=20)
    assert any(t.id == t1.id for t in items)

    # 2. Filter by status
    items, total = task_svc.list_tasks(status=TaskStatus.IN_PROGRESS, page=1, page_size=20)
    assert any(t.id == t2.id for t in items)

    # 3. Search query
    items, total = task_svc.list_tasks(search=f"Beta Task {unique_suffix}")
    assert total >= 1
    assert items[0].id == t2.id


# ==============================================================================
# 8. EMBEDDED REMINDERS & FOLLOW-UPS (MONGODB INVARIANT)
# ==============================================================================

def test_mongo_embedded_reminders_and_follow_ups(mongo_services):
    """Test embedded subdocument reminders & follow-ups preserve attempt invariants."""
    task_svc = mongo_services["task"]
    reminder_svc = mongo_services["reminder"]
    follow_up_svc = mongo_services["follow_up"]

    task = task_svc.create_task(title="Embedded Subdoc Invariant Test")
    assert task.attempt_count == 0

    # 1. Create reminder — INVARIANT: must NOT increment attempt_count
    remind_time = datetime.now(timezone.utc) + timedelta(hours=2)
    reminder = reminder_svc.create_reminder(
        task_id=task.id,
        remind_at=remind_time,
        message="Review contract draft",
    )
    assert reminder.message == "Review contract draft"

    re_fetched = task_svc.get_task(task_id=task.id)
    assert re_fetched.attempt_count == 0
    assert len(re_fetched.reminders) == 1

    # 2. Process reminder — INVARIANT: must NOT increment attempt_count
    processed = reminder_svc.process_reminder(reminder_id=reminder.id)
    assert processed.is_sent is True

    re_fetched = task_svc.get_task(task_id=task.id)
    assert re_fetched.attempt_count == 0

    # 3. Delete reminder
    reminder_svc.delete_reminder(reminder_id=reminder.id)
    re_fetched = task_svc.get_task(task_id=task.id)
    assert len(re_fetched.reminders) == 0

    # 4. Create follow-up
    sched_time = datetime.now(timezone.utc) + timedelta(days=1)
    follow_up = follow_up_svc.create_follow_up(
        task_id=task.id,
        scheduled_at=sched_time,
        notes="Call stakeholder",
    )
    assert follow_up.notes == "Call stakeholder"

    re_fetched = task_svc.get_task(task_id=task.id)
    assert len(re_fetched.follow_ups) == 1
    assert re_fetched.attempt_count == 0

    # 5. List follow-ups and due follow-ups
    all_fus = follow_up_svc.list_follow_ups()
    assert len(all_fus) >= 1
    assert any(fu.id == follow_up.id for fu in all_fus)

    task_fus = follow_up_svc.list_follow_ups(task_id=task.id)
    assert len(task_fus) == 1
    assert task_fus[0].id == follow_up.id

    pending_fus = follow_up_svc.list_follow_ups(is_completed=False)
    assert any(fu.id == follow_up.id for fu in pending_fus)

    # 6. Complete follow-up
    completed_fu = follow_up_svc.complete_follow_up(
        follow_up_id=follow_up.id,
        notes="Stakeholder aligned",
    )
    assert completed_fu.completed_at is not None
    assert completed_fu.notes == "Stakeholder aligned"

    completed_fus = follow_up_svc.list_follow_ups(is_completed=True)
    assert any(fu.id == follow_up.id for fu in completed_fus)

    # 7. Delete follow-up
    follow_up_svc.delete_follow_up(follow_up_id=follow_up.id)
    re_fetched = task_svc.get_task(task_id=task.id)
    assert len(re_fetched.follow_ups) == 0


# ==============================================================================
# 9. NOTIFICATION SERVICE BOUNDARY (MONGODB)
# ==============================================================================

def test_mongo_notifications(mongo_services):
    """Test notification creation, deduplication, user scoping, and read tracking."""
    user_svc = mongo_services["user"]
    notif_svc = mongo_services["notif"]

    user1 = user_svc.register_user(
        name="User One",
        email=f"u1_{uuid.uuid4().hex[:6]}@example.com",
        password="Password123!",
    )
    user2 = user_svc.register_user(
        name="User Two",
        email=f"u2_{uuid.uuid4().hex[:6]}@example.com",
        password="Password123!",
    )

    # 1. Create notification with dedup key
    dedup_key = f"alert:{uuid.uuid4().hex}"
    n1 = notif_svc.create_notification(
        user_id=user1.id,
        type="task_assigned",
        title="Task 1 Assigned",
        message="You have a new assignment",
        dedup_key=dedup_key,
    )
    assert n1.title == "Task 1 Assigned"

    # 2. Deduplication check: duplicate call returns existing notification
    n2 = notif_svc.create_notification(
        user_id=user1.id,
        type="task_assigned",
        title="Duplicate Attempt",
        message="Duplicate",
        dedup_key=dedup_key,
    )
    assert n2.id == n1.id

    # 3. User Scoping: User 2 cannot access User 1's notification
    with pytest.raises(NotificationNotFoundError):
        notif_svc.get_notification(user_id=user2.id, notification_id=n1.id)

    # 4. Mark as read
    marked = notif_svc.mark_as_read(user_id=user1.id, notification_id=n1.id)
    assert marked.is_read is True

    # 5. Mark all as read
    notif_svc.create_notification(
        user_id=user1.id,
        type="reminder_due",
        title="Reminder Due",
        message="Upcoming reminder",
    )
    updated_count = notif_svc.mark_all_as_read(user_id=user1.id)
    assert updated_count >= 1


# ==============================================================================
# 10. USER SETTINGS SERVICE BOUNDARY (MONGODB)
# ==============================================================================

def test_mongo_user_settings(mongo_services):
    """Test user settings auto-provisioning, partial updates, and factory reset."""
    user_svc = mongo_services["user"]
    settings_svc = mongo_services["settings"]

    user = user_svc.register_user(
        name="Settings User",
        email=f"set_{uuid.uuid4().hex[:6]}@example.com",
        password="Password123!",
    )

    # Auto-provision
    current = settings_svc.get_user_settings(user_id=user.id)
    assert current.theme == "system"
    assert current.default_task_priority == "medium"

    # Partial Update
    updates = UserSettingsUpdate(theme="dark", default_task_priority="urgent")
    modified = settings_svc.update_user_settings(user_id=user.id, updates=updates)
    assert modified.theme == "dark"
    assert modified.default_task_priority == "urgent"

    # Factory Reset
    reset = settings_svc.reset_user_settings(user_id=user.id)
    assert reset.theme == "system"
    assert reset.default_task_priority == "medium"


# ==============================================================================
# 11. REFRESH TOKEN LIFECYCLE & REPLAY PROTECTION (MONGODB)
# ==============================================================================

def test_mongo_refresh_token_lifecycle_and_replay_protection(mongo_services):
    """Test token generation, rotation, single-token revocation, and replay attack detection."""
    user_svc = mongo_services["user"]

    user = user_svc.register_user(
        name="Token User",
        email=f"tok_{uuid.uuid4().hex[:6]}@example.com",
        password="Password123!",
    )

    # 1. Create Token
    raw_token, doc = user_svc.create_refresh_token_for_user(
        user_id=user.id,
        client_ip="127.0.0.1",
        user_agent="PyTest/Phase30",
    )
    assert raw_token is not None
    assert doc.is_revoked is False

    # 2. Rotate Token (One-time use)
    new_raw, new_doc, rotated_user = user_svc.rotate_refresh_token(
        token_str=raw_token,
        client_ip="127.0.0.1",
        user_agent="PyTest/Phase30",
    )
    assert new_raw != raw_token
    assert new_doc.is_revoked is False
    assert rotated_user.id == user.id

    # 3. Replay Detection: Re-using the already rotated token must fail and revoke all sessions
    with pytest.raises(RefreshTokenRevokedError, match="Replay detected"):
        user_svc.rotate_refresh_token(
            token_str=raw_token,
            client_ip="192.168.1.100",
            user_agent="AttackerAgent",
        )

    # 4. Verify all tokens for the user are now invalidated
    with pytest.raises(RefreshTokenRevokedError):
        user_svc.rotate_refresh_token(token_str=new_raw)
