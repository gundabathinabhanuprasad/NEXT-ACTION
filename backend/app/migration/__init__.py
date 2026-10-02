"""Migration package for controlled PostgreSQL to MongoDB data replication, verification, and dual-write."""

from app.migration.coordinator import MigrationCoordinator
from app.migration.dual_write import (
    DualWriteOperation,
    DualWriteResult,
    DualWriter,
    dual_writer,
    is_dual_write_enabled,
    override_dual_write,
)
from app.migration.extractor import PostgreSQLExtractor
from app.migration.fingerprint import compute_fingerprint
from app.migration.loader import MongoDBLoader
from app.migration.reporter import MigrationReporter
from app.migration.rollback import MigrationRollback
from app.migration.state import MigrationError, MigrationState
from app.migration.transformer import EntityTransformer
from app.migration.validator import MigrationValidator
from app.migration.verifier import MigrationVerifier

__all__ = [
    "MigrationCoordinator",
    "PostgreSQLExtractor",
    "EntityTransformer",
    "MigrationValidator",
    "MongoDBLoader",
    "MigrationVerifier",
    "MigrationRollback",
    "MigrationReporter",
    "MigrationState",
    "MigrationError",
    "compute_fingerprint",
    "DualWriter",
    "dual_writer",
    "is_dual_write_enabled",
    "override_dual_write",
    "DualWriteResult",
    "DualWriteOperation",
]
