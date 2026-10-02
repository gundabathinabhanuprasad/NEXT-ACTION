"""Workflow service encapsulating Workflow CRUD operations.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import WorkflowNotFoundError


def get_workflow(db: Optional[Session] = None, workflow_id: Union[str, uuid.UUID] = "") -> Any:
    """Retrieve a workflow by ID or raise WorkflowNotFoundError."""
    return get_persistence_gateway().workflow_service.get_workflow(db=db, workflow_id=workflow_id)


def create_workflow(
    db: Optional[Session] = None,
    name: str = "",
    description: Optional[str] = None,
    is_active: bool = True,
) -> Any:
    """Create and persist a new Workflow entity."""
    return get_persistence_gateway().workflow_service.create_workflow(
        db=db,
        name=name,
        description=description,
        is_active=is_active,
    )


def update_workflow(
    db: Optional[Session] = None,
    workflow_id: Union[str, uuid.UUID] = "",
    name: Optional[str] = None,
    description: Optional[str] = None,
    is_active: Optional[bool] = None,
) -> Any:
    """Update existing workflow attributes."""
    return get_persistence_gateway().workflow_service.update_workflow(
        db=db,
        workflow_id=workflow_id,
        name=name,
        description=description,
        is_active=is_active,
    )


def delete_workflow(db: Optional[Session] = None, workflow_id: Union[str, uuid.UUID] = "") -> bool:
    """Delete existing workflow."""
    return get_persistence_gateway().workflow_service.delete_workflow(db=db, workflow_id=workflow_id)


def list_workflows(
    db: Optional[Session] = None,
    search: Optional[str] = None,
    is_active: Optional[bool] = None,
    page: int = 1,
    page_size: int = 100,
) -> Tuple[List[Any], int]:
    """Retrieve filtered and paginated list of workflows."""
    return get_persistence_gateway().workflow_service.list_workflows(
        db=db,
        search=search,
        is_active=is_active,
        page=page,
        page_size=page_size,
    )
