"""MongoDB repository for Event documents."""

from datetime import datetime
from typing import Any, Dict, List, Optional, Union
import uuid
from pymongo.database import Database
from app.documents.event import EventDocument
from app.repositories.mongodb_base import BaseMongoRepository


class EventRepository(BaseMongoRepository):
    """Data access repository for events collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("events", db=db)

    def create(self, event_data: Union[EventDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new event document."""
        if isinstance(event_data, EventDocument):
            payload = event_data.to_mongo()
        else:
            payload = dict(event_data)
        return self.insert_doc(payload)

    def get_by_id(self, event_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve an event by UUID string."""
        return self.find_by_id(event_id)

    def update(
        self,
        event_id: Union[str, uuid.UUID],
        fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update event fields."""
        return self.update_by_id(event_id, fields)

    def delete(self, event_id: Union[str, uuid.UUID]) -> bool:
        """Delete an event by ID."""
        return self.delete_by_id(event_id)

    def list_in_range(
        self,
        start_range: datetime,
        end_range: datetime,
        client_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> List[Dict[str, Any]]:
        """Find events that fall within a specified date/time window."""
        query: Dict[str, Any] = {
            "start_at": {"$gte": start_range, "$lte": end_range},
        }
        if client_id is not None:
            query["client_id"] = str(client_id)
        return self.find_many(query, sort_by="start_at", sort_order="asc")

    def list_for_task(self, task_id: Union[str, uuid.UUID]) -> List[Dict[str, Any]]:
        """Find events associated with a specific task."""
        query = {"task_id": str(task_id)}
        return self.find_many(query, sort_by="start_at", sort_order="asc")

    def list_for_client(self, client_id: Union[str, uuid.UUID]) -> List[Dict[str, Any]]:
        """Find events associated with a specific client."""
        query = {"client_id": str(client_id)}
        return self.find_many(query, sort_by="start_at", sort_order="asc")
