"""MongoDB repository for RecurringTask documents."""

from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
from pymongo.database import Database
from app.documents.common import utcnow
from app.documents.recurring_task import RecurringTaskDocument
from app.repositories.mongodb_base import BaseMongoRepository


class RecurringTaskRepository(BaseMongoRepository):
    """Data access repository for recurring_tasks collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("recurring_tasks", db=db)

    def create(self, task_data: Union[RecurringTaskDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new recurring task schedule definition."""
        if isinstance(task_data, RecurringTaskDocument):
            payload = task_data.to_mongo()
        else:
            payload = dict(task_data)
        return self.insert_doc(payload)

    def get_by_id(self, task_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve recurring task by UUID string."""
        return self.find_by_id(task_id)

    def update(
        self,
        task_id: Union[str, uuid.UUID],
        fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update recurring task schedule configuration."""
        return self.update_by_id(task_id, fields)

    def delete(self, task_id: Union[str, uuid.UUID]) -> bool:
        """Delete recurring task definition."""
        return self.delete_by_id(task_id)

    def list_due(
        self,
        before_timestamp: Optional[datetime] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """Find active recurring tasks scheduled to execute at or before before_timestamp."""
        cutoff = before_timestamp or utcnow()
        query = {
            "is_active": True,
            "next_run_at": {"$lte": cutoff},
            "$or": [
                {"end_date": None},
                {"end_date": {"$gt": cutoff}},
            ],
        }
        return self.find_many(query, sort_by="next_run_at", sort_order="asc", limit=limit)

    def update_next_run(
        self,
        task_id: Union[str, uuid.UUID],
        next_run_at: datetime,
        last_run_at: Optional[datetime] = None,
    ) -> Optional[Dict[str, Any]]:
        """Advance schedule after an execution occurs."""
        now = utcnow()
        update_fields: Dict[str, Any] = {
            "next_run_at": next_run_at,
            "last_run_at": last_run_at or now,
            "updated_at": now,
        }
        return self.update_by_id(task_id, update_fields)

    def list_recurring(
        self,
        is_active: Optional[bool] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """List recurring tasks with optional is_active filter, search, and pagination."""
        query: Dict[str, Any] = {}
        if is_active is not None:
            query["is_active"] = is_active
        if created_by_user_id is not None:
            query["created_by_user_id"] = str(created_by_user_id)
        if search and search.strip():
            term = search.strip()
            query["$or"] = [
                {"name": {"$regex": term, "$options": "i"}},
                {"description": {"$regex": term, "$options": "i"}},
                {"subject_line": {"$regex": term, "$options": "i"}},
            ]
        return self.paginate_find(query, sort_by="created_at", sort_order="desc", page=page, page_size=page_size)
