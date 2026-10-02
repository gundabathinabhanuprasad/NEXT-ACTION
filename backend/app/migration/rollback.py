"""Rollback layer: Safely removes only MongoDB data created by a specific migration run."""

from typing import Dict
from pymongo.database import Database
from app.migration.loader import MIGRATION_ORDER


class MigrationRollback:
    """Reverts a migration run by removing only tagged MongoDB documents, leaving PostgreSQL untouched."""

    @staticmethod
    def rollback(mongo_db: Database, migration_id: str) -> Dict[str, int]:
        """Delete all MongoDB documents associated with the given migration_id across all collections.

        Guarantees:
        1. PostgreSQL is NEVER modified, queried for deletion, or touched.
        2. Only documents bearing the explicit _migration_id tag are removed.
        3. Pre-existing MongoDB documents with different migration IDs or no tags are preserved.

        Args:
            mongo_db: Target MongoDB database.
            migration_id: Unique identifier of the migration run to revert.

        Returns:
            Dictionary mapping collection names to the count of deleted documents.
        """
        deleted_counts: Dict[str, int] = {}

        for col in MIGRATION_ORDER:
            collection = mongo_db[col]
            res = collection.delete_many({"_migration_id": migration_id})
            deleted_counts[col] = res.deleted_count

        return deleted_counts
