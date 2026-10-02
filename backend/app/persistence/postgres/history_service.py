"""PostgreSQL / SQLAlchemy History Service Adapter."""

from datetime import datetime
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload

from app.db.session import SessionLocal
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.schemas.history import TaskHistoryResponse
from app.services.exceptions import TaskNotFoundError


class PostgresHistoryService:
    """PostgreSQL history service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def log_history(
        self,
        db: Optional[Session] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        action: str = "",
        old_value: Optional[str] = None,
        new_value: Optional[str] = None,
        reason: Optional[str] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskHistory:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id)) if task_id else None
            uid = uuid.UUID(str(created_by_user_id)) if created_by_user_id else None

            history = TaskHistory(
                task_id=tid,
                action=action,
                old_value=old_value,
                new_value=new_value,
                reason=reason,
                created_by_user_id=uid,
            )
            session.add(history)
            session.flush()
            if close_needed:
                session.commit()
                session.refresh(history)

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_task_history(history, DualWriteOperation.CREATE)

            return history
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
    ) -> List[TaskHistory]:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id))
            aid = uuid.UUID(str(actor_id)) if actor_id else None

            task = session.get(Task, tid)
            if not task:
                raise TaskNotFoundError(tid)

            query = (
                select(TaskHistory)
                .where(TaskHistory.task_id == tid)
                .options(
                    joinedload(TaskHistory.created_by_user),
                    joinedload(TaskHistory.task),
                )
            )

            if action:
                query = query.where(TaskHistory.action == action.strip().lower())

            if aid:
                query = query.where(TaskHistory.created_by_user_id == aid)

            if order.lower() == "desc":
                query = query.order_by(TaskHistory.created_at.desc(), TaskHistory.id.desc())
            else:
                query = query.order_by(TaskHistory.created_at.asc(), TaskHistory.id.asc())

            if page is not None and page_size is not None:
                offset = (page - 1) * page_size
                query = query.offset(offset).limit(page_size)

            return list(session.scalars(query).unique().all())
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
    ) -> List[TaskHistory]:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id)) if task_id else None
            aid = uuid.UUID(str(actor_id)) if actor_id else None

            query = (
                select(TaskHistory)
                .options(
                    joinedload(TaskHistory.created_by_user),
                    joinedload(TaskHistory.task),
                )
            )

            if action:
                query = query.where(TaskHistory.action == action.strip().lower())
            if tid:
                query = query.where(TaskHistory.task_id == tid)
            if aid:
                query = query.where(TaskHistory.created_by_user_id == aid)

            query = query.order_by(TaskHistory.created_at.desc(), TaskHistory.id.desc()).limit(limit)
            return list(session.scalars(query).unique().all())
        finally:
            if close_needed:
                session.close()

    def list_activity(
        self,
        db: Optional[Session] = None,
        page: int = 1,
        page_size: int = 20,
        action: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> Tuple[List[TaskHistory], int]:
        session, close_needed = self._ensure_session(db)
        try:
            tid = uuid.UUID(str(task_id)) if task_id else None
            aid = uuid.UUID(str(actor_id)) if actor_id else None

            query = select(TaskHistory)

            if action:
                query = query.where(TaskHistory.action == action.strip().lower())
            if tid:
                query = query.where(TaskHistory.task_id == tid)
            if aid:
                query = query.where(TaskHistory.created_by_user_id == aid)
            if start_date:
                query = query.where(TaskHistory.created_at >= start_date)
            if end_date:
                query = query.where(TaskHistory.created_at <= end_date)

            count_query = select(func.count()).select_from(query.subquery())
            total = session.execute(count_query).scalar_one()

            offset = (page - 1) * page_size
            query = (
                query.options(
                    joinedload(TaskHistory.created_by_user),
                    joinedload(TaskHistory.task),
                )
                .order_by(TaskHistory.created_at.desc(), TaskHistory.id.desc())
                .offset(offset)
                .limit(page_size)
            )

            items = list(session.scalars(query).unique().all())
            return items, total
        finally:
            if close_needed:
                session.close()

    def serialize_task_history(self, history: TaskHistory) -> TaskHistoryResponse:
        actor_name: Optional[str] = None
        actor_email: Optional[str] = None

        if getattr(history, "created_by_user", None) is not None:
            actor_name = history.created_by_user.name
            actor_email = history.created_by_user.email
        elif getattr(history, "created_by_user_id", None) is not None:
            actor_name = "Former user"
        else:
            actor_name = "System"

        task_title: Optional[str] = history.task.title if getattr(history, "task", None) else None

        return TaskHistoryResponse(
            id=history.id,
            task_id=history.task_id,
            task_title=task_title,
            action=history.action,
            old_value=history.old_value,
            new_value=history.new_value,
            reason=history.reason,
            created_by_user_id=history.created_by_user_id,
            actor_name=actor_name,
            actor_email=actor_email,
            created_at=history.created_at,
        )
