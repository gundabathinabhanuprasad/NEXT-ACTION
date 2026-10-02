"""MongoDB document schema for Notification entity."""

from datetime import datetime
from typing import Optional
from pydantic import Field
from app.documents.common import BaseDocument


class NotificationDocument(BaseDocument):
    """In-app persistent notification document for attention management."""

    user_id: str = Field(description="Recipient User UUID string")
    task_id: Optional[str] = Field(default=None, description="Related Task UUID string")
    type: str = Field(min_length=1, max_length=50)
    title: str = Field(min_length=1, max_length=255)
    message: str = Field(min_length=1)
    dedup_key: Optional[str] = Field(default=None, max_length=255)
    is_read: bool = Field(default=False)
    read_at: Optional[datetime] = Field(default=None)
