"""MongoDB document schema for Workflow entity."""

from typing import Optional
from pydantic import Field
from app.documents.common import BaseDocument


class WorkflowDocument(BaseDocument):
    """Workflow process group entity document."""

    name: str = Field(min_length=1, max_length=255)
    description: Optional[str] = Field(default=None)
    is_active: bool = Field(default=True)
