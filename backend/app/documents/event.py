"""MongoDB document schema for Event entity."""

from datetime import datetime
from typing import Optional
from pydantic import Field
from app.documents.common import BaseDocument


class EventDocument(BaseDocument):
    """Calendar activity or appointment document."""

    title: str = Field(min_length=1, max_length=255)
    description: Optional[str] = Field(default=None)
    start_at: datetime = Field(description="Event start UTC timestamp")
    end_at: Optional[datetime] = Field(default=None)
    location: Optional[str] = Field(default=None, max_length=255)
    task_id: Optional[str] = Field(default=None)
    client_id: Optional[str] = Field(default=None)
