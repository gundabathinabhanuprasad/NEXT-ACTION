"""MongoDB document schema for User entity."""

from typing import Optional
from pydantic import Field, field_validator
from app.documents.common import BaseDocument


class UserDocument(BaseDocument):
    """User account entity document."""

    name: str = Field(min_length=1, max_length=255)
    email: str = Field(min_length=3, max_length=255)
    password_hash: str = Field(default="", max_length=255)
    is_active: bool = Field(default=True)
    google_id: Optional[str] = Field(default=None, max_length=255)
    auth_provider: str = Field(default="local", max_length=50)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        """Enforce lowercase, stripped, and valid email address format."""
        cleaned = v.strip().lower()
        if "@" not in cleaned or "." not in cleaned.split("@")[-1]:
            raise ValueError("Invalid email format")
        return cleaned
