"""PostgreSQL / SQLAlchemy FollowUp Service Adapter."""

from datetime import datetime, timezone
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.follow_up import FollowUp
from app.models.task import Task
from app.services.exceptions import FollowUpNotFoundError, TaskNotFoundError


class PostgresFollowUpService:
    """PostgreSQL follow-up service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def get_follow_up(self, db: Optional[Session] = None, follow_up_id: Union[str, uuid.UUID] = "") -> FollowUp:
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(follow_up_id))
            follow_up = session.get(FollowUp, parsed_id)
            if not follow_up:
                raise FollowUpNotFoundError(parsed_id)
            return follow_up
        finally:
            if close_needed:
                session.close()

    def create_follow_up(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
        scheduled_at: datetime = datetime.now(timezone.utc),
        notes: Optional[str] = None,
    ) -> FollowUp:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id))
            task = session.get(Task, tid)
            if not task:
                raise TaskNotFoundError(tid)

            follow_up = FollowUp(
                task_id=task.id,
                scheduled_at=scheduled_at,
                notes=notes,
            )
            session.add(follow_up)
            session.commit()
            session.refresh(follow_up)
            return follow_up
        finally:
            if close_needed:
                session.close()

    def complete_follow_up(
        self,
        db: Optional[Session] = None,
        follow_up_id: Union[str, uuid.UUID] = "",
        completed_at: Optional[datetime] = None,
        notes: Optional[str] = None,
    ) -> FollowUp:
        session, close_needed = self._ensure_session(db)
        try:
            follow_up = self.get_follow_up(session, follow_up_id)
            follow_up.completed_at = completed_at or datetime.now(timezone.utc)
            if notes is not None:
                follow_up.notes = notes

            session.commit()
            session.refresh(follow_up)
            return follow_up
        finally:
            if close_needed:
                session.close()

    def list_task_follow_ups(
        self,
        db: Optional[Session] = None,
        task_id: Union[str, uuid.UUID] = "",
    ) -> List[FollowUp]:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id))
            task = session.get(Task, tid)
            if not task:
                raise TaskNotFoundError(tid)
            stmt = select(FollowUp).where(FollowUp.task_id == tid).order_by(FollowUp.scheduled_at.asc())
            return list(session.scalars(stmt).all())
        finally:
            if close_needed:
                session.close()

    def list_due_follow_ups(
        self,
        db: Optional[Session] = None,
        as_of: Optional[datetime] = None,
    ) -> List[FollowUp]:
        session, close_needed = self._ensure_session(db)
        try:
            target_time = as_of or datetime.now(timezone.utc)
            stmt = (
                select(FollowUp)
                .where(FollowUp.completed_at.is_(None))
                .where(FollowUp.scheduled_at <= target_time)
                .order_by(FollowUp.scheduled_at.asc())
            )
            return list(session.scalars(stmt).all())
        finally:
            if close_needed:
                session.close()

    def list_follow_ups(
        self,
        db: Optional[Session] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        is_completed: Optional[bool] = None,
    ) -> List[FollowUp]:
        session, close_needed = self._ensure_session(db)
        try:
            stmt = select(FollowUp)
            if task_id is not None:
                tid = uuid.UUID(str(task_id))
                stmt = stmt.where(FollowUp.task_id == tid)
            if is_completed is True:
                stmt = stmt.where(FollowUp.completed_at.is_not(None))
            elif is_completed is False:
                stmt = stmt.where(FollowUp.completed_at.is_(None))
            stmt = stmt.order_by(FollowUp.scheduled_at.asc())
            return list(session.scalars(stmt).all())
        finally:
            if close_needed:
                session.close()

    def delete_follow_up(self, db: Optional[Session] = None, follow_up_id: Union[str, uuid.UUID] = "") -> None:
        session, close_needed = self._ensure_session(db)
        try:
            follow_up = self.get_follow_up(session, follow_up_id)
            session.delete(follow_up)
            session.commit()
        finally:
            if close_needed:
                session.close()
