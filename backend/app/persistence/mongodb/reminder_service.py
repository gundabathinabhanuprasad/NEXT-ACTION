"""MongoDB Reminder Service implementation using embedded task subdocuments."""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Union
import uuid

from app.documents.common import utcnow
from app.documents.task import ReminderSubDocument
from app.repositories import TaskRepository
from app.services.exceptions import ReminderNotFoundError, TaskNotFoundError


def _safe_sort_key(dt: Optional[datetime]) -> datetime:
    """Return a timezone-aware UTC datetime for safe cross-comparison and sorting."""
    if dt is None:
        return datetime.min.replace(tzinfo=timezone.utc)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def _safe_parse_reminder(raw: Any) -> Optional[ReminderSubDocument]:
    """Safely validate a raw MongoDB subdocument into a ReminderSubDocument."""
    if not isinstance(raw, dict):
        return None
    try:
        data = dict(raw)
        if not data.get("remind_at"):
            data["remind_at"] = utcnow()
        return ReminderSubDocument.model_validate(data)
    except Exception:
        return None


class MongoReminderService:
    """Reminder service implementation using embedded task reminders."""

    def __init__(self, task_repo: Optional[TaskRepository] = None):
        self.task_repo = task_repo or TaskRepository()

    def create_reminder(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        remind_at: Optional[datetime] = None,
        message: str = "",
    ) -> ReminderSubDocument:
        """Create an embedded reminder within target task."""
        task = self.task_repo.get_by_id(task_id)
        if not task:
            raise TaskNotFoundError(task_id)

        reminder = ReminderSubDocument(
            task_id=str(task_id),
            remind_at=remind_at or utcnow(),
            message=message.strip(),
            is_sent=False,
        )
        self.task_repo.add_reminder(task_id, reminder)
        return reminder

    def get_reminder(
        self,
        db: Any = None,
        reminder_id: Union[str, uuid.UUID] = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> ReminderSubDocument:
        """Look up reminder subdocument by ID."""
        rid_str = str(reminder_id)
        if task_id is not None:
            task = self.task_repo.get_by_id(task_id)
        else:
            task = self.task_repo.find_one({"reminders.id": rid_str})

        if not task:
            raise ReminderNotFoundError(reminder_id)

        for rem in (task.get("reminders") or []):
            if isinstance(rem, dict) and rem.get("id") == rid_str:
                parsed = _safe_parse_reminder(rem)
                if parsed:
                    return parsed

        raise ReminderNotFoundError(reminder_id)

    def process_reminder(
        self,
        db: Any = None,
        reminder_id: Union[str, uuid.UUID] = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> ReminderSubDocument:
        """Mark embedded reminder as sent."""
        rid_str = str(reminder_id)
        res = self.task_repo.collection.update_one(
            {"reminders.id": rid_str},
            {"$set": {"reminders.$.is_sent": True}},
        )
        if res.matched_count == 0:
            raise ReminderNotFoundError(reminder_id)
        return self.get_reminder(reminder_id=rid_str, task_id=task_id)

    def list_task_reminders(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
    ) -> List[ReminderSubDocument]:
        """List embedded reminders for task."""
        task = self.task_repo.get_by_id(task_id)
        if not task:
            raise TaskNotFoundError(task_id)
        items = []
        for r in (task.get("reminders") or []):
            parsed = _safe_parse_reminder(r)
            if parsed:
                items.append(parsed)
        return items

    def list_due_reminders(
        self,
        db: Any = None,
        as_of: Optional[datetime] = None,
    ) -> List[ReminderSubDocument]:
        """List unsent reminders due on or before as_of across all tasks."""
        target_time = as_of or datetime.now(timezone.utc)
        tasks = self.task_repo.collection.find(
            {"reminders": {"$elemMatch": {"is_sent": False, "remind_at": {"$lte": target_time}}}}
        )
        due = []
        for t in tasks:
            for r in (t.get("reminders") or []):
                parsed = _safe_parse_reminder(r)
                if not parsed:
                    continue
                remind = _safe_sort_key(parsed.remind_at)
                target_tz = _safe_sort_key(target_time)
                if not parsed.is_sent and remind <= target_tz:
                    due.append(parsed)
        due.sort(key=lambda x: _safe_sort_key(x.remind_at))
        return due

    def list_reminders(
        self,
        db: Any = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        is_sent: Optional[bool] = None,
    ) -> List[ReminderSubDocument]:
        """List reminders filtered by task and sent status."""
        if task_id is not None:
            task = self.task_repo.get_by_id(task_id)
            if not task:
                return []
            reminders = []
            for r in (task.get("reminders") or []):
                parsed = _safe_parse_reminder(r)
                if parsed:
                    reminders.append(parsed)
            if is_sent is not None:
                reminders = [r for r in reminders if r.is_sent == is_sent]
            reminders.sort(key=lambda x: _safe_sort_key(x.remind_at))
            return reminders

        query: Dict[str, Any] = {}
        if is_sent is not None:
            query = {"reminders.is_sent": is_sent}
        tasks = self.task_repo.collection.find(query)
        res = []
        for t in tasks:
            for r in (t.get("reminders") or []):
                parsed = _safe_parse_reminder(r)
                if not parsed:
                    continue
                if is_sent is None or parsed.is_sent == is_sent:
                    res.append(parsed)
        res.sort(key=lambda x: _safe_sort_key(x.remind_at))
        return res

    def delete_reminder(
        self,
        db: Any = None,
        reminder_id: Union[str, uuid.UUID] = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> bool:
        """Remove embedded reminder from task."""
        rid_str = str(reminder_id)
        if task_id is None:
            task = self.task_repo.find_one({"reminders.id": rid_str})
            if not task:
                raise ReminderNotFoundError(reminder_id)
            tid_str = task["_id"]
        else:
            tid_str = str(task_id)

        updated = self.task_repo.remove_reminder(tid_str, rid_str)
        return updated is not None
