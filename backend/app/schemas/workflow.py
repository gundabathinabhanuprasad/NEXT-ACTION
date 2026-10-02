"""Workflow request and response schemas."""

from datetime import datetime
from typing import List, Optional
import uuid
from pydantic import BaseModel, ConfigDict, Field


class WorkflowBase(BaseModel):
    """Base fields for Workflow process entity."""

    name: str = Field(min_length=1, max_length=255, description="Workflow name")
    description: Optional[str] = Field(default=None, description="Workflow process description")
    is_active: bool = Field(default=True, description="Whether workflow is active")


class WorkflowCreate(WorkflowBase):
    """Schema for creating a new workflow."""

    pass


class WorkflowUpdate(BaseModel):
    """Schema for updating an existing workflow."""

    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    description: Optional[str] = None
    is_active: Optional[bool] = None


class WorkflowResponse(WorkflowBase):
    """Response schema for a single workflow."""

    id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class WorkflowListResponse(BaseModel):
    """Paginated / collection list of workflows."""

    items: List[WorkflowResponse]
    total: int
    page: int = 1
    page_size: int = 100
