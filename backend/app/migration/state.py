"""Migration state, execution metadata, and tracking models."""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import uuid
from pydantic import BaseModel, Field


def utcnow() -> datetime:
    """Return timezone-aware current UTC datetime."""
    return datetime.now(timezone.utc)


def generate_migration_id() -> str:
    """Generate a unique, human-readable migration identifier."""
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    suffix = uuid.uuid4().hex[:6]
    return f"mig_{timestamp}_{suffix}"


class MigrationError(BaseModel):
    """Detailed record of a migration or validation error."""

    entity: str
    entity_id: Optional[str] = None
    field: Optional[str] = None
    message: str
    timestamp: datetime = Field(default_factory=utcnow)


class ChecksumMismatch(BaseModel):
    """Details of a record fingerprint mismatch between PostgreSQL and MongoDB."""

    entity: str
    entity_id: str
    postgres_fingerprint: str
    mongodb_fingerprint: str
    postgres_data: Optional[Dict[str, Any]] = None
    mongodb_data: Optional[Dict[str, Any]] = None


class RelationshipError(BaseModel):
    """Detailed record of a broken foreign key reference."""

    parent_entity: str
    parent_id: str
    reference_field: str
    referenced_entity: str
    broken_id: str
    message: str


class MigrationState(BaseModel):
    """Comprehensive state and metrics container for a migration run."""

    migration_id: str = Field(default_factory=generate_migration_id)
    start_time: datetime = Field(default_factory=utcnow)
    end_time: Optional[datetime] = None
    mode: str = "dry-run"  # "dry-run", "migrate", "verify", "rollback"
    status: str = "running"  # "running", "completed", "failed", "rolled_back"
    source_database: str = "postgresql"
    destination_database: str = "mongodb"

    # Extraction counts from PostgreSQL
    source_counts: Dict[str, int] = Field(default_factory=dict)
    # Destination counts in MongoDB before / after
    destination_counts_before: Dict[str, int] = Field(default_factory=dict)
    destination_counts_after: Dict[str, int] = Field(default_factory=dict)

    # Operation metrics per collection
    inserted: Dict[str, int] = Field(default_factory=dict)
    updated: Dict[str, int] = Field(default_factory=dict)
    skipped: Dict[str, int] = Field(default_factory=dict)
    invalid: Dict[str, int] = Field(default_factory=dict)
    failed: Dict[str, int] = Field(default_factory=dict)

    # Detailed logs and errors
    errors: List[MigrationError] = Field(default_factory=list)
    checksum_mismatches: List[ChecksumMismatch] = Field(default_factory=list)
    relationship_errors: List[RelationshipError] = Field(default_factory=list)

    # Summary notes / metadata
    metadata: Dict[str, Any] = Field(default_factory=dict)

    def mark_completed(self) -> None:
        """Mark migration run as successfully finished."""
        self.end_time = utcnow()
        self.status = "completed"

    def mark_failed(self, error_message: str) -> None:
        """Mark migration run as failed with a top-level error."""
        self.end_time = utcnow()
        self.status = "failed"
        self.errors.append(
            MigrationError(
                entity="system",
                entity_id=None,
                field=None,
                message=error_message,
            )
        )

    def mark_rolled_back(self) -> None:
        """Mark migration run as rolled back."""
        self.end_time = utcnow()
        self.status = "rolled_back"
