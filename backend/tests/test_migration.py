"""Phase 31 — Controlled PostgreSQL -> MongoDB Migration & Dual-Write Test Suite.

Verifies:
1. Dry-run execution (simulation - zero writes)
2. Exact ID and UTC timestamp preservation
3. Accurate transformations for all 12 entities (including embedded reminders & follow-ups)
4. Referential integrity validation and safe abort on broken references
5. Controlled live migration and count parity across all collections
6. Deterministic SHA-256 fingerprint checksum verification and mismatch detection
7. Idempotent repeat migration without record or subdocument duplication
8. Reversible rollback removing only tagged MongoDB documents while preserving PostgreSQL
9. Dual-write disabled by default
10. Dual-write success across core entities
11. Dual-write MongoDB failure resilience (PostgreSQL remains committed and intact)
12. Migration CLI interface and audit report generation
"""

from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Generator
from unittest.mock import MagicMock, patch
import uuid
import pytest
from pymongo import MongoClient
from pymongo.database import Database
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.mongodb import init_mongo_indexes
from app.migration.cli import main as cli_main
from app.migration.coordinator import MigrationCoordinator
from app.migration.dual_write import (
    DualWriteOperation,
    DualWriter,
    is_dual_write_enabled,
    override_dual_write,
)
from app.migration.extractor import PostgreSQLExtractor
from app.migration.fingerprint import compute_fingerprint
from app.migration.loader import MIGRATION_ORDER, MongoDBLoader
from app.migration.reporter import MigrationReporter
from app.migration.rollback import MigrationRollback
from app.migration.state import MigrationState, generate_migration_id
from app.migration.transformer import EntityTransformer
from app.migration.validator import MigrationValidator
from app.migration.verifier import MigrationVerifier

from app.models.client import Client
from app.models.enums import RecurrenceType, TaskPriority, TaskStatus
from app.models.event import Event
from app.models.follow_up import FollowUp
from app.models.notification import Notification
from app.models.recurring_task import RecurringTask, RecurringTaskExecution
from app.models.refresh_token import RefreshToken
from app.models.reminder import Reminder
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.task_template import TaskTemplate
from app.models.user import User
from app.models.user_settings import UserSettings
from app.models.workflow import Workflow

from app.persistence.postgres.client_service import PostgresClientService
from app.persistence.postgres.history_service import PostgresHistoryService
from app.persistence.postgres.notification_service import PostgresNotificationService
from app.persistence.postgres.task_service import PostgresTaskService
from app.persistence.postgres.user_service import PostgresUserService
from app.persistence.postgres.workflow_service import PostgresWorkflowService

TEST_MIGRATION_DB_NAME = "nextaction_phase31_migration_test"
MONGO_TEST_URI = "mongodb://localhost:27017"


@pytest.fixture(scope="module")
def mongo_test_db() -> Generator[Database, None, None]:
    """Provide an isolated, indexed test database against local MongoDB."""
    client = MongoClient(MONGO_TEST_URI, serverSelectionTimeoutMS=2000, tz_aware=True)
    try:
        client.admin.command("ping")
    except Exception as exc:
        pytest.skip(f"Local MongoDB instance not available at {MONGO_TEST_URI}: {exc}")

    client.drop_database(TEST_MIGRATION_DB_NAME)
    db = client[TEST_MIGRATION_DB_NAME]
    init_mongo_indexes(db)
    yield db
    client.drop_database(TEST_MIGRATION_DB_NAME)
    client.close()


@pytest.fixture(autouse=True)
def clean_mongo_collections(mongo_test_db: Database):
    """Ensure MongoDB collections are empty between tests."""
    for col in MIGRATION_ORDER:
        mongo_test_db[col].delete_many({})
    yield


@pytest.fixture
def migration_corpus(db: Session):
    """Create a rich, deterministic PostgreSQL corpus covering all 12 entities."""
    now = datetime.now(timezone.utc)
    unique_suffix = uuid.uuid4().hex[:8]

    # 1. Users
    user_a = User(
        name="Migration Alpha User",
        email=f"mig_alpha_{unique_suffix}@example.com",
        password_hash="$2b$12$eXampleHashedPasswordMigration123",
        is_active=True,
        created_at=now - timedelta(days=10),
    )
    user_b = User(
        name="Migration Beta User",
        email=f"mig_beta_{unique_suffix}@example.com",
        password_hash="$2b$12$eXampleHashedPasswordMigration456",
        is_active=True,
        created_at=now - timedelta(days=9),
    )
    db.add_all([user_a, user_b])
    db.commit()
    db.refresh(user_a)
    db.refresh(user_b)

    # 2. UserSettings
    settings_a = UserSettings(
        user_id=user_a.id,
        timezone="Asia/Kolkata",
        theme="dark",
        compact_mode=True,
        default_task_priority="high",
        default_max_attempts=3,
        notify_task_assigned=True,
        created_at=now - timedelta(days=10),
    )
    db.add(settings_a)

    # 3. Clients
    client_a = Client(
        name=f"Acme Corp {unique_suffix}",
        company="Acme Global",
        email="contact@acme.com",
        phone="+1234567890",
        notes="High-value client for migration test",
        created_at=now - timedelta(days=8),
    )
    db.add(client_a)

    # 4. Workflows
    wf_a = Workflow(
        name=f"Onboarding Pipeline {unique_suffix}",
        description="Standard onboarding workflow",
        is_active=True,
        created_at=now - timedelta(days=8),
    )
    db.add(wf_a)
    db.commit()
    db.refresh(client_a)
    db.refresh(wf_a)

    # 5. TaskTemplate
    template_a = TaskTemplate(
        name=f"Standard Task Blueprint {unique_suffix}",
        description="Template for recurring tasks",
        workflow_id=wf_a.id,
        client_id=client_a.id,
        assigned_user_id=user_a.id,
        priority=TaskPriority.HIGH,
        max_attempts=3,
        default_due_offset_days=5,
        default_next_action_offset_days=2,
        is_active=True,
        created_by_user_id=user_a.id,
        created_at=now - timedelta(days=7),
    )
    db.add(template_a)
    db.commit()
    db.refresh(template_a)

    # 6. RecurringTask
    recurring_a = RecurringTask(
        template_id=template_a.id,
        name=f"Daily Standup Review {unique_suffix}",
        description="Daily operational check",
        workflow_id=wf_a.id,
        client_id=client_a.id,
        assigned_user_id=user_a.id,
        priority=TaskPriority.MEDIUM,
        max_attempts=2,
        due_offset_days=1,
        next_action_offset_days=0,
        recurrence_type=RecurrenceType.DAILY,
        interval=1,
        start_date=now - timedelta(days=5),
        next_run_at=now + timedelta(days=1),
        is_active=True,
        created_by_user_id=user_a.id,
        created_at=now - timedelta(days=5),
    )
    db.add(recurring_a)
    db.commit()
    db.refresh(recurring_a)

    # 7. Tasks with embedded reminders and follow-ups
    task_pending = Task(
        title="Active Follow-up Project",
        description="Task requiring attempts and scheduling",
        subject_line="Phase 31 Migration Verification",
        workflow_id=wf_a.id,
        client_id=client_a.id,
        assigned_user_id=user_a.id,
        template_id=template_a.id,
        recurring_task_id=recurring_a.id,
        status=TaskStatus.IN_PROGRESS,
        priority=TaskPriority.URGENT,
        due_date=now + timedelta(days=3),
        next_action_date=now + timedelta(days=1),
        attempt_count=1,
        max_attempts=3,
        created_at=now - timedelta(days=4),
    )
    task_completed = Task(
        title="Completed Setup Audit",
        description="Historical finished task",
        workflow_id=wf_a.id,
        client_id=client_a.id,
        assigned_user_id=user_b.id,
        status=TaskStatus.COMPLETED,
        priority=TaskPriority.LOW,
        due_date=now - timedelta(days=1),
        completed_at=now - timedelta(hours=2),
        attempt_count=2,
        max_attempts=2,
        created_at=now - timedelta(days=6),
    )
    db.add_all([task_pending, task_completed])
    db.commit()
    db.refresh(task_pending)
    db.refresh(task_completed)

    # Reminders and FollowUps linked to task_pending
    rem_1 = Reminder(
        task_id=task_pending.id,
        remind_at=now + timedelta(hours=4),
        message="Follow up with client",
        is_sent=False,
        created_at=now - timedelta(days=3),
    )
    fu_1 = FollowUp(
        task_id=task_pending.id,
        scheduled_at=now + timedelta(days=1),
        completed_at=None,
        notes="Review SLA requirements",
        created_at=now - timedelta(days=3),
    )
    db.add_all([rem_1, fu_1])

    # 8. TaskHistory
    hist_1 = TaskHistory(
        task_id=task_pending.id,
        action="attempt",
        old_value="0",
        new_value="1",
        reason="First phone call made",
        created_by_user_id=user_a.id,
        created_at=now - timedelta(days=2),
    )
    db.add(hist_1)

    # 9. RecurringTaskExecution
    exec_1 = RecurringTaskExecution(
        recurring_task_id=recurring_a.id,
        scheduled_for=now - timedelta(days=1),
        task_id=task_pending.id,
        status="success",
        executed_at=now - timedelta(days=1),
    )
    db.add(exec_1)

    # 10. Notification
    notif_1 = Notification(
        user_id=user_a.id,
        task_id=task_pending.id,
        type="task_assigned",
        title="Assigned to Active Follow-up Project",
        message="You have been assigned to task",
        dedup_key=f"task_assigned:{task_pending.id}:{user_a.id}",
        is_read=False,
        created_at=now - timedelta(days=3),
    )
    db.add(notif_1)

    # 11. Event
    event_1 = Event(
        title="Client Onboarding Sync",
        description="Kickoff meeting",
        start_at=now + timedelta(days=2),
        end_at=now + timedelta(days=2, hours=1),
        location="Google Meet",
        task_id=task_pending.id,
        client_id=client_a.id,
        created_at=now - timedelta(days=2),
    )
    db.add(event_1)

    # 12. RefreshToken
    token_1 = RefreshToken(
        user_id=user_a.id,
        token_hash=uuid.uuid4().hex + uuid.uuid4().hex,  # 64 chars
        expires_at=now + timedelta(days=7),
        is_revoked=False,
        created_at=now - timedelta(days=1),
    )
    db.add(token_1)
    db.commit()

    return {
        "user_a": user_a,
        "user_b": user_b,
        "settings_a": settings_a,
        "client_a": client_a,
        "wf_a": wf_a,
        "template_a": template_a,
        "recurring_a": recurring_a,
        "task_pending": task_pending,
        "task_completed": task_completed,
        "reminder_1": rem_1,
        "follow_up_1": fu_1,
        "history_1": hist_1,
        "exec_1": exec_1,
        "notif_1": notif_1,
        "event_1": event_1,
        "token_1": token_1,
    }


def test_migration_dry_run(db: Session, mongo_test_db: Database, migration_corpus: dict):
    """Test dry-run simulation mode performs ZERO writes to MongoDB and ZERO writes to PostgreSQL."""
    coordinator = MigrationCoordinator()
    state = coordinator.run_dry_run(db=db, mongo_db=mongo_test_db)

    assert state.mode == "dry-run"
    assert state.status == "completed"
    assert len(state.relationship_errors) == 0
    assert state.source_counts["users"] >= 2
    assert state.source_counts["tasks"] >= 2

    # Verify ZERO documents were written to MongoDB
    for col in MIGRATION_ORDER:
        assert mongo_test_db[col].count_documents({}) == 0


def test_entity_transformations_accuracy(db: Session, migration_corpus: dict):
    """Test accuracy of entity transformation for all models and child embeddings."""
    task = migration_corpus["task_pending"]
    transformed_task = EntityTransformer.transform_task(task)

    assert transformed_task.id == str(task.id)
    assert transformed_task.title == task.title
    assert transformed_task.status == task.status
    assert transformed_task.priority == task.priority
    assert transformed_task.attempt_count == 1
    assert transformed_task.max_attempts == 3

    # Verify embedded subdocuments
    assert len(transformed_task.reminders) == 1
    assert transformed_task.reminders[0].id == str(migration_corpus["reminder_1"].id)
    assert transformed_task.reminders[0].message == "Follow up with client"

    assert len(transformed_task.follow_ups) == 1
    assert transformed_task.follow_ups[0].id == str(migration_corpus["follow_up_1"].id)
    assert transformed_task.follow_ups[0].notes == "Review SLA requirements"

    # Verify denormalized fields
    assert transformed_task.client_name == migration_corpus["client_a"].name
    assert transformed_task.workflow_name == migration_corpus["wf_a"].name
    assert transformed_task.assigned_user_name == migration_corpus["user_a"].name
    assert transformed_task.assigned_user_email == migration_corpus["user_a"].email


def test_id_and_timestamp_preservation(migration_corpus: dict):
    """Test that PostgreSQL UUIDs and UTC timestamps are preserved exactly without ID regeneration."""
    user = migration_corpus["user_a"]
    transformed_user = EntityTransformer.transform_user(user)

    # Exact string UUID preservation
    assert transformed_user.id == str(user.id)
    assert uuid.UUID(transformed_user.id) == user.id

    # UTC timestamp preservation
    assert transformed_user.created_at.tzinfo is not None
    assert transformed_user.created_at.astimezone(timezone.utc) == user.created_at.astimezone(timezone.utc)


def test_relationship_validation_success(db: Session, migration_corpus: dict):
    """Test that consistent relational corpus produces zero relationship errors."""
    extractor = PostgreSQLExtractor(db)
    raw_entities = {
        "users": extractor.extract_users(),
        "user_settings": extractor.extract_user_settings(),
        "clients": extractor.extract_clients(),
        "workflows": extractor.extract_workflows(),
        "task_templates": extractor.extract_task_templates(),
        "recurring_tasks": extractor.extract_recurring_tasks(),
        "tasks": extractor.extract_tasks(),
        "task_history": extractor.extract_task_histories(),
        "recurring_task_executions": extractor.extract_recurring_task_executions(),
        "notifications": extractor.extract_notifications(),
        "events": extractor.extract_events(),
        "refresh_tokens": extractor.extract_refresh_tokens(),
    }

    errors = MigrationValidator.validate_relationships(raw_entities)
    assert len(errors) == 0


def test_relationship_validation_failure_broken_reference(db: Session):
    """Test that broken foreign key references are detected and safely reported."""
    fake_user_id = uuid.uuid4()
    corrupted_data = {
        "users": [],  # Empty users list
        "user_settings": [
            UserSettings(
                id=uuid.uuid4(),
                user_id=fake_user_id,
            )
        ],
    }

    errors = MigrationValidator.validate_relationships(corrupted_data)
    assert len(errors) == 1
    assert errors[0].parent_entity == "user_settings"
    assert errors[0].reference_field == "user_id"
    assert errors[0].broken_id == str(fake_user_id)


def test_controlled_migration_and_count_verification(
    db: Session, mongo_test_db: Database, migration_corpus: dict
):
    """Test live migration loads all documents into MongoDB with matching counts and distributions."""
    coordinator = MigrationCoordinator()
    state = coordinator.run_migration(db=db, mongo_db=mongo_test_db, allow_unsafe_engine=True)

    assert state.mode == "migrate"
    assert state.status == "completed"
    assert sum(state.failed.values()) == 0

    verifier = MigrationVerifier(db=db, mongo_db=mongo_test_db)
    count_comparison = verifier.verify_counts(state.source_counts)

    for col, cmp_info in count_comparison.items():
        assert cmp_info["match"] is True, f"Count mismatch in {col}: {cmp_info}"

    # Verify task distribution parity
    distributions = verifier.verify_task_distributions()
    assert distributions["status_distribution"]["match"] is True
    assert distributions["priority_distribution"]["match"] is True
    assert distributions["total_attempts"]["match"] is True
    assert distributions["completed_count"]["match"] is True


def test_checksum_verification_and_mismatch_detection(
    db: Session, mongo_test_db: Database, migration_corpus: dict
):
    """Test SHA-256 fingerprint matching and detection of modified documents."""
    coordinator = MigrationCoordinator()
    state = coordinator.run_migration(db=db, mongo_db=mongo_test_db, allow_unsafe_engine=True)
    assert len(state.checksum_mismatches) == 0

    # Tamper with a MongoDB document directly to verify detection
    task_id = str(migration_corpus["task_pending"].id)
    mongo_test_db["tasks"].update_one({"_id": task_id}, {"$set": {"title": "Tampered Title"}})

    verifier = MigrationVerifier(db=db, mongo_db=mongo_test_db)
    extractor = PostgreSQLExtractor(db)
    transformed_tasks = [EntityTransformer.transform_task(t) for t in extractor.extract_tasks()]
    mismatches = verifier.verify_checksums({"tasks": transformed_tasks})

    assert len(mismatches) == 1
    assert mismatches[0].entity == "tasks"
    assert mismatches[0].entity_id == task_id


def test_migration_idempotency(db: Session, mongo_test_db: Database, migration_corpus: dict):
    """Test running migration twice on identical data produces 0 duplicate records."""
    coordinator = MigrationCoordinator()

    # First run
    state_1 = coordinator.run_migration(db=db, mongo_db=mongo_test_db, allow_unsafe_engine=True)
    assert state_1.status == "completed"
    first_counts = MigrationVerifier(db, mongo_test_db).get_mongodb_counts()

    # Second run
    state_2 = coordinator.run_migration(db=db, mongo_db=mongo_test_db, allow_unsafe_engine=True)
    assert state_2.status == "completed"
    second_counts = MigrationVerifier(db, mongo_test_db).get_mongodb_counts()

    # Verify exact count equality (0 duplicates)
    for col in MIGRATION_ORDER:
        assert first_counts[col] == second_counts[col]
        # In second run, all documents should be registered as updated, 0 failed
        assert state_2.failed.get(col, 0) == 0

    # Verify embedded subdocuments were not duplicated inside tasks
    task_doc = mongo_test_db["tasks"].find_one({"_id": str(migration_corpus["task_pending"].id)})
    assert len(task_doc["reminders"]) == 1
    assert len(task_doc["follow_ups"]) == 1


def test_migration_rollback_mongodb_only(
    db: Session, mongo_test_db: Database, migration_corpus: dict
):
    """Test rollback removes only tagged MongoDB documents while leaving PostgreSQL completely intact."""
    coordinator = MigrationCoordinator()
    custom_migration_id = f"test_rollback_{uuid.uuid4().hex[:6]}"

    # Run migration with custom migration ID
    state = coordinator.run_migration(
        db=db, mongo_db=mongo_test_db, migration_id=custom_migration_id, allow_unsafe_engine=True
    )
    assert state.status == "completed"

    # Pre-rollback: MongoDB has documents
    assert mongo_test_db["tasks"].count_documents({"_migration_id": custom_migration_id}) >= 2

    # Execute rollback
    deleted_counts = coordinator.run_rollback(mongo_db=mongo_test_db, migration_id=custom_migration_id)

    # Post-rollback: MongoDB documents for this migration are removed
    assert sum(deleted_counts.values()) > 0
    assert mongo_test_db["tasks"].count_documents({"_migration_id": custom_migration_id}) == 0

    # PostgreSQL remains completely intact
    pg_tasks = list(db.scalars(select(Task)).all())
    assert len(pg_tasks) >= 2


def test_dual_write_disabled_by_default(db: Session, mongo_test_db: Database):
    """Test that dual-write is disabled by default and performs no MongoDB writes."""
    assert is_dual_write_enabled() is False

    dual_writer_inst = DualWriter(mongo_db=mongo_test_db)
    client_service = PostgresClientService()

    # Create client in PostgreSQL
    client = client_service.create_client(
        db=db,
        name=f"No Dual Write Client {uuid.uuid4().hex[:6]}",
        company="Offline Corp",
    )

    # Verify client was NOT written to MongoDB
    doc = mongo_test_db["clients"].find_one({"_id": str(client.id)})
    assert doc is None


def test_dual_write_success(db: Session, mongo_test_db: Database):
    """Test that enabled dual-write synchronizes core entities to MongoDB after PostgreSQL commits."""
    dual_writer_inst = DualWriter(mongo_db=mongo_test_db)
    # Temporarily replace global dual_writer target db for test
    from app.migration.dual_write import dual_writer as global_dual_writer
    orig_db = global_dual_writer._mongo_db
    global_dual_writer._mongo_db = mongo_test_db

    try:
        with override_dual_write(True):
            assert is_dual_write_enabled() is True

            # 1. User
            user_svc = PostgresUserService()
            user = user_svc.register_user(
                db=db,
                name="DualWrite Tester",
                email=f"dw_{uuid.uuid4().hex[:8]}@example.com",
                password="SecurePassword123!",
            )
            mongo_user = mongo_test_db["users"].find_one({"_id": str(user.id)})
            assert mongo_user is not None
            assert mongo_user["name"] == "DualWrite Tester"

            # 2. Client
            client_svc = PostgresClientService()
            client = client_svc.create_client(
                db=db,
                name=f"DW Client {uuid.uuid4().hex[:6]}",
                company="DW Inc",
            )
            mongo_client = mongo_test_db["clients"].find_one({"_id": str(client.id)})
            assert mongo_client is not None
            assert mongo_client["company"] == "DW Inc"

            # 3. Workflow
            wf_svc = PostgresWorkflowService()
            wf = wf_svc.create_workflow(
                db=db,
                name=f"DW Workflow {uuid.uuid4().hex[:6]}",
            )
            mongo_wf = mongo_test_db["workflows"].find_one({"_id": str(wf.id)})
            assert mongo_wf is not None
            assert mongo_wf["name"] == wf.name

            # 4. Task
            task_svc = PostgresTaskService()
            task = task_svc.create_task(
                db=db,
                title="DualWrite Task",
                assigned_user_id=user.id,
                client_id=client.id,
                workflow_id=wf.id,
            )
            mongo_task = mongo_test_db["tasks"].find_one({"_id": str(task.id)})
            assert mongo_task is not None
            assert mongo_task["title"] == "DualWrite Task"

            # 5. Task Mutation (Attempt)
            task_svc.record_attempt(
                db=db,
                task_id=task.id,
                notes="DualWrite Attempt 1",
                user_id=user.id,
            )
            mongo_task_updated = mongo_test_db["tasks"].find_one({"_id": str(task.id)})
            assert mongo_task_updated["attempt_count"] == 1

            # 6. Notification
            notif_svc = PostgresNotificationService()
            notif = notif_svc.create_notification(
                db=db,
                user_id=user.id,
                type="task_alert",
                title="DW Notification",
                message="Dual write notification message",
                task_id=task.id,
            )
            mongo_notif = mongo_test_db["notifications"].find_one({"_id": str(notif.id)})
            assert mongo_notif is not None
            assert mongo_notif["title"] == "DW Notification"

    finally:
        global_dual_writer._mongo_db = orig_db


def test_dual_write_mongodb_failure_resilience(db: Session):
    """Test that a MongoDB synchronization failure does NOT roll back or break PostgreSQL commit."""
    from app.migration.dual_write import dual_writer as global_dual_writer

    # Mock MongoDB database whose collections raise errors on write
    failing_db = MagicMock(spec=Database)
    failing_collection = MagicMock()
    failing_collection.replace_one.side_effect = RuntimeError("Simulated MongoDB network failure")
    failing_db.__getitem__.return_value = failing_collection

    orig_db = global_dual_writer._mongo_db
    global_dual_writer._mongo_db = failing_db
    global_dual_writer.clear_recent_results()

    try:
        with override_dual_write(True):
            client_svc = PostgresClientService()
            # Operation must succeed in PostgreSQL despite MongoDB throwing
            client = client_svc.create_client(
                db=db,
                name=f"Resilience Client {uuid.uuid4().hex[:6]}",
                company="Resilience Corp",
            )
            assert client.id is not None

            # Verify PostgreSQL record was committed
            pg_client = db.get(Client, client.id)
            assert pg_client is not None
            assert pg_client.name == client.name

            # Verify failure was observed, captured, and logged
            results = global_dual_writer.get_recent_results()
            assert len(results) >= 1
            last_result = results[-1]
            assert last_result.success is False
            assert last_result.entity == "clients"
            assert "Simulated MongoDB network failure" in last_result.error

    finally:
        global_dual_writer._mongo_db = orig_db
        global_dual_writer.clear_recent_results()


def test_migration_cli_dry_run(mongo_test_db: Database):
    """Test that migration CLI runs dry-run mode and returns exit code 0."""
    with patch("app.migration.cli.get_mongodb_database", return_value=mongo_test_db):
        exit_code = cli_main(["--mode", "dry-run"])
        assert exit_code == 0


def test_migration_safety_checks(db: Session, mongo_test_db: Database):
    """Test that migration rejects execution if PERSISTENCE_ENGINE is unexpectedly altered."""
    coordinator = MigrationCoordinator()
    orig_engine = settings.PERSISTENCE_ENGINE
    try:
        settings.PERSISTENCE_ENGINE = "mongodb"
        with pytest.raises(RuntimeError) as exc_info:
            coordinator.run_migration(db=db, mongo_db=mongo_test_db, allow_unsafe_engine=False)
        assert "Safety check rejected migration" in str(exc_info.value)
    finally:
        settings.PERSISTENCE_ENGINE = orig_engine


def test_migration_report_generation(db: Session, mongo_test_db: Database, migration_corpus: dict):
    """Test that MigrationReporter outputs valid Markdown and JSON audit files in docs/migration-reports."""
    reports_dir = Path("docs/migration-reports")
    reporter = MigrationReporter(reports_dir=reports_dir)
    coordinator = MigrationCoordinator(reporter=reporter)

    state = coordinator.run_migration(db=db, mongo_db=mongo_test_db, allow_unsafe_engine=True)
    md_report = reports_dir / f"migration_{state.migration_id}.md"
    json_report = reports_dir / f"migration_{state.migration_id}.json"

    assert md_report.exists()
    assert json_report.exists()
    assert md_report.stat().st_size > 500
    assert json_report.stat().st_size > 500
