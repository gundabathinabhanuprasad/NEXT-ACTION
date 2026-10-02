"""MongoDB repository for TaskTemplate documents."""

from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
from pymongo.database import Database
from app.documents.task_template import TaskTemplateDocument
from app.repositories.mongodb_base import BaseMongoRepository


class TaskTemplateRepository(BaseMongoRepository):
    """Data access repository for task_templates collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("task_templates", db=db)

    def create(self, template_data: Union[TaskTemplateDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new task template document."""
        if isinstance(template_data, TaskTemplateDocument):
            payload = template_data.to_mongo()
        else:
            payload = dict(template_data)
        return self.insert_doc(payload)

    def get_by_id(self, template_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve a task template by UUID string."""
        return self.find_by_id(template_id)

    def update(
        self,
        template_id: Union[str, uuid.UUID],
        fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update task template fields."""
        return self.update_by_id(template_id, fields)

    def delete(self, template_id: Union[str, uuid.UUID]) -> bool:
        """Delete a task template by ID."""
        return self.delete_by_id(template_id)

    def list_templates(
        self,
        is_active: Optional[bool] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """List templates with optional filtering and pagination."""
        query: Dict[str, Any] = {}
        if is_active is not None:
            query["is_active"] = is_active
        if workflow_id is not None:
            query["workflow_id"] = str(workflow_id)
        if client_id is not None:
            query["client_id"] = str(client_id)
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
