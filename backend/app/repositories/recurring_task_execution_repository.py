"""MongoDB repository for RecurringTaskExecution idempotency tracking."""

from datetime import datetime
from typing import Any, Dict, List, Optional, Union
import uuid
from pymongo.database import Database
from app.documents.recurring_task import RecurringTaskExecutionDocument
from app.repositories.mongodb_base import BaseMongoRepository


class RecurringTaskExecutionRepository(BaseMongoRepository):
    """Data access repository for recurring_task_executions collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("recurring_task_executions", db=db)

    def record_execution(
        self,
        execution_data: Union[RecurringTaskExecutionDocument, Dict[str, Any]],
    ) -> Dict[str, Any]:
        """Record an execution run for idempotency tracking."""
        if isinstance(execution_data, RecurringTaskExecutionDocument):
            payload = execution_data.to_mongo()
        else:
            payload = dict(execution_data)
        return self.insert_doc(payload)

    def get_by_id(self, execution_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve execution record by UUID string."""
        return self.find_by_id(execution_id)

    def get_execution(
        self,
        recurring_task_id: Union[str, uuid.UUID],
        scheduled_for: datetime,
    ) -> Optional[Dict[str, Any]]:
        """Look up execution record by recurring_task_id and target scheduled_for datetime."""
        return self.find_one({
            "recurring_task_id": str(recurring_task_id),
            "scheduled_for": scheduled_for,
        })

    def is_already_executed(
        self,
        recurring_task_id: Union[str, uuid.UUID],
        scheduled_for: datetime,
    ) -> bool:
        """Check if an execution has already occurred for this recurring task slot."""
        return self.exists({
            "recurring_task_id": str(recurring_task_id),
            "scheduled_for": scheduled_for,
        })

    def list_for_recurring_task(
        self,
        recurring_task_id: Union[str, uuid.UUID],
        limit: int = 50,
        skip: int = 0,
    ) -> List[Dict[str, Any]]:
        """List execution records for a recurring task ordered descending by execution time."""
        query = {"recurring_task_id": str(recurring_task_id)}
        return self.find_many(query, sort_by="executed_at", sort_order="desc", limit=limit, skip=skip)
