"""MongoDB Workflow Service implementation."""

from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.documents.workflow import WorkflowDocument
from app.repositories import WorkflowRepository
from app.services.exceptions import WorkflowNotFoundError


class MongoWorkflowService:
    """Workflow service implementation using MongoDB collections and repositories."""

    def __init__(self, workflow_repo: Optional[WorkflowRepository] = None):
        self.workflow_repo = workflow_repo or WorkflowRepository()

    def _to_doc(self, raw_data: Optional[Dict[str, Any]]) -> WorkflowDocument:
        if raw_data is None:
            raise WorkflowNotFoundError("Unknown")
        return WorkflowDocument.model_validate(raw_data)

    def create_workflow(
        self,
        db: Any = None,
        name: str = "",
        description: Optional[str] = None,
        is_active: bool = True,
    ) -> WorkflowDocument:
        """Create a new workflow definition."""
        doc = WorkflowDocument(
            name=name.strip(),
            description=description.strip() if description else None,
            is_active=is_active,
        )
        saved = self.workflow_repo.create(doc)
        return self._to_doc(saved)

    def get_workflow(
        self,
        db: Any = None,
        workflow_id: Union[str, uuid.UUID] = "",
    ) -> WorkflowDocument:
        """Retrieve workflow by ID or raise WorkflowNotFoundError."""
        wf_dict = self.workflow_repo.get_by_id(workflow_id)
        if not wf_dict:
            raise WorkflowNotFoundError(workflow_id)
        return self._to_doc(wf_dict)

    def list_workflows(
        self,
        db: Any = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 100,
    ) -> Tuple[List[WorkflowDocument], int]:
        """List workflows with filtering and pagination."""
        items, total = self.workflow_repo.list_workflows(
            is_active=is_active,
            search=search,
            page=page,
            page_size=page_size,
        )
        return [self._to_doc(i) for i in items], total

    def update_workflow(
        self,
        db: Any = None,
        workflow_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        description: Optional[str] = None,
        is_active: Optional[bool] = None,
    ) -> WorkflowDocument:
        """Update workflow fields."""
        wf = self.get_workflow(workflow_id=workflow_id)
        updates: Dict[str, Any] = {}
        if name is not None:
            updates["name"] = name.strip()
        if description is not None:
            updates["description"] = description.strip() if description else None
        if is_active is not None:
            updates["is_active"] = is_active

        if updates:
            updated = self.workflow_repo.update(wf.id, updates)
            return self._to_doc(updated)
        return wf

    def delete_workflow(
        self,
        db: Any = None,
        workflow_id: Union[str, uuid.UUID] = "",
    ) -> bool:
        """Delete workflow by identifier."""
        self.get_workflow(workflow_id=workflow_id)
        return self.workflow_repo.delete(workflow_id)
