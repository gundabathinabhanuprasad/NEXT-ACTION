"""PostgreSQL / SQLAlchemy Task Service Adapter.

Preserves exact existing PostgreSQL task persistence and business logic.
"""

from datetime import datetime, timezone
import json
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.client import Client
from app.models.enums import TaskPriority, TaskStatus
from app.models.task import Task
from app.models.user import User
from app.models.workflow import Workflow
from app.services.exceptions import (
    InactiveUserError,
    InvalidStatusTransitionError,
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
)
from app.persistence.postgres.history_service import PostgresHistoryService
from app.persistence.postgres.notification_service import PostgresNotificationService

_history_service = PostgresHistoryService()
_notification_service = PostgresNotificationService()


def validate_task_dates(
    due_date: Optional[datetime] = None,
    next_action_date: Optional[datetime] = None,
) -> None:
    """Validate task date parameters ensuring datetime types and reasonable invariants."""
    if due_date is not None and not isinstance(due_date, datetime):
        raise InvalidTaskDateError("due_date must be a valid datetime instance.")
    if next_action_date is not None and not isinstance(next_action_date, datetime):
        raise InvalidTaskDateError("next_action_date must be a valid datetime instance.")


class PostgresTaskService:
    """PostgreSQL task service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        """Ensure an active SQLAlchemy Session is available."""
        if db is not None:
            return db, False
        return SessionLocal(), True

    def _sync_task(self, task: Task, operation: str = "UPDATE") -> None:
        """Controlled dual-write to MongoDB (Phase 31)."""
        from app.migration.dual_write import DualWriteOperation, dual_writer
        op = (
            DualWriteOperation.CREATE
            if operation == "CREATE"
            else (DualWriteOperation.DELETE if operation == "DELETE" else DualWriteOperation.UPDATE)
        )
        dual_writer.sync_task(task, op)

    def get_task(self, db: Optional[Session] = None, task_id: Union[str, uuid.UUID] = "") -> Task:
        """Retrieve a task by ID or raise TaskNotFoundError."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(task_id))
            task = session.get(Task, parsed_id)
            if not task:
                raise TaskNotFoundError(parsed_id)
            return task
        finally:
            if close_needed:
                session.close()

    def create_task(
        self,
        db: Optional[Session] = None,
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
    ) -> Task:
        """Create a new Task and log initial creation history atomically."""
        validate_task_dates(due_date=due_date, next_action_date=next_action_date)
        session, close_needed = self._ensure_session(db)
        try:
            cid = uuid.UUID(str(client_id)) if client_id else None
            wid = uuid.UUID(str(workflow_id)) if workflow_id else None
            uid = uuid.UUID(str(assigned_user_id)) if assigned_user_id else None
            tid = uuid.UUID(str(template_id)) if template_id else None
            rid = uuid.UUID(str(recurring_task_id)) if recurring_task_id else None
            created_uid = uuid.UUID(str(created_by_user_id)) if created_by_user_id else None

            if uid is not None:
                user = session.get(User, uid)
                if not user:
                    raise UserNotFoundError(uid)
                if not user.is_active:
                    raise InactiveUserError()

            task = Task(
                title=title,
                description=description,
                subject_line=subject_line,
                client_id=cid,
                workflow_id=wid,
                assigned_user_id=uid,
                template_id=tid,
                recurring_task_id=rid,
                status=status,
                priority=priority,
                due_date=due_date,
                next_action_date=next_action_date,
                attempt_count=0,
                max_attempts=max_attempts,
            )
            session.add(task)
            session.flush()

            initial_payload = {
                "title": task.title,
                "status": task.status.value,
                "priority": task.priority.value,
                "max_attempts": task.max_attempts,
                "due_date": task.due_date.isoformat() if task.due_date else None,
                "next_action_date": task.next_action_date.isoformat() if task.next_action_date else None,
                "template_id": str(tid) if tid else None,
                "recurring_task_id": str(rid) if rid else None,
            }

            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="created",
                new_value=json.dumps(initial_payload),
                created_by_user_id=created_uid or uid,
            )

            session.commit()
            session.refresh(task)

            if uid is not None:
                _notification_service.create_notification(
                    db=session,
                    user_id=uid,
                    type="task_assigned",
                    title=f"New Task Assigned: {task.title}",
                    message=f"You have been assigned to task '{task.title}'.",
                    task_id=task.id,
                    dedup_key=f"task_assigned:{task.id}:{uid}",
                )

            self._sync_task(task, "CREATE")
            return task
        finally:
            if close_needed:
                session.close()

    def record_attempt(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
        notes: Optional[str] = None,
        authorized_override: bool = False,
        override_reason: Optional[str] = None,
    ) -> Task:
        """Record a work attempt on a task."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if task.status == TaskStatus.COMPLETED:
                raise TaskCompletedError(parsed_tid, action="attempt")
            if task.status == TaskStatus.CANCELLED:
                raise TaskCancelledError(parsed_tid, action="attempt")

            if authorized_override:
                if not override_reason or not override_reason.strip():
                    raise OverrideReasonRequiredError()
                old_count = task.attempt_count
                task.attempt_count += 1
                _history_service.log_history(
                    db=session,
                    task_id=task.id,
                    action="attempt_override",
                    old_value=str(old_count),
                    new_value=str(task.attempt_count),
                    reason=override_reason.strip(),
                    created_by_user_id=parsed_uid,
                )
            else:
                if task.attempt_count >= task.max_attempts:
                    raise MaxAttemptsReachedError(parsed_tid, task.attempt_count, task.max_attempts)
                old_count = task.attempt_count
                task.attempt_count += 1
                _history_service.log_history(
                    db=session,
                    task_id=task.id,
                    action="attempt",
                    old_value=str(old_count),
                    new_value=str(task.attempt_count),
                    reason=notes,
                    created_by_user_id=parsed_uid,
                )

            session.commit()
            session.refresh(task)

            if task.attempt_count >= task.max_attempts and task.assigned_user_id is not None:
                _notification_service.create_notification(
                    db=session,
                    user_id=task.assigned_user_id,
                    type="attempt_limit_reached",
                    title=f"Max Attempts Reached: {task.title}",
                    message=f"Task '{task.title}' reached maximum attempt limit ({task.attempt_count}/{task.max_attempts}). Authorized override required.",
                    task_id=task.id,
                    dedup_key=f"attempt_limit:{task.id}:{task.attempt_count}",
                )

            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def postpone_task(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        new_due_date: datetime = datetime.now(timezone.utc),
        reason: str = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Task:
        """Postpone a task's due date."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if task.status == TaskStatus.COMPLETED:
                raise TaskCompletedError(parsed_tid, action="postpone")
            if task.status == TaskStatus.CANCELLED:
                raise TaskCancelledError(parsed_tid, action="postpone")

            if not reason or not reason.strip():
                raise PostponementReasonRequiredError()

            validate_task_dates(due_date=new_due_date)

            old_due_str = task.due_date.isoformat() if task.due_date else "None"
            new_due_str = new_due_date.isoformat()

            task.due_date = new_due_date
            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="postponed",
                old_value=old_due_str,
                new_value=new_due_str,
                reason=reason.strip(),
                created_by_user_id=parsed_uid,
            )

            session.commit()
            session.refresh(task)
            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def update_next_action_date(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        next_action_date: Optional[datetime] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Task:
        """Update next action date."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if task.status == TaskStatus.COMPLETED:
                raise TaskCompletedError(parsed_tid, action="update_next_action_date")
            if task.status == TaskStatus.CANCELLED:
                raise TaskCancelledError(parsed_tid, action="update_next_action_date")

            validate_task_dates(next_action_date=next_action_date)

            old_date_str = task.next_action_date.isoformat() if task.next_action_date else "None"
            new_date_str = next_action_date.isoformat() if next_action_date else "None"

            task.next_action_date = next_action_date
            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="next_action_date_changed",
                old_value=old_date_str,
                new_value=new_date_str,
                created_by_user_id=parsed_uid,
            )

            session.commit()
            session.refresh(task)
            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def complete_task(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Task:
        """Complete a task."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if task.status == TaskStatus.COMPLETED:
                raise TaskAlreadyCompletedError(parsed_tid)
            if task.status == TaskStatus.CANCELLED:
                raise TaskCancelledError(parsed_tid, action="complete")

            old_status = task.status.value
            task.status = TaskStatus.COMPLETED
            task.completed_at = datetime.now(timezone.utc)

            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="completed",
                old_value=old_status,
                new_value=TaskStatus.COMPLETED.value,
                created_by_user_id=parsed_uid,
            )

            session.commit()
            session.refresh(task)

            if task.assigned_user_id is not None and parsed_uid is not None and task.assigned_user_id != parsed_uid:
                _notification_service.create_notification(
                    db=session,
                    user_id=task.assigned_user_id,
                    type="task_completed",
                    title=f"Task Completed: {task.title}",
                    message=f"Task '{task.title}' was marked as completed.",
                    task_id=task.id,
                )

            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def reopen_task(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        reason: str = "",
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Task:
        """Reopen a completed task."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if task.status != TaskStatus.COMPLETED:
                raise TaskNotCompletedError(parsed_tid)

            if not reason or not reason.strip():
                raise ReopenReasonRequiredError()

            old_status = task.status.value
            task.status = TaskStatus.PENDING
            task.completed_at = None

            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="reopened",
                old_value=old_status,
                new_value=TaskStatus.PENDING.value,
                reason=reason.strip(),
                created_by_user_id=parsed_uid,
            )

            session.commit()
            session.refresh(task)

            if task.assigned_user_id is not None and parsed_uid is not None and task.assigned_user_id != parsed_uid:
                _notification_service.create_notification(
                    db=session,
                    user_id=task.assigned_user_id,
                    type="task_reopened",
                    title=f"Task Reopened: {task.title}",
                    message=f"Task '{task.title}' was reopened: {reason.strip()}",
                    task_id=task.id,
                )

            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def change_status(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        new_status: TaskStatus = TaskStatus.PENDING,
        user_id: Optional[Union[str, uuid.UUID]] = None,
        reason: Optional[str] = None,
    ) -> Task:
        """Controlled status change."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if not isinstance(new_status, TaskStatus):
                raise InvalidStatusTransitionError(from_status=str(task.status), to_status=str(new_status))

            if task.status == new_status:
                return task

            if new_status == TaskStatus.COMPLETED:
                return self.complete_task(session, task_id=parsed_tid, user_id=parsed_uid)

            old_status_val = task.status.value
            task.status = new_status
            if old_status_val == TaskStatus.COMPLETED.value:
                task.completed_at = None

            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="status_changed",
                old_value=old_status_val,
                new_value=new_status.value,
                reason=reason,
                created_by_user_id=parsed_uid,
            )

            session.commit()
            session.refresh(task)
            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def change_priority(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        new_priority: TaskPriority = TaskPriority.MEDIUM,
        user_id: Optional[Union[str, uuid.UUID]] = None,
        reason: Optional[str] = None,
    ) -> Task:
        """Change task priority."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if task.priority == new_priority:
                return task

            old_priority_val = task.priority.value
            task.priority = new_priority

            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="priority_changed",
                old_value=old_priority_val,
                new_value=new_priority.value,
                reason=reason,
                created_by_user_id=parsed_uid,
            )

            session.commit()
            session.refresh(task)
            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def assign_task(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Task:
        """Assign or reassign a task."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            uid = uuid.UUID(str(assigned_user_id)) if assigned_user_id else None
            by_uid = uuid.UUID(str(assigned_by_user_id)) if assigned_by_user_id else None
            task = self.get_task(session, parsed_tid)

            if uid is not None:
                user = session.get(User, uid)
                if not user:
                    raise UserNotFoundError(uid)
                if not user.is_active:
                    raise InactiveUserError()

            if task.assigned_user_id == uid:
                return task

            old_user_str = str(task.assigned_user_id) if task.assigned_user_id else "None"
            new_user_str = str(uid) if uid else "None"

            task.assigned_user_id = uid

            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="reassigned",
                old_value=old_user_str,
                new_value=new_user_str,
                created_by_user_id=by_uid,
            )

            session.commit()
            session.refresh(task)

            if uid is not None and uid != by_uid:
                notif_type = "task_assigned" if old_user_str == "None" else "task_reassigned"
                notif_title = f"Task Assigned: {task.title}" if notif_type == "task_assigned" else f"Task Reassigned: {task.title}"
                notif_msg = f"You have been assigned to task '{task.title}'." if notif_type == "task_assigned" else f"Task '{task.title}' has been reassigned to you."
                _notification_service.create_notification(
                    db=session,
                    user_id=uid,
                    type=notif_type,
                    title=notif_title,
                    message=notif_msg,
                    task_id=task.id,
                )

            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def update_subject_line(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        subject_line: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Task:
        """Update subject line."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_uid = uuid.UUID(str(user_id)) if user_id else None
            task = self.get_task(session, parsed_tid)

            if task.subject_line == subject_line:
                return task

            old_subject = task.subject_line
            task.subject_line = subject_line

            _history_service.log_history(
                db=session,
                task_id=task.id,
                action="subject_line_changed",
                old_value=old_subject,
                new_value=subject_line,
                created_by_user_id=parsed_uid,
            )

            session.commit()
            session.refresh(task)
            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def update_task(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        title: Optional[str] = None,
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Task:
        """Update general fields on task."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            task = self.get_task(session, parsed_tid)

            if title is not None and title.strip():
                task.title = title.strip()
            if description is not None:
                task.description = description
            if subject_line is not None:
                task.subject_line = subject_line

            session.commit()
            session.refresh(task)
            self._sync_task(task, "UPDATE")
            return task
        finally:
            if close_needed:
                session.close()

    def delete_task(self, db: Optional[Session] = None, task_id: Union[str, uuid.UUID] = "") -> bool:
        """Delete task by ID."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            task = self.get_task(session, parsed_tid)
            session.delete(task)
            session.commit()
            self._sync_task(task, "DELETE")
            return True
        finally:
            if close_needed:
                session.close()

    def get_task_history(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        action: Optional[str] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
        order: str = "asc",
        page: Optional[int] = None,
        page_size: Optional[int] = None,
    ) -> list:
        """Retrieve task audit history."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id))
            parsed_aid = uuid.UUID(str(actor_id)) if actor_id else None
            return _history_service.get_task_history(
                db=session,
                task_id=parsed_tid,
                action=action,
                actor_id=parsed_aid,
                order=order,
                page=page,
                page_size=page_size,
            )
        finally:
            if close_needed:
                session.close()

    def get_recent_activity(
        self,
        db: Optional[Session] = None,
        limit: int = 20,
        action: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> list:
        """Retrieve recent task history logs across tasks."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_tid = uuid.UUID(str(task_id)) if task_id else None
            parsed_aid = uuid.UUID(str(actor_id)) if actor_id else None
            return _history_service.get_recent_activity(
                db=session,
                limit=limit,
                action=action,
                task_id=parsed_tid,
                actor_id=parsed_aid,
            )
        finally:
            if close_needed:
                session.close()

    def list_tasks(
        self,
        db: Optional[Session] = None,
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
    ) -> Tuple[List[Task], int]:
        """Retrieve filtered, searched, and paginated list of tasks."""
        session, close_needed = self._ensure_session(db)
        try:
            parsed_uid = uuid.UUID(str(assigned_user_id)) if assigned_user_id else None
            parsed_cid = uuid.UUID(str(client_id)) if client_id else None
            parsed_wid = uuid.UUID(str(workflow_id)) if workflow_id else None

            stmt = select(Task)
            count_stmt = select(func.count(func.distinct(Task.id)))

            if search is not None and search.strip():
                term = f"%{search.strip()}%"
                stmt = stmt.outerjoin(Client, Task.client_id == Client.id)
                stmt = stmt.outerjoin(Workflow, Task.workflow_id == Workflow.id)
                stmt = stmt.outerjoin(User, Task.assigned_user_id == User.id)

                count_stmt = count_stmt.outerjoin(Client, Task.client_id == Client.id)
                count_stmt = count_stmt.outerjoin(Workflow, Task.workflow_id == Workflow.id)
                count_stmt = count_stmt.outerjoin(User, Task.assigned_user_id == User.id)

                search_cond = or_(
                    Task.title.ilike(term),
                    Task.description.ilike(term),
                    Task.subject_line.ilike(term),
                    Client.name.ilike(term),
                    Workflow.name.ilike(term),
                    User.name.ilike(term),
                    User.email.ilike(term),
                )
                stmt = stmt.where(search_cond)
                count_stmt = count_stmt.where(search_cond)

            if status is not None:
                stmt = stmt.where(Task.status == status)
                count_stmt = count_stmt.where(Task.status == status)

            if priority is not None:
                stmt = stmt.where(Task.priority == priority)
                count_stmt = count_stmt.where(Task.priority == priority)

            if unassigned is True:
                stmt = stmt.where(Task.assigned_user_id.is_(None))
                count_stmt = count_stmt.where(Task.assigned_user_id.is_(None))
            elif parsed_uid is not None:
                stmt = stmt.where(Task.assigned_user_id == parsed_uid)
                count_stmt = count_stmt.where(Task.assigned_user_id == parsed_uid)

            if parsed_cid is not None:
                stmt = stmt.where(Task.client_id == parsed_cid)
                count_stmt = count_stmt.where(Task.client_id == parsed_cid)

            if parsed_wid is not None:
                stmt = stmt.where(Task.workflow_id == parsed_wid)
                count_stmt = count_stmt.where(Task.workflow_id == parsed_wid)

            if due_from is not None:
                stmt = stmt.where(Task.due_date >= due_from)
                count_stmt = count_stmt.where(Task.due_date >= due_from)

            if due_to is not None:
                stmt = stmt.where(Task.due_date <= due_to)
                count_stmt = count_stmt.where(Task.due_date <= due_to)
            elif due_date_before is not None:
                stmt = stmt.where(Task.due_date <= due_date_before)
                count_stmt = count_stmt.where(Task.due_date <= due_date_before)

            if next_action_from is not None:
                stmt = stmt.where(Task.next_action_date >= next_action_from)
                count_stmt = count_stmt.where(Task.next_action_date >= next_action_from)

            if next_action_to is not None:
                stmt = stmt.where(Task.next_action_date <= next_action_to)
                count_stmt = count_stmt.where(Task.next_action_date <= next_action_to)
            elif next_action_before is not None:
                stmt = stmt.where(Task.next_action_date <= next_action_before)
                count_stmt = count_stmt.where(Task.next_action_date <= next_action_before)

            now = datetime.now(timezone.utc)

            if overdue is True:
                stmt = stmt.where(
                    Task.due_date < now,
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )
                count_stmt = count_stmt.where(
                    Task.due_date < now,
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )

            if due_today is True:
                today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
                today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)
                stmt = stmt.where(
                    Task.due_date >= today_start,
                    Task.due_date <= today_end,
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )
                count_stmt = count_stmt.where(
                    Task.due_date >= today_start,
                    Task.due_date <= today_end,
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )

            if upcoming is True:
                stmt = stmt.where(
                    Task.due_date > now,
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )
                count_stmt = count_stmt.where(
                    Task.due_date > now,
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )

            if no_next_action is True or has_next_action is False:
                stmt = stmt.where(Task.next_action_date.is_(None))
                count_stmt = count_stmt.where(Task.next_action_date.is_(None))
            elif has_next_action is True:
                stmt = stmt.where(Task.next_action_date.is_not(None))
                count_stmt = count_stmt.where(Task.next_action_date.is_not(None))

            if near_max_attempts is True:
                stmt = stmt.where(
                    Task.attempt_count >= (Task.max_attempts - 1),
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )
                count_stmt = count_stmt.where(
                    Task.attempt_count >= (Task.max_attempts - 1),
                    Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                )

            total = session.scalar(count_stmt) or 0

            sort_fields = {
                "created_at": Task.created_at,
                "updated_at": Task.updated_at,
                "due_date": Task.due_date,
                "next_action_date": Task.next_action_date,
                "priority": Task.priority,
                "status": Task.status,
                "title": Task.title,
                "attempt_count": Task.attempt_count,
            }
            sort_col = sort_fields.get(sort_by, Task.created_at)

            if sort_order.lower() == "asc":
                order_expr = sort_col.asc().nullslast() if sort_by in ("due_date", "next_action_date") else sort_col.asc()
            else:
                order_expr = sort_col.desc().nullslast() if sort_by in ("due_date", "next_action_date") else sort_col.desc()

            offset = max(0, (page - 1) * page_size)
            stmt = stmt.order_by(order_expr, Task.created_at.desc(), Task.id.asc()).offset(offset).limit(page_size)
            items = list(session.scalars(stmt).unique().all())

            return items, total
        finally:
            if close_needed:
                session.close()
