"""PostgreSQL / SQLAlchemy Notification Service Adapter."""

from datetime import datetime, timezone
from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.notification import Notification
from app.models.user import User
from app.services.exceptions import NotificationNotFoundError, UserNotFoundError


def should_notify_user(db: Session, user_id: uuid.UUID, notif_type: str) -> bool:
    """Check if user has enabled notifications for this specific type in UserSettings."""
    from app.models.user_settings import UserSettings

    settings = db.scalars(
        select(UserSettings).where(UserSettings.user_id == user_id)
    ).first()
    if not settings:
        return True

    type_attr_map = {
        "task_assigned": "notify_task_assigned",
        "task_reassigned": "notify_task_reassigned",
        "reminder_due": "notify_reminder_due",
        "follow_up_due": "notify_follow_up_due",
        "next_action_due": "notify_next_action_due",
        "task_overdue": "notify_task_overdue",
        "attempt_limit_reached": "notify_attempt_limit_reached",
        "near_max_attempts": "notify_attempt_limit_reached",
        "task_completed": "notify_task_completed",
        "task_reopened": "notify_task_reopened",
    }
    attr_name = type_attr_map.get(notif_type)
    if attr_name and hasattr(settings, attr_name):
        return bool(getattr(settings, attr_name, True))
    return True


class PostgresNotificationService:
    """PostgreSQL notification service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def create_notification(
        self,
        db: Optional[Session] = None,
        user_id: Union[str, uuid.UUID] = "",
        type: str = "",
        title: str = "",
        message: str = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
        dedup_key: Optional[str] = None,
    ) -> Optional[Notification]:
        session, close_needed = self._ensure_session(db)
        try:
            uid = uuid.UUID(str(user_id))
            tid = uuid.UUID(str(task_id)) if task_id else None

            user = session.get(User, uid)
            if not user:
                raise UserNotFoundError(uid)

            if not should_notify_user(session, uid, type):
                return None

            if dedup_key:
                stmt = select(Notification).where(
                    Notification.user_id == uid,
                    Notification.dedup_key == dedup_key,
                )
                existing = session.scalars(stmt).first()
                if existing:
                    return existing

            notification = Notification(
                user_id=uid,
                task_id=tid,
                type=type,
                title=title,
                message=message,
                dedup_key=dedup_key,
                is_read=False,
            )
            session.add(notification)
            session.commit()
            session.refresh(notification)

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_notification(notification, DualWriteOperation.CREATE)

            return notification
        finally:
            if close_needed:
                session.close()

    def get_notification(
        self,
        db: Optional[Session] = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_id: Union[str, uuid.UUID] = "",
    ) -> Notification:
        session, close_needed = self._ensure_session(db)
        try:
            uid = uuid.UUID(str(user_id))
            nid = uuid.UUID(str(notification_id))

            stmt = select(Notification).where(
                Notification.id == nid,
                Notification.user_id == uid,
            )
            notification = session.scalars(stmt).first()
            if not notification:
                raise NotificationNotFoundError(nid)
            return notification
        finally:
            if close_needed:
                session.close()

    def get_user_notifications(
        self,
        db: Optional[Session] = None,
        user_id: Union[str, uuid.UUID] = "",
        unread_only: bool = False,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Notification], int, int]:
        session, close_needed = self._ensure_session(db)
        try:
            uid = uuid.UUID(str(user_id))

            unread_stmt = select(func.count(Notification.id)).where(
                Notification.user_id == uid,
                Notification.is_read.is_(False),
            )
            unread_count = session.scalar(unread_stmt) or 0

            stmt = select(Notification).where(Notification.user_id == uid)
            count_stmt = select(func.count(Notification.id)).where(Notification.user_id == uid)

            if unread_only:
                stmt = stmt.where(Notification.is_read.is_(False))
                count_stmt = count_stmt.where(Notification.is_read.is_(False))

            total = session.scalar(count_stmt) or 0
            offset = max(0, (page - 1) * page_size)
            stmt = stmt.order_by(Notification.created_at.desc()).offset(offset).limit(page_size)
            items = list(session.scalars(stmt).all())

            return items, total, unread_count
        finally:
            if close_needed:
                session.close()

    def get_unread_count(self, db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> int:
        session, close_needed = self._ensure_session(db)
        try:
            uid = uuid.UUID(str(user_id))
            stmt = select(func.count(Notification.id)).where(
                Notification.user_id == uid,
                Notification.is_read.is_(False),
            )
            return session.scalar(stmt) or 0
        finally:
            if close_needed:
                session.close()

    def mark_as_read(
        self,
        db: Optional[Session] = None,
        user_id: Union[str, uuid.UUID] = "",
        notification_id: Union[str, uuid.UUID] = "",
    ) -> Notification:
        session, close_needed = self._ensure_session(db)
        try:
            notification = self.get_notification(session, user_id=user_id, notification_id=notification_id)
            if not notification.is_read:
                notification.is_read = True
                notification.read_at = datetime.now(timezone.utc)
                session.commit()
                session.refresh(notification)

                # Controlled dual-write to MongoDB (Phase 31)
                from app.migration.dual_write import DualWriteOperation, dual_writer
                dual_writer.sync_notification(notification, DualWriteOperation.UPDATE)

            return notification
        finally:
            if close_needed:
                session.close()

    def mark_all_as_read(self, db: Optional[Session] = None, user_id: Union[str, uuid.UUID] = "") -> int:
        session, close_needed = self._ensure_session(db)
        try:
            uid = uuid.UUID(str(user_id))
            now = datetime.now(timezone.utc)
            stmt = (
                update(Notification)
                .where(
                    Notification.user_id == uid,
                    Notification.is_read.is_(False),
                )
                .values(is_read=True, read_at=now)
            )
            result = session.execute(stmt)
            session.commit()
            return result.rowcount or 0
        finally:
            if close_needed:
                session.close()

    def evaluate_due_notifications(
        self,
        db: Optional[Session] = None,
        as_of: Optional[datetime] = None,
    ) -> int:
        session, close_needed = self._ensure_session(db)
        try:
            from app.services.scheduling_service import SchedulingService
            result = SchedulingService.evaluate_all(db=session, as_of=as_of, user_id=None)
            return result.notifications_created
        finally:
            if close_needed:
                session.close()
