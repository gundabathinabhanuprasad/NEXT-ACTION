"""MongoDB repository for TaskHistory audit documents."""

from typing import Any, Dict, List, Optional, Union
import uuid
from pymongo.database import Database
from app.documents.task_history import TaskHistoryDocument
from app.repositories.mongodb_base import BaseMongoRepository


class TaskHistoryRepository(BaseMongoRepository):
    """Data access repository for task_history collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("task_history", db=db)

    def create(self, history_data: Union[TaskHistoryDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new task history entry."""
        if isinstance(history_data, TaskHistoryDocument):
            payload = history_data.to_mongo()
        else:
            payload = dict(history_data)
        return self.insert_doc(payload)

    def log_history(
        self,
        task_id: Optional[Union[str, uuid.UUID]],
        action: str,
        old_value: Optional[str] = None,
        new_value: Optional[str] = None,
        reason: Optional[str] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> Dict[str, Any]:
        """Convenience method to construct and record an audit log event."""
        task_str = str(task_id) if task_id is not None else None
        user_str = str(created_by_user_id) if created_by_user_id is not None else None
        doc = TaskHistoryDocument(
            task_id=task_str,
            action=action,
            old_value=old_value,
            new_value=new_value,
            reason=reason,
            created_by_user_id=user_str,
        )
        return self.insert_doc(doc.to_mongo())

    def get_by_id(self, history_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve a history record by ID."""
        return self.find_by_id(history_id)

    def list_for_task(
        self,
        task_id: Union[str, uuid.UUID],
        limit: int = 100,
        skip: int = 0,
    ) -> List[Dict[str, Any]]:
        """List audit history entries for a specific task, ordered descending by timestamp."""
        query = {"task_id": str(task_id)}
        return self.find_many(query, sort_by="created_at", sort_order="desc", limit=limit, skip=skip)

    def list_recent(
        self,
        limit: int = 100,
        skip: int = 0,
    ) -> List[Dict[str, Any]]:
        """List most recent audit history entries across all tasks."""
        return self.find_many({}, sort_by="created_at", sort_order="desc", limit=limit, skip=skip)

    def count_for_task(self, task_id: Union[str, uuid.UUID]) -> int:
        """Count audit records for a task."""
        return self.count({"task_id": str(task_id)})

    def delete_for_task(self, task_id: Union[str, uuid.UUID]) -> int:
        """Delete all history entries for a given task."""
        return self.delete_many({"task_id": str(task_id)})
