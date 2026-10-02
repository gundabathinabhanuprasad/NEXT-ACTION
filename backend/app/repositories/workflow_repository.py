"""MongoDB repository for Workflow documents."""

from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
import re
from pymongo.database import Database
from app.documents.workflow import WorkflowDocument
from app.repositories.mongodb_base import BaseMongoRepository


class WorkflowRepository(BaseMongoRepository):
    """Data access repository for workflows collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("workflows", db=db)

    def create(self, workflow_data: Union[WorkflowDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new workflow document."""
        if isinstance(workflow_data, WorkflowDocument):
            payload = workflow_data.to_mongo()
        else:
            payload = dict(workflow_data)
        return self.insert_doc(payload)

    def get_by_id(self, workflow_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve workflow by identifier."""
        return self.find_by_id(workflow_id)

    def update(
        self,
        workflow_id: Union[str, uuid.UUID],
        fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update workflow fields."""
        return self.update_by_id(workflow_id, fields)

    def delete(self, workflow_id: Union[str, uuid.UUID]) -> bool:
        """Delete workflow by identifier."""
        return self.delete_by_id(workflow_id)

    def list_workflows(
        self,
        is_active: Optional[bool] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """List workflows with optional active filter and name/description search."""
        query: Dict[str, Any] = {}
        if is_active is not None:
            query["is_active"] = is_active
        if search and search.strip():
            escaped = re.escape(search.strip())
            pattern = {"$regex": escaped, "$options": "i"}
            query["$or"] = [
                {"name": pattern},
                {"description": pattern},
            ]
        return self.paginate_find(query, sort_by="name", sort_order="asc", page=page, page_size=page_size)

    def list_active(self) -> List[Dict[str, Any]]:
        """Retrieve all active workflows."""
        return self.find_many({"is_active": True}, sort_by="name", sort_order="asc")
