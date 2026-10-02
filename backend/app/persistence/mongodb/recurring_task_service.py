"""MongoDB RecurringTask Service implementation."""

import calendar
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.documents.recurring_task import RecurringTaskDocument, RecurringTaskExecutionDocument
from app.models.enums import RecurrenceType, TaskPriority
from app.repositories import (
    ClientRepository,
    RecurringTaskExecutionRepository,
    RecurringTaskRepository,
    TaskTemplateRepository,
    UserRepository,
    WorkflowRepository,
)
from app.services.exceptions import (
    ClientNotFoundError,
    InactiveUserError,
    RecurringTaskNotFoundError,
    TaskTemplateNotFoundError,
    UnauthorizedRecurringTaskAccessError,
    UserNotFoundError,
    WorkflowNotFoundError,
)


def compute_next_run(
    current_run: datetime,
    recurrence_type: RecurrenceType,
    interval: int,
    day_of_week: Optional[int] = None,
    day_of_month: Optional[int] = None,
) -> datetime:
    """Compute the next scheduled run datetime given recurrence parameters and calendar boundaries."""
    if interval < 1:
        interval = 1

    if recurrence_type == RecurrenceType.DAILY or recurrence_type == RecurrenceType.CUSTOM_INTERVAL:
        return current_run + timedelta(days=interval)

    elif recurrence_type == RecurrenceType.WEEKLY:
        next_date = current_run + timedelta(weeks=interval)
        if day_of_week is not None and 0 <= day_of_week <= 6:
            current_weekday = next_date.weekday()
            diff = day_of_week - current_weekday
            next_date = next_date + timedelta(days=diff)
        return next_date

    elif recurrence_type == RecurrenceType.MONTHLY:
        target_month_raw = current_run.month + interval
        target_year = current_run.year + (target_month_raw - 1) // 12
        target_month = ((target_month_raw - 1) % 12) + 1

        target_day = day_of_month if day_of_month is not None else current_run.day
        max_days = calendar.monthrange(target_year, target_month)[1]
        effective_day = min(target_day, max_days)

        return current_run.replace(
            year=target_year,
            month=target_month,
            day=effective_day,
        )

    return current_run + timedelta(days=interval)


class MongoRecurringTaskService:
    """Recurring task schedule service backed by MongoDB recurring_tasks collection."""

    def __init__(
        self,
        recurring_repo: Optional[RecurringTaskRepository] = None,
        execution_repo: Optional[RecurringTaskExecutionRepository] = None,
        template_repo: Optional[TaskTemplateRepository] = None,
        user_repo: Optional[UserRepository] = None,
        client_repo: Optional[ClientRepository] = None,
        workflow_repo: Optional[WorkflowRepository] = None,
    ):
        self.recurring_repo = recurring_repo or RecurringTaskRepository()
        self.execution_repo = execution_repo or RecurringTaskExecutionRepository()
        self.template_repo = template_repo or TaskTemplateRepository()
        self.user_repo = user_repo or UserRepository()
        self.client_repo = client_repo or ClientRepository()
        self.workflow_repo = workflow_repo or WorkflowRepository()

    def _to_doc(self, raw: Dict[str, Any]) -> RecurringTaskDocument:
        """Convert BSON dict to validated RecurringTaskDocument."""
        data = dict(raw)
        if "_id" in data:
            data["id"] = str(data.pop("_id"))
        return RecurringTaskDocument.model_validate(data)

    def get_recurring_task(
        self,
        db: Any = None,
        recurring_task_id: Union[str, uuid.UUID] = "",
    ) -> RecurringTaskDocument:
        """Retrieve recurring task by ID or raise RecurringTaskNotFoundError."""
        rec = self.recurring_repo.get_by_id(recurring_task_id)
        if not rec:
            raise RecurringTaskNotFoundError(recurring_task_id)
        return self._to_doc(rec)

    def list_recurring_tasks(
        self,
        db: Any = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[RecurringTaskDocument], int]:
        """List recurring task definitions with optional search, active filtering, and pagination."""
        items, total = self.recurring_repo.list_recurring(
            is_active=is_active,
            created_by_user_id=created_by_user_id,
            search=search,
            page=page,
            page_size=page_size,
        )
        return [self._to_doc(i) for i in items], total

    def create_recurring_task(
        self,
        db: Any = None,
        name: str = "",
        start_date: datetime = datetime.now(timezone.utc),
        created_by_user_id: Union[str, uuid.UUID] = "",
        template_id: Optional[Union[str, uuid.UUID]] = None,
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        priority: TaskPriority = TaskPriority.MEDIUM,
        max_attempts: int = 2,
        due_offset_days: Optional[int] = None,
        next_action_offset_days: Optional[int] = None,
        recurrence_type: RecurrenceType = RecurrenceType.DAILY,
        interval: int = 1,
        day_of_week: Optional[int] = None,
        day_of_month: Optional[int] = None,
        end_date: Optional[datetime] = None,
        is_active: bool = True,
    ) -> RecurringTaskDocument:
        """Create a new recurring task schedule definition."""
        if template_id is not None:
            tpl = self.template_repo.get_by_id(template_id)
            if not tpl:
                raise TaskTemplateNotFoundError(template_id)

        if client_id is not None:
            client = self.client_repo.get_by_id(client_id)
            if not client:
                raise ClientNotFoundError(client_id)

        if workflow_id is not None:
            wf = self.workflow_repo.get_by_id(workflow_id)
            if not wf:
                raise WorkflowNotFoundError(workflow_id)

        if assigned_user_id is not None:
            user = self.user_repo.get_by_id(assigned_user_id)
            if not user:
                raise UserNotFoundError(assigned_user_id)
            if not user.get("is_active", True):
                raise InactiveUserError()

        doc = RecurringTaskDocument(
            name=name.strip(),
            start_date=start_date,
            next_run_at=start_date,
            created_by_user_id=str(created_by_user_id),
            template_id=str(template_id) if template_id is not None else None,
            description=description.strip() if description else None,
            subject_line=subject_line.strip() if subject_line else None,
            workflow_id=str(workflow_id) if workflow_id is not None else None,
            client_id=str(client_id) if client_id is not None else None,
            assigned_user_id=str(assigned_user_id) if assigned_user_id is not None else None,
            priority=priority,
            max_attempts=max_attempts,
            due_offset_days=due_offset_days,
            next_action_offset_days=next_action_offset_days,
            recurrence_type=recurrence_type,
            interval=interval,
            day_of_week=day_of_week,
            day_of_month=day_of_month,
            end_date=end_date,
            is_active=is_active,
        )
        saved = self.recurring_repo.create(doc)
        return self._to_doc(saved)

    def update_recurring_task(
        self,
        db: Any = None,
        recurring_task_id: Union[str, uuid.UUID] = "",
        current_user_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        template_id: Optional[Union[str, uuid.UUID]] = None,
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        priority: Optional[TaskPriority] = None,
        max_attempts: Optional[int] = None,
        due_offset_days: Optional[int] = None,
        next_action_offset_days: Optional[int] = None,
        recurrence_type: Optional[RecurrenceType] = None,
        interval: Optional[int] = None,
        day_of_week: Optional[int] = None,
        day_of_month: Optional[int] = None,
        start_date: Optional[datetime] = None,
        next_run_at: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        is_active: Optional[bool] = None,
    ) -> RecurringTaskDocument:
        """Update recurring task schedule with authorization check."""
        rec = self.get_recurring_task(recurring_task_id=recurring_task_id)
        if str(rec.created_by_user_id) != str(current_user_id):
            raise UnauthorizedRecurringTaskAccessError(recurring_task_id)

        update_fields: Dict[str, Any] = {}
        if name is not None:
            update_fields["name"] = name.strip()
        if template_id is not None:
            tpl = self.template_repo.get_by_id(template_id)
            if not tpl:
                raise TaskTemplateNotFoundError(template_id)
            update_fields["template_id"] = str(template_id)
        if description is not None:
            update_fields["description"] = description.strip() if description else None
        if subject_line is not None:
            update_fields["subject_line"] = subject_line.strip() if subject_line else None
        if workflow_id is not None:
            wf = self.workflow_repo.get_by_id(workflow_id)
            if not wf:
                raise WorkflowNotFoundError(workflow_id)
            update_fields["workflow_id"] = str(workflow_id)
        if client_id is not None:
            client = self.client_repo.get_by_id(client_id)
            if not client:
                raise ClientNotFoundError(client_id)
            update_fields["client_id"] = str(client_id)
        if assigned_user_id is not None:
            user = self.user_repo.get_by_id(assigned_user_id)
            if not user:
                raise UserNotFoundError(assigned_user_id)
            if not user.get("is_active", True):
                raise InactiveUserError()
            update_fields["assigned_user_id"] = str(assigned_user_id)
        if priority is not None:
            update_fields["priority"] = priority.value if hasattr(priority, "value") else str(priority)
        if max_attempts is not None:
            update_fields["max_attempts"] = max_attempts
        if due_offset_days is not None:
            update_fields["due_offset_days"] = due_offset_days
        if next_action_offset_days is not None:
            update_fields["next_action_offset_days"] = next_action_offset_days
        if recurrence_type is not None:
            update_fields["recurrence_type"] = recurrence_type.value if hasattr(recurrence_type, "value") else str(recurrence_type)
        if interval is not None:
            update_fields["interval"] = interval
        if day_of_week is not None:
            update_fields["day_of_week"] = day_of_week
        if day_of_month is not None:
            update_fields["day_of_month"] = day_of_month
        if start_date is not None:
            update_fields["start_date"] = start_date
        if next_run_at is not None:
            update_fields["next_run_at"] = next_run_at
        if end_date is not None:
            update_fields["end_date"] = end_date
        if is_active is not None:
            update_fields["is_active"] = is_active

        updated = self.recurring_repo.update(recurring_task_id, update_fields)
        if not updated:
            raise RecurringTaskNotFoundError(recurring_task_id)
        return self._to_doc(updated)

    def delete_recurring_task(
        self,
        db: Any = None,
        recurring_task_id: Union[str, uuid.UUID] = "",
        current_user_id: Union[str, uuid.UUID] = "",
    ) -> None:
        """Delete recurring task definition with authorization check."""
        rec = self.get_recurring_task(recurring_task_id=recurring_task_id)
        if str(rec.created_by_user_id) != str(current_user_id):
            raise UnauthorizedRecurringTaskAccessError(recurring_task_id)
        self.recurring_repo.delete(recurring_task_id)

    def evaluate_recurring_tasks(
        self,
        db: Any = None,
        max_evaluations: int = 50,
        target_time: Optional[datetime] = None,
    ) -> Tuple[int, int, List[Any]]:
        """Evaluate due recurring tasks and generate concrete tasks idempotently."""
        now = target_time or datetime.now(timezone.utc)
        due_items = self.recurring_repo.list_due(before_timestamp=now, limit=max_evaluations)

        from app.services.task_service import create_task
        from app.services.history_service import log_history

        created_tasks: List[Any] = []
        evaluated_count = 0

        for raw_rec in due_items:
            rec = self._to_doc(raw_rec)
            evaluated_count += 1
            slot_time = rec.next_run_at

            if self.execution_repo.is_already_executed(rec.id, slot_time):
                # Advance schedule past this slot
                next_slot = compute_next_run(
                    slot_time,
                    rec.recurrence_type,
                    rec.interval,
                    rec.day_of_week,
                    rec.day_of_month,
                )
                self.recurring_repo.update_next_run(rec.id, next_run_at=next_slot, last_run_at=slot_time)
                continue

            # Compute effective offsets
            due_date = None
            if rec.due_offset_days is not None:
                due_date = slot_time + timedelta(days=rec.due_offset_days)

            next_action_date = None
            if rec.next_action_offset_days is not None:
                next_action_date = slot_time + timedelta(days=rec.next_action_offset_days)

            created_task = create_task(
                db=db,
                title=rec.name,
                description=rec.description,
                subject_line=rec.subject_line,
                workflow_id=rec.workflow_id,
                client_id=rec.client_id,
                assigned_user_id=rec.assigned_user_id,
                template_id=rec.template_id,
                recurring_task_id=rec.id,
                status=TaskPriority.MEDIUM,  # type: ignore
                priority=rec.priority,
                max_attempts=rec.max_attempts,
                due_date=due_date,
                next_action_date=next_action_date,
                created_by_user_id=rec.created_by_user_id,
            )

            # Record execution run
            exec_doc = RecurringTaskExecutionDocument(
                recurring_task_id=rec.id,
                scheduled_for=slot_time,
                task_id=str(created_task.id),
                status="success",
            )
            self.execution_repo.record_execution(exec_doc)

            # Advance next_run_at
            next_slot = compute_next_run(
                slot_time,
                rec.recurrence_type,
                rec.interval,
                rec.day_of_week,
                rec.day_of_month,
            )
            self.recurring_repo.update_next_run(rec.id, next_run_at=next_slot, last_run_at=slot_time)

            log_history(
                db=db,
                task_id=created_task.id,
                action="created_from_recurring",
                old_value=None,
                new_value=f"Recurring: {rec.name} ({rec.id})",
                reason=f"Generated from RecurringTask '{rec.name}' for schedule slot {slot_time.isoformat()}",
                created_by_user_id=rec.created_by_user_id,
            )
            created_tasks.append(created_task)

        return evaluated_count, len(created_tasks), created_tasks
