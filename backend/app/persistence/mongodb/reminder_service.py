"""MongoDB Reminder Service implementation using embedded task subdocuments."""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Union
import uuid

from app.documents.task import ReminderSubDocument
from app.repositories import TaskRepository
from app.services.exceptions import ReminderNotFoundError, TaskNotFoundError


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
            remind_at=remind_at,
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

        for rem in task.get("reminders", []):
            if rem.get("id") == rid_str:
                return ReminderSubDocument.model_validate(rem)

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
        return [ReminderSubDocument.model_validate(r) for r in task.get("reminders", [])]

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
            for r in t.get("reminders", []):
                if not r.get("is_sent", False) and r.get("remind_at") and r["remind_at"] <= target_time:
                    due.append(ReminderSubDocument.model_validate(r))
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
            reminders = [ReminderSubDocument.model_validate(r) for r in task.get("reminders", [])]
            if is_sent is not None:
                reminders = [r for r in reminders if r.is_sent == is_sent]
            return reminders
        query: Dict[str, Any] = {}
        if is_sent is not None:
            query = {"reminders.is_sent": is_sent}
        tasks = self.task_repo.collection.find(query)
        res = []
        for t in tasks:
            for r in t.get("reminders", []):
                if is_sent is None or r.get("is_sent") == is_sent:
                    res.append(ReminderSubDocument.model_validate(r))
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
