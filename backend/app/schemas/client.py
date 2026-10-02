"""Client request and response schemas."""

from datetime import datetime
from typing import List, Optional
import uuid
from pydantic import BaseModel, ConfigDict, Field


class ClientBase(BaseModel):
    """Base fields for Client entity."""

    name: str = Field(min_length=1, max_length=255, description="Client or Contact Name")
    company: Optional[str] = Field(default=None, max_length=255, description="Company / Organization Name")
    email: Optional[str] = Field(default=None, max_length=255, description="Email address")
    phone: Optional[str] = Field(default=None, max_length=50, description="Phone number")
    notes: Optional[str] = Field(default=None, description="General client notes")


class ClientCreate(ClientBase):
    """Schema for creating a new client."""

    pass


class ClientUpdate(BaseModel):
    """Schema for updating an existing client."""

    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    company: Optional[str] = Field(default=None, max_length=255)
    email: Optional[str] = Field(default=None, max_length=255)
    phone: Optional[str] = Field(default=None, max_length=50)
    notes: Optional[str] = None


class ClientResponse(ClientBase):
    """Response schema for a single client."""

    id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ClientListResponse(BaseModel):
    """Paginated / collection list of clients."""

    items: List[ClientResponse]
    total: int
    page: int = 1
    page_size: int = 100
