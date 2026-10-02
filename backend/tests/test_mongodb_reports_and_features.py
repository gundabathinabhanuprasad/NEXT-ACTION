"""Integration and unit tests for MongoDB dual-engine implementations:
- MongoReportService (task summary, task detail, productivity, workload, activity, reminders/follow-ups)
- MongoTaskTemplateService
- MongoRecurringTaskService
- TaskPriority & TaskStatus case-insensitivity
"""

from datetime import datetime, timezone
from typing import Generator
import uuid
import pytest
from pymongo import MongoClient
from pymongo.database import Database

from app.db.mongodb import init_mongo_indexes
from app.models.enums import TaskPriority, TaskStatus, RecurrenceType
from app.schemas.task import TaskCreate, PriorityChangeRequest, StatusChangeRequest
from app.schemas.reports import ReportFilterParams
from app.schemas.task_template import TaskTemplateCreate, TaskTemplateUpdate
from app.schemas.recurring_task import RecurringTaskCreate, RecurringTaskUpdate
from app.persistence.mongodb.report_service import MongoReportService
from app.persistence.mongodb.task_template_service import MongoTaskTemplateService
from app.persistence.mongodb.recurring_task_service import MongoRecurringTaskService
from app.repositories.task_template_repository import TaskTemplateRepository
from app.repositories.recurring_task_repository import RecurringTaskRepository
from app.repositories import (
    ClientRepository,
    TaskHistoryRepository,
    TaskRepository,
    UserRepository,
    WorkflowRepository,
)

TEST_DB_NAME = "nextaction_features_test"
MONGO_TEST_URI = "mongodb://localhost:27017"


@pytest.fixture(scope="module")
def mongo_test_db() -> Generator[Database, None, None]:
    """Provide an isolated, indexed test database against local MongoDB, or skip if unavailable."""
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


def test_task_priority_and_status_case_insensitivity():
    """Verify TaskCreate accepts uppercase/mixed-case priority and status strings."""
    t1 = TaskCreate(
        title="Test Case Normalization",
        status="IN_PROGRESS",  # type: ignore
        priority="HIGH",  # type: ignore
    )
    assert t1.status == TaskStatus.IN_PROGRESS
    assert t1.priority == TaskPriority.HIGH

    t2 = TaskCreate(
        title="Test Case Normalization 2",
        status="completed",  # type: ignore
        priority="urgent",  # type: ignore
    )
    assert t2.status == TaskStatus.COMPLETED
    assert t2.priority == TaskPriority.URGENT

    p_change = PriorityChangeRequest(priority="LOW")  # type: ignore
    assert p_change.priority == TaskPriority.LOW

    s_change = StatusChangeRequest(status="CANCELLED")  # type: ignore
    assert s_change.status == TaskStatus.CANCELLED


def test_mongo_report_service_task_summary(mongo_test_db: Database):
    """Verify MongoReportService.get_task_summary_report aggregates without error."""
    service = MongoReportService()
    service.task_repo = TaskRepository(db=mongo_test_db)
    report = service.get_task_summary_report(filters=None)
    assert hasattr(report, "total_tasks")
    assert hasattr(report, "open_tasks")
    assert hasattr(report, "completed_tasks")
    assert hasattr(report, "status_breakdown")
    assert hasattr(report, "priority_breakdown")


def test_mongo_report_service_task_detail(mongo_test_db: Database):
    """Verify MongoReportService.get_task_detail_report paginates without error."""
    service = MongoReportService()
    service.task_repo = TaskRepository(db=mongo_test_db)
    report = service.get_task_detail_report(page=1, page_size=10)
    assert hasattr(report, "items")
    assert hasattr(report, "total")
    assert report.page == 1
    assert report.page_size == 10


def test_mongo_report_service_productivity(mongo_test_db: Database):
    """Verify MongoReportService.get_productivity_report calculates trends without error."""
    service = MongoReportService()
    service.task_repo = TaskRepository(db=mongo_test_db)
    report = service.get_productivity_report()
    assert hasattr(report, "total_created")
    assert hasattr(report, "total_completed")
    assert hasattr(report, "daily_trends")
    assert isinstance(report.daily_trends, list)


def test_mongo_report_service_workload(mongo_test_db: Database):
    """Verify MongoReportService.get_workload_report groups workloads without error."""
    service = MongoReportService()
    service.task_repo = TaskRepository(db=mongo_test_db)
    report = service.get_workload_report()
    assert hasattr(report, "by_assignee")
    assert hasattr(report, "by_client")
    assert hasattr(report, "by_workflow")


def test_mongo_report_service_activity(mongo_test_db: Database):
    """Verify MongoReportService.get_activity_report logs without error."""
    service = MongoReportService()
    service.history_repo = TaskHistoryRepository(db=mongo_test_db)
    report = service.get_activity_report(page=1, page_size=5)
    assert hasattr(report, "items")
    assert hasattr(report, "total")
    assert hasattr(report, "action_counts")


def test_mongo_report_service_reminders_followups(mongo_test_db: Database):
    """Verify MongoReportService.get_reminders_followups_report queues without error."""
    service = MongoReportService()
    service.task_repo = TaskRepository(db=mongo_test_db)
    report = service.get_reminders_followups_report()
    assert hasattr(report, "summary")
    assert hasattr(report, "reminders")
    assert hasattr(report, "follow_ups")


def test_mongo_task_template_crud(mongo_test_db: Database):
    """Verify MongoTaskTemplateService CRUD lifecycle."""
    repo = TaskTemplateRepository(db=mongo_test_db)
    service = MongoTaskTemplateService(template_repo=repo)
    uid = str(uuid.uuid4())
    tmpl = service.create_task_template(
        name=f"Template Test {uuid.uuid4().hex[:6]}",
        priority=TaskPriority.HIGH,
        created_by_user_id=uid,
    )
    assert tmpl.id is not None

    fetched = service.get_task_template(template_id=tmpl.id)
    assert fetched.id == tmpl.id

    updated = service.update_task_template(
        template_id=tmpl.id,
        current_user_id=uid,
        name=f"Updated {tmpl.name}",
    )
    assert updated.name.startswith("Updated")

    items, total = service.list_task_templates(page=1, page_size=10)
    assert total >= 1

    deleted = service.delete_task_template(template_id=tmpl.id, current_user_id=uid)
    with pytest.raises(Exception):
        service.get_task_template(template_id=tmpl.id)


def test_mongo_recurring_task_crud(mongo_test_db: Database):
    """Verify MongoRecurringTaskService CRUD lifecycle."""
    repo = RecurringTaskRepository(db=mongo_test_db)
    service = MongoRecurringTaskService(recurring_repo=repo)
    uid = str(uuid.uuid4())
    rec = service.create_recurring_task(
        name=f"Daily Standup {uuid.uuid4().hex[:6]}",
        recurrence_type=RecurrenceType.DAILY,
        interval=1,
        priority=TaskPriority.MEDIUM,
        start_date=datetime.now(timezone.utc),
        created_by_user_id=uid,
    )
    assert rec.id is not None

    fetched = service.get_recurring_task(recurring_task_id=rec.id)
    assert fetched.id == rec.id

    updated = service.update_recurring_task(
        recurring_task_id=rec.id,
        current_user_id=uid,
        name=f"Updated {rec.name}",
    )
    assert updated.name.startswith("Updated")

    items, total = service.list_recurring_tasks(page=1, page_size=10)
    assert total >= 1

    service.delete_recurring_task(recurring_task_id=rec.id, current_user_id=uid)
    with pytest.raises(Exception):
        service.get_recurring_task(recurring_task_id=rec.id)

