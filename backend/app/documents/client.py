"""MongoDB document schema for Client entity."""

from typing import Optional
from pydantic import Field
from app.documents.common import BaseDocument


class ClientDocument(BaseDocument):
    """Client / Contact entity document."""

    name: str = Field(min_length=1, max_length=255)
    company: Optional[str] = Field(default=None, max_length=255)
    email: Optional[str] = Field(default=None, max_length=255)
    phone: Optional[str] = Field(default=None, max_length=50)
    notes: Optional[str] = Field(default=None)
