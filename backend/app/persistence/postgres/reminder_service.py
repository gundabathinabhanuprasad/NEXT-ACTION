"""PostgreSQL / SQLAlchemy Reminder Service Adapter."""

from datetime import datetime, timezone
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.reminder import Reminder
from app.models.task import Task
from app.services.exceptions import ReminderNotFoundError, TaskNotFoundError


class PostgresReminderService:
    """PostgreSQL reminder service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def get_reminder(self, db: Optional[Session] = None, reminder_id: Union[str, uuid.UUID] = "") -> Reminder:
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(reminder_id))
            reminder = session.get(Reminder, parsed_id)
            if not reminder:
                raise ReminderNotFoundError(parsed_id)
            return reminder
        finally:
            if close_needed:
                session.close()

    def create_reminder(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        remind_at: datetime = datetime.now(timezone.utc),
        message: str = "",
    ) -> Reminder:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id))
            task = session.get(Task, tid)
            if not task:
                raise TaskNotFoundError(tid)

            reminder = Reminder(
                task_id=task.id,
                remind_at=remind_at,
                message=message,
                is_sent=False,
            )
            session.add(reminder)
            session.commit()
            session.refresh(reminder)
            return reminder
        finally:
            if close_needed:
                session.close()

    def process_reminder(self, db: Optional[Session] = None, reminder_id: Union[str, uuid.UUID] = "") -> Reminder:
        session, close_needed = self._ensure_session(db)
        try:
            reminder = self.get_reminder(session, reminder_id)
            reminder.is_sent = True
            session.commit()
            session.refresh(reminder)
            return reminder
        finally:
            if close_needed:
                session.close()

    def list_due_reminders(
        self,
        db: Optional[Session] = None,
        as_of: Optional[datetime] = None,
    ) -> List[Reminder]:
        session, close_needed = self._ensure_session(db)
        try:
            target_time = as_of or datetime.now(timezone.utc)
            stmt = (
                select(Reminder)
                .where(Reminder.is_sent.is_(False))
                .where(Reminder.remind_at <= target_time)
                .order_by(Reminder.remind_at.asc())
            )
            return list(session.scalars(stmt).all())
        finally:
            if close_needed:
                session.close()

    def list_task_reminders(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
    ) -> List[Reminder]:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id))
            task = session.get(Task, tid)
            if not task:
                raise TaskNotFoundError(tid)
            stmt = select(Reminder).where(Reminder.task_id == tid).order_by(Reminder.remind_at.asc())
            return list(session.scalars(stmt).all())
        finally:
            if close_needed:
                session.close()

    def list_reminders(
        self,
        db: Optional[Session] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        is_sent: Optional[bool] = None,
    ) -> List[Reminder]:
        session, close_needed = self._ensure_session(db)
        try:
            stmt = select(Reminder)
            if task_id is not None:
                tid = uuid.UUID(str(task_id))
                stmt = stmt.where(Reminder.task_id == tid)
            if is_sent is not None:
                stmt = stmt.where(Reminder.is_sent == is_sent)
            stmt = stmt.order_by(Reminder.remind_at.asc())
            return list(session.scalars(stmt).all())
        finally:
            if close_needed:
                session.close()

    def delete_reminder(self, db: Optional[Session] = None, reminder_id: Union[str, uuid.UUID] = "") -> None:
        session, close_needed = self._ensure_session(db)
        try:
            reminder = self.get_reminder(session, reminder_id)
            session.delete(reminder)
            session.commit()
        finally:
            if close_needed:
                session.close()
