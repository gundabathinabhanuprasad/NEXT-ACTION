"""Common base classes, timestamp helpers, and configuration for MongoDB Pydantic documents."""

from datetime import datetime, timezone
from typing import Any, Dict
import uuid
from pydantic import BaseModel, ConfigDict, Field


def utcnow() -> datetime:
    """Return timezone-aware current UTC datetime."""
    return datetime.now(timezone.utc)


class BaseSubDocument(BaseModel):
    """Base schema for embedded subdocuments without an independent collection."""

    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)

    model_config = ConfigDict(
        populate_by_name=True,
        arbitrary_types_allowed=True,
        use_enum_values=True,
    )

    def to_mongo(self) -> Dict[str, Any]:
        """Dump subdocument representation suitable for MongoDB storage."""
        return self.model_dump(by_alias=True)

    def to_domain(self) -> Dict[str, Any]:
        """Dump subdocument representation suitable for domain consumption."""
        return self.model_dump(by_alias=False)


class BaseDocument(BaseModel):
    """Base schema for top-level MongoDB collection documents.

    Uses string UUIDs as _id to maintain 100% semantic and operational parity
    with PostgreSQL UUID primary keys.
    """

    id: str = Field(default_factory=lambda: str(uuid.uuid4()), alias="_id")
    created_at: datetime = Field(default_factory=utcnow)
    updated_at: datetime = Field(default_factory=utcnow)

    model_config = ConfigDict(
        populate_by_name=True,
        arbitrary_types_allowed=True,
        use_enum_values=True,
    )

    def to_mongo(self) -> Dict[str, Any]:
        """Dump document representation suitable for MongoDB storage (using _id)."""
        return self.model_dump(by_alias=True)

    def to_domain(self) -> Dict[str, Any]:
        """Dump document representation suitable for domain/API consumption (using id)."""
        return self.model_dump(by_alias=False)
