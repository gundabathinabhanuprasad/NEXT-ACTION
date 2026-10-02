"""MongoDB repository for Task documents with embedded reminders and follow-ups."""

from datetime import datetime, timezone
import re
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
from pymongo import ReturnDocument
from pymongo.database import Database
from app.documents.task import TaskDocument
from app.models.enums import TaskPriority, TaskStatus
from app.repositories.mongodb_base import BaseMongoRepository


class TaskRepository(BaseMongoRepository):
    """Data access repository for tasks collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("tasks", db=db)

    def create(self, task_data: Union[TaskDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new task document."""
        if isinstance(task_data, TaskDocument):
            payload = task_data.to_mongo()
        else:
            payload = dict(task_data)

        # Normalize ID strings
        for field in ("workflow_id", "client_id", "assigned_user_id", "template_id", "recurring_task_id"):
            if field in payload and payload[field] is not None:
                payload[field] = self.to_uuid_str(payload[field])

        # Normalize enum strings
        if "status" in payload and hasattr(payload["status"], "value"):
            payload["status"] = payload["status"].value
        if "priority" in payload and hasattr(payload["priority"], "value"):
            payload["priority"] = payload["priority"].value

        # Normalize date fields
        for date_col in ("due_date", "next_action_date", "completed_at"):
            if date_col in payload:
                payload[date_col] = self.ensure_utc(payload[date_col])

        if "reminders" not in payload or payload["reminders"] is None:
            payload["reminders"] = []
        if "follow_ups" not in payload or payload["follow_ups"] is None:
            payload["follow_ups"] = []

        return self.insert_doc(payload)

    def get_by_id(self, task_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve task by identifier."""
        return self.find_by_id(task_id)

    def update(
        self,
        task_id: Union[str, uuid.UUID],
        fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update task fields."""
        payload = dict(fields)
        for field in ("workflow_id", "client_id", "assigned_user_id", "template_id", "recurring_task_id"):
            if field in payload and payload[field] is not None:
                payload[field] = self.to_uuid_str(payload[field])

        if "status" in payload and hasattr(payload["status"], "value"):
            payload["status"] = payload["status"].value
        if "priority" in payload and hasattr(payload["priority"], "value"):
            payload["priority"] = payload["priority"].value

        for date_col in ("due_date", "next_action_date", "completed_at"):
            if date_col in payload:
                payload[date_col] = self.ensure_utc(payload[date_col])

        return self.update_by_id(task_id, payload)

    def delete(self, task_id: Union[str, uuid.UUID]) -> bool:
        """Delete task by identifier."""
        return self.delete_by_id(task_id)

    def increment_attempt(
        self,
        task_id: Union[str, uuid.UUID],
        enforce_ceiling: bool = False,
    ) -> Tuple[Optional[Dict[str, Any]], bool]:
        """Atomically increment attempt_count, optionally enforcing max_attempts ceiling.

        Returns (updated_doc, True) if incremented, or (current_doc, False) if ceiling was reached.
        """
        tid_str = self.to_uuid_str(task_id)
        now = self.ensure_utc(datetime.now(timezone.utc))

        query: Dict[str, Any] = {"_id": tid_str}
        if enforce_ceiling:
            query["$expr"] = {"$lt": ["$attempt_count", "$max_attempts"]}

        doc = self.collection.find_one_and_update(
            query,
            {
                "$inc": {"attempt_count": 1},
                "$set": {"updated_at": now},
            },
            return_document=ReturnDocument.AFTER,
        )
        if doc is not None:
            return self.format_document(doc), True

        curr = self.find_by_id(tid_str)
        return curr, False

    def add_reminder(
        self,
        task_id: Union[str, uuid.UUID],
        reminder_data: Union[Any, Dict[str, Any]],
    ) -> Optional[Dict[str, Any]]:
        """Push an embedded reminder to the task document."""
        tid_str = self.to_uuid_str(task_id)
        if hasattr(reminder_data, "to_mongo"):
            payload = reminder_data.to_mongo()
        else:
            payload = dict(reminder_data)
        if "id" not in payload:
            payload["id"] = str(uuid.uuid4())
        payload["task_id"] = tid_str
        payload["remind_at"] = self.ensure_utc(payload.get("remind_at"))
        now = self.ensure_utc(datetime.now(timezone.utc))
        payload["created_at"] = self.ensure_utc(payload.get("created_at") or now)
        payload["updated_at"] = now

        doc = self.collection.find_one_and_update(
            {"_id": tid_str},
            {
                "$push": {"reminders": payload},
                "$set": {"updated_at": now},
            },
            return_document=ReturnDocument.AFTER,
        )
        return self.format_document(doc)

    def remove_reminder(
        self,
        task_id: Union[str, uuid.UUID],
        reminder_id: Union[str, uuid.UUID],
    ) -> Optional[Dict[str, Any]]:
        """Pull an embedded reminder by identifier."""
        tid_str = self.to_uuid_str(task_id)
        rid_str = self.to_uuid_str(reminder_id)
        now = self.ensure_utc(datetime.now(timezone.utc))

        doc = self.collection.find_one_and_update(
            {"_id": tid_str},
            {
                "$pull": {"reminders": {"id": rid_str}},
                "$set": {"updated_at": now},
            },
            return_document=ReturnDocument.AFTER,
        )
        return self.format_document(doc)

    def add_follow_up(
        self,
        task_id: Union[str, uuid.UUID],
        follow_up_data: Union[Any, Dict[str, Any]],
    ) -> Optional[Dict[str, Any]]:
        """Push an embedded follow-up item to the task document."""
        tid_str = self.to_uuid_str(task_id)
        if hasattr(follow_up_data, "to_mongo"):
            payload = follow_up_data.to_mongo()
        else:
            payload = dict(follow_up_data)
        if "id" not in payload:
            payload["id"] = str(uuid.uuid4())
        payload["task_id"] = tid_str
        payload["scheduled_at"] = self.ensure_utc(payload.get("scheduled_at"))
        now = self.ensure_utc(datetime.now(timezone.utc))
        payload["created_at"] = self.ensure_utc(payload.get("created_at") or now)
        payload["updated_at"] = now

        doc = self.collection.find_one_and_update(
            {"_id": tid_str},
            {
                "$push": {"follow_ups": payload},
                "$set": {"updated_at": now},
            },
            return_document=ReturnDocument.AFTER,
        )
        return self.format_document(doc)

    def complete_follow_up(
        self,
        task_id: Union[str, uuid.UUID],
        follow_up_id: Union[str, uuid.UUID],
        completed_at: Optional[datetime] = None,
    ) -> Optional[Dict[str, Any]]:
        """Mark an embedded follow-up completed."""
        tid_str = self.to_uuid_str(task_id)
        fid_str = self.to_uuid_str(follow_up_id)
        now = self.ensure_utc(completed_at or datetime.now(timezone.utc))

        doc = self.collection.find_one_and_update(
            {"_id": tid_str, "follow_ups.id": fid_str},
            {
                "$set": {
                    "follow_ups.$.completed_at": now,
                    "follow_ups.$.updated_at": now,
                    "updated_at": now,
                }
            },
            return_document=ReturnDocument.AFTER,
        )
        return self.format_document(doc)

    def list_tasks(
        self,
        search: Optional[str] = None,
        status: Optional[Union[TaskStatus, str]] = None,
        priority: Optional[Union[TaskPriority, str]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        unassigned: Optional[bool] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        due_from: Optional[datetime] = None,
        due_to: Optional[datetime] = None,
        due_date_before: Optional[datetime] = None,
        next_action_from: Optional[datetime] = None,
        next_action_to: Optional[datetime] = None,
        next_action_before: Optional[datetime] = None,
        overdue: Optional[bool] = None,
        due_today: Optional[bool] = None,
        upcoming: Optional[bool] = None,
        has_next_action: Optional[bool] = None,
        no_next_action: Optional[bool] = None,
        near_max_attempts: Optional[bool] = None,
        sort_by: str = "created_at",
        sort_order: str = "desc",
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """Execute complex multi-criteria query matching the existing SQLAlchemy specification."""
        query: Dict[str, Any] = {}
        now = self.ensure_utc(datetime.now(timezone.utc))

        # Search across title, description, subject_line, and denormalized names
        if search and search.strip():
            escaped = re.escape(search.strip())
            pattern = {"$regex": escaped, "$options": "i"}
            query["$or"] = [
                {"title": pattern},
                {"description": pattern},
                {"subject_line": pattern},
                {"client_name": pattern},
                {"workflow_name": pattern},
                {"assigned_user_name": pattern},
                {"assigned_user_email": pattern},
            ]

        # Status and priority filters
        if status is not None:
            status_val = status.value if hasattr(status, "value") else str(status)
            query["status"] = status_val

        if priority is not None:
            prio_val = priority.value if hasattr(priority, "value") else str(priority)
            query["priority"] = prio_val

        # Assignment filters
        if unassigned is True:
            query["assigned_user_id"] = None
        elif assigned_user_id is not None:
            query["assigned_user_id"] = self.to_uuid_str(assigned_user_id)

        if client_id is not None:
            query["client_id"] = self.to_uuid_str(client_id)

        if workflow_id is not None:
            query["workflow_id"] = self.to_uuid_str(workflow_id)

        # Date range filters
        due_filters: Dict[str, Any] = {}
        if due_from is not None:
            due_filters["$gte"] = self.ensure_utc(due_from)
        if due_to is not None:
            due_filters["$lte"] = self.ensure_utc(due_to)
        elif due_date_before is not None:
            due_filters["$lte"] = self.ensure_utc(due_date_before)
        if due_filters:
            query["due_date"] = due_filters

        next_action_filters: Dict[str, Any] = {}
        if next_action_from is not None:
            next_action_filters["$gte"] = self.ensure_utc(next_action_from)
        if next_action_to is not None:
            next_action_filters["$lte"] = self.ensure_utc(next_action_to)
        elif next_action_before is not None:
            next_action_filters["$lte"] = self.ensure_utc(next_action_before)
        if next_action_filters:
            query["next_action_date"] = next_action_filters

        # Smart attention filters
        terminal_statuses = ["completed", "cancelled"]
        if overdue is True:
            query["due_date"] = {"$lt": now}
            query["status"] = {"$nin": terminal_statuses}

        if due_today is True:
            today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
            today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)
            query["due_date"] = {"$gte": today_start, "$lte": today_end}
            query["status"] = {"$nin": terminal_statuses}

        if upcoming is True:
            query["due_date"] = {"$gt": now}
            query["status"] = {"$nin": terminal_statuses}

        if no_next_action is True or has_next_action is False:
            query["next_action_date"] = None
        elif has_next_action is True:
            query["next_action_date"] = {"$ne": None}

        if near_max_attempts is True:
            query["status"] = {"$nin": terminal_statuses}
            query["$expr"] = {"$gte": ["$attempt_count", {"$subtract": ["$max_attempts", 1]}]}

        return self.paginate_find(
            query,
            sort_by=sort_by,
            sort_order=sort_order,
            page=page,
            page_size=page_size,
        )
