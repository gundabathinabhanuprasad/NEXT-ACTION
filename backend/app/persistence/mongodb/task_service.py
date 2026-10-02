"""MongoDB Task Service implementation preserving exact business rules and invariants."""

from datetime import datetime, timezone
import logging
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.documents.common import utcnow
from app.documents.task import TaskDocument
from app.documents.task_history import TaskHistoryDocument
from app.models.enums import TaskPriority, TaskStatus
from app.repositories import (
    ClientRepository,
    TaskHistoryRepository,
    TaskRepository,
    UserRepository,
    WorkflowRepository,
)
from app.services.exceptions import (
    ClientNotFoundError,
    InactiveUserError,
    InvalidTaskDateError,
    MaxAttemptsReachedError,
    OverrideReasonRequiredError,
    PostponementReasonRequiredError,
    ReopenReasonRequiredError,
    TaskAlreadyCompletedError,
    TaskCancelledError,
    TaskCompletedError,
    TaskNotCompletedError,
    TaskNotFoundError,
    UserNotFoundError,
    WorkflowNotFoundError,
)

logger = logging.getLogger("nextaction.persistence.mongodb.task")


def validate_task_dates(
    due_date: Optional[datetime] = None,
    next_action_date: Optional[datetime] = None,
) -> None:
    """Validate task date parameters ensuring datetime types."""
    if due_date is not None and not isinstance(due_date, datetime):
        raise InvalidTaskDateError("due_date must be a valid datetime instance.")
    if next_action_date is not None and not isinstance(next_action_date, datetime):
        raise InvalidTaskDateError("next_action_date must be a valid datetime instance.")


class MongoTaskService:
    """Task service implementation using MongoDB collections and repositories."""

    def __init__(
        self,
        task_repo: Optional[TaskRepository] = None,
        history_repo: Optional[TaskHistoryRepository] = None,
        user_repo: Optional[UserRepository] = None,
        client_repo: Optional[ClientRepository] = None,
        workflow_repo: Optional[WorkflowRepository] = None,
    ):
        self.task_repo = task_repo or TaskRepository()
        self.history_repo = history_repo or TaskHistoryRepository()
        self.user_repo = user_repo or UserRepository()
        self.client_repo = client_repo or ClientRepository()
        self.workflow_repo = workflow_repo or WorkflowRepository()

    def _to_doc(self, raw_data: Optional[Dict[str, Any]]) -> TaskDocument:
        """Hydrate dictionary or document into strongly typed TaskDocument."""
        if raw_data is None:
            raise TaskNotFoundError("Unknown")
        return TaskDocument.model_validate(raw_data)

    def get_task(self, db: Any = None, task_id: Union[str, uuid.UUID] = "") -> TaskDocument:
        """Retrieve task by ID or raise TaskNotFoundError."""
        doc_dict = self.task_repo.get_by_id(task_id)
        if not doc_dict:
            raise TaskNotFoundError(task_id)
        return self._to_doc(doc_dict)

    def create_task(
        self,
        db: Any = None,
        title: str = "",
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        template_id: Optional[Union[str, uuid.UUID]] = None,
        recurring_task_id: Optional[Union[str, uuid.UUID]] = None,
        status: TaskStatus = TaskStatus.PENDING,
        priority: TaskPriority = TaskPriority.MEDIUM,
        due_date: Optional[datetime] = None,
        next_action_date: Optional[datetime] = None,
        max_attempts: int = 2,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Create a new Task document and log initial history."""
        validate_task_dates(due_date=due_date, next_action_date=next_action_date)

        assigned_user_name: Optional[str] = None
        assigned_user_email: Optional[str] = None
        if assigned_user_id is not None:
            user = self.user_repo.get_by_id(assigned_user_id)
            if not user:
                raise UserNotFoundError(assigned_user_id)
            if not user.get("is_active", True):
                raise InactiveUserError(f"User {assigned_user_id} is inactive and cannot be assigned tasks.")
            assigned_user_name = user.get("name")
            assigned_user_email = user.get("email")

        client_name: Optional[str] = None
        if client_id is not None:
            client = self.client_repo.get_by_id(client_id)
            if not client:
                raise ClientNotFoundError(client_id)
            client_name = client.get("name")

        workflow_name: Optional[str] = None
        if workflow_id is not None:
            wf = self.workflow_repo.get_by_id(workflow_id)
            if not wf:
                raise WorkflowNotFoundError(workflow_id)
            workflow_name = wf.get("name")

        task = TaskDocument(
            title=title,
            description=description,
            subject_line=subject_line,
            client_id=str(client_id) if client_id is not None else None,
            workflow_id=str(workflow_id) if workflow_id is not None else None,
            assigned_user_id=str(assigned_user_id) if assigned_user_id is not None else None,
            template_id=str(template_id) if template_id is not None else None,
            recurring_task_id=str(recurring_task_id) if recurring_task_id is not None else None,
            status=status,
            priority=priority,
            due_date=due_date,
            next_action_date=next_action_date,
            max_attempts=max_attempts,
            client_name=client_name,
            workflow_name=workflow_name,
            assigned_user_name=assigned_user_name,
            assigned_user_email=assigned_user_email,
        )

        saved = self.task_repo.create(task)
        self.history_repo.log_history(
            task_id=task.id,
            action="created",
            new_value=task.title,
            created_by_user_id=created_by_user_id,
        )
        return self._to_doc(saved)

    def update_task(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        title: Optional[str] = None,
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Update mutable task metadata fields and log audit history."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskCompletedError(task_id, action="update")
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="update")

        updates: Dict[str, Any] = {}
        if title is not None and title.strip():
            old_title = task.title
            new_title = title.strip()
            if old_title != new_title:
                updates["title"] = new_title
                self.history_repo.log_history(
                    task_id=task.id,
                    action="title_updated",
                    old_value=old_title,
                    new_value=new_title,
                    created_by_user_id=user_id,
                )

        if description is not None:
            old_desc = task.description or ""
            new_desc = description.strip() if description else ""
            if old_desc != new_desc:
                updates["description"] = new_desc or None
                self.history_repo.log_history(
                    task_id=task.id,
                    action="description_updated",
                    old_value=old_desc,
                    new_value=new_desc,
                    created_by_user_id=user_id,
                )

        if subject_line is not None:
            old_sub = task.subject_line or ""
            new_sub = subject_line.strip() if subject_line else ""
            if old_sub != new_sub:
                updates["subject_line"] = new_sub or None
                self.history_repo.log_history(
                    task_id=task.id,
                    action="subject_line_updated",
                    old_value=old_sub,
                    new_value=new_sub,
                    created_by_user_id=user_id,
                )

        if updates:
            updated = self.task_repo.update(task.id, updates)
            return self._to_doc(updated)
        return task

    def change_status(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        new_status: TaskStatus = TaskStatus.PENDING,
        user_id: Optional[Union[str, uuid.UUID]] = None,
        reason: Optional[str] = None,
    ) -> TaskDocument:
        """Change task status preserving completed/reopen invariants."""
        task = self.get_task(task_id=task_id)
        if task.status == new_status:
            return task

        if task.status == TaskStatus.COMPLETED and new_status != TaskStatus.COMPLETED:
            raise TaskAlreadyCompletedError(task_id, action="change_status")

        old_status_val = task.status.value if hasattr(task.status, "value") else str(task.status)
        new_status_val = new_status.value if hasattr(new_status, "value") else str(new_status)

        updates: Dict[str, Any] = {"status": new_status_val}
        if new_status == TaskStatus.COMPLETED:
            updates["completed_at"] = utcnow()

        updated = self.task_repo.update(task.id, updates)
        self.history_repo.log_history(
            task_id=task.id,
            action="status_changed",
            old_value=old_status_val,
            new_value=new_status_val,
            reason=reason.strip() if reason else None,
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def change_priority(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        new_priority: TaskPriority = TaskPriority.MEDIUM,
        user_id: Optional[Union[str, uuid.UUID]] = None,
        reason: Optional[str] = None,
    ) -> TaskDocument:
        """Update task priority with history tracking."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskCompletedError(task_id, action="change_priority")
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="change_priority")

        if task.priority == new_priority:
            return task

        old_prio_val = task.priority.value if hasattr(task.priority, "value") else str(task.priority)
        new_prio_val = new_priority.value if hasattr(new_priority, "value") else str(new_priority)

        updated = self.task_repo.update(task.id, {"priority": new_prio_val})
        self.history_repo.log_history(
            task_id=task.id,
            action="priority_changed",
            old_value=old_prio_val,
            new_value=new_prio_val,
            reason=reason.strip() if reason else None,
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def assign_task(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Assign or unassign task with denormalized user snapshots."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskCompletedError(task_id, action="assign")
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="assign")

        assigned_user_name: Optional[str] = None
        assigned_user_email: Optional[str] = None
        if assigned_user_id is not None:
            user = self.user_repo.get_by_id(assigned_user_id)
            if not user:
                raise UserNotFoundError(assigned_user_id)
            if not user.get("is_active", True):
                raise InactiveUserError(f"User {assigned_user_id} is inactive and cannot be assigned tasks.")
            assigned_user_name = user.get("name")
            assigned_user_email = user.get("email")

        old_user_str = task.assigned_user_id or "unassigned"
        new_user_str = str(assigned_user_id) if assigned_user_id is not None else "unassigned"

        updates: Dict[str, Any] = {
            "assigned_user_id": str(assigned_user_id) if assigned_user_id is not None else None,
            "assigned_user_name": assigned_user_name,
            "assigned_user_email": assigned_user_email,
        }
        updated = self.task_repo.update(task.id, updates)

        self.history_repo.log_history(
            task_id=task.id,
            action="assigned" if assigned_user_id is not None else "unassigned",
            old_value=old_user_str,
            new_value=new_user_str,
            created_by_user_id=assigned_by_user_id,
        )
        return self._to_doc(updated)

    def update_subject_line(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        subject_line: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Update email subject line identifier."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskCompletedError(task_id, action="update_subject_line")
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="update_subject_line")

        old_sub = task.subject_line or ""
        new_sub = subject_line.strip() if subject_line else ""

        updated = self.task_repo.update(task.id, {"subject_line": new_sub or None})
        self.history_repo.log_history(
            task_id=task.id,
            action="subject_line_updated",
            old_value=old_sub,
            new_value=new_sub,
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def record_attempt(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
        notes: Optional[str] = None,
        authorized_override: bool = False,
        override_reason: Optional[str] = None,
    ) -> TaskDocument:
        """Record an outreach attempt respecting max_attempts ceiling and override semantics."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskCompletedError(task_id, action="record_attempt")
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="record_attempt")

        if authorized_override:
            if not override_reason or not override_reason.strip():
                raise OverrideReasonRequiredError()

            updated, _ = self.task_repo.increment_attempt(task.id, enforce_ceiling=False)
            self.history_repo.log_history(
                task_id=task.id,
                action="attempt_recorded_with_override",
                old_value=str(task.attempt_count),
                new_value=str(updated["attempt_count"]),
                reason=override_reason.strip(),
                created_by_user_id=user_id,
            )
            return self._to_doc(updated)

        if task.attempt_count >= task.max_attempts:
            raise MaxAttemptsReachedError(task_id, task.attempt_count, task.max_attempts)

        updated, ok = self.task_repo.increment_attempt(task.id, enforce_ceiling=True)
        if not ok:
            raise MaxAttemptsReachedError(task_id, task.attempt_count, task.max_attempts)

        self.history_repo.log_history(
            task_id=task.id,
            action="attempt_recorded",
            old_value=str(task.attempt_count),
            new_value=str(updated["attempt_count"]),
            reason=notes.strip() if notes else None,
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def postpone_task(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        new_due_date: Optional[datetime] = None,
        reason: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Postpone task due date with mandatory justification reason."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskCompletedError(task_id, action="postpone")
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="postpone")

        if not reason or not reason.strip():
            raise PostponementReasonRequiredError()

        if new_due_date is None:
            raise InvalidTaskDateError("new_due_date cannot be None")
        validate_task_dates(due_date=new_due_date)

        old_due_str = task.due_date.isoformat() if task.due_date else "None"
        new_due_str = new_due_date.isoformat()

        updated = self.task_repo.update(task.id, {"due_date": new_due_date})
        self.history_repo.log_history(
            task_id=task.id,
            action="postponed",
            old_value=old_due_str,
            new_value=new_due_str,
            reason=reason.strip(),
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def update_next_action_date(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        next_action_date: Optional[datetime] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Update next action target date with audit history."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskCompletedError(task_id, action="update_next_action_date")
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="update_next_action_date")

        validate_task_dates(next_action_date=next_action_date)

        old_str = task.next_action_date.isoformat() if task.next_action_date else "None"
        new_str = next_action_date.isoformat() if next_action_date else "None"

        updated = self.task_repo.update(task.id, {"next_action_date": next_action_date})
        self.history_repo.log_history(
            task_id=task.id,
            action="next_action_date_updated",
            old_value=old_str,
            new_value=new_str,
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def complete_task(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Mark task as COMPLETED with timestamp and history."""
        task = self.get_task(task_id=task_id)
        if task.status == TaskStatus.COMPLETED:
            raise TaskAlreadyCompletedError(task_id)
        if task.status == TaskStatus.CANCELLED:
            raise TaskCancelledError(task_id, action="complete")

        now = utcnow()
        old_status = task.status.value if hasattr(task.status, "value") else str(task.status)
        new_status = TaskStatus.COMPLETED.value

        updated = self.task_repo.update(task.id, {
            "status": new_status,
            "completed_at": now,
        })
        self.history_repo.log_history(
            task_id=task.id,
            action="completed",
            old_value=old_status,
            new_value=new_status,
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def reopen_task(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        reason: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskDocument:
        """Reopen a completed task with mandatory justification reason."""
        task = self.get_task(task_id=task_id)
        if task.status != TaskStatus.COMPLETED:
            raise TaskNotCompletedError(task_id)

        if not reason or not reason.strip():
            raise ReopenReasonRequiredError()

        old_status = task.status.value if hasattr(task.status, "value") else str(task.status)
        new_status = TaskStatus.PENDING.value

        updated = self.task_repo.update(task.id, {
            "status": new_status,
            "completed_at": None,
        })
        self.history_repo.log_history(
            task_id=task.id,
            action="reopened",
            old_value=old_status,
            new_value=new_status,
            reason=reason.strip(),
            created_by_user_id=user_id,
        )
        return self._to_doc(updated)

    def delete_task(self, db: Any = None, task_id: Union[str, uuid.UUID] = "") -> bool:
        """Delete a task and its audit history."""
        self.history_repo.delete_for_task(task_id)
        return self.task_repo.delete(task_id)

    def list_tasks(
        self,
        db: Any = None,
        search: Optional[str] = None,
        status: Optional[TaskStatus] = None,
        priority: Optional[TaskPriority] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        unassigned: Optional[bool] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        due_from: Optional[datetime] = None,
        due_to: Optional[datetime] = None,
        next_action_from: Optional[datetime] = None,
        next_action_to: Optional[datetime] = None,
        overdue: Optional[bool] = None,
        due_today: Optional[bool] = None,
        upcoming: Optional[bool] = None,
        has_next_action: Optional[bool] = None,
        no_next_action: Optional[bool] = None,
        near_max_attempts: Optional[bool] = None,
        due_date_before: Optional[datetime] = None,
        next_action_before: Optional[datetime] = None,
        sort_by: str = "created_at",
        sort_order: str = "desc",
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[TaskDocument], int]:
        """List tasks using MongoDB multi-criteria filter."""
        items, total = self.task_repo.list_tasks(
            search=search,
            status=status,
            priority=priority,
            assigned_user_id=assigned_user_id,
            unassigned=unassigned,
            client_id=client_id,
            workflow_id=workflow_id,
            due_from=due_from,
            due_to=due_to,
            due_date_before=due_date_before,
            next_action_from=next_action_from,
            next_action_to=next_action_to,
            next_action_before=next_action_before,
            overdue=overdue,
            due_today=due_today,
            upcoming=upcoming,
            has_next_action=has_next_action,
            no_next_action=no_next_action,
            near_max_attempts=near_max_attempts,
            sort_by=sort_by,
            sort_order=sort_order,
            page=page,
            page_size=page_size,
        )
        return [self._to_doc(item) for item in items], total

    def get_task_history(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        action: Optional[str] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
        order: str = "asc",
        page: Optional[int] = None,
        page_size: Optional[int] = None,
    ) -> List[TaskHistoryDocument]:
        """Retrieve audit history entries for a task."""
        entries = self.history_repo.list_for_task(task_id, limit=page_size or 100)
        if action:
            entries = [e for e in entries if e.get("action") == action]
        if actor_id:
            entries = [e for e in entries if e.get("created_by_user_id") == str(actor_id)]
        if order.lower() == "asc":
            entries = list(reversed(entries))
        return [TaskHistoryDocument.model_validate(e) for e in entries]

    def get_recent_activity(
        self,
        db: Any = None,
        limit: int = 20,
        action: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> List[TaskHistoryDocument]:
        """Retrieve recent audit activity across tasks."""
        entries = self.history_repo.list_recent(limit=limit)
        if action:
            entries = [e for e in entries if e.get("action") == action]
        if task_id:
            entries = [e for e in entries if e.get("task_id") == str(task_id)]
        if actor_id:
            entries = [e for e in entries if e.get("created_by_user_id") == str(actor_id)]
        return [TaskHistoryDocument.model_validate(e) for e in entries]
