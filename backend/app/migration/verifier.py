"""Verification layer: Validates counts, task distributions, and canonical record checksums."""

from typing import Any, Dict, List
from pymongo.database import Database
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.migration.fingerprint import compute_fingerprint
from app.migration.loader import MIGRATION_ORDER
from app.migration.state import ChecksumMismatch
from app.models.enums import TaskPriority, TaskStatus
from app.models.task import Task


class MigrationVerifier:
    """Verifies data integrity and consistency between PostgreSQL and MongoDB."""

    def __init__(self, db: Session, mongo_db: Database):
        self.db = db
        self.mongo_db = mongo_db

    def get_mongodb_counts(self) -> Dict[str, int]:
        """Query document counts directly from all 12 MongoDB collections."""
        counts = {}
        for col in MIGRATION_ORDER:
            counts[col] = self.mongo_db[col].count_documents({})
        return counts

    def verify_counts(self, source_counts: Dict[str, int]) -> Dict[str, Dict[str, Any]]:
        """Compare source PostgreSQL counts with destination MongoDB counts."""
        mongo_counts = self.get_mongodb_counts()
        comparison = {}
        for col in MIGRATION_ORDER:
            pg_count = source_counts.get(col, 0)
            mg_count = mongo_counts.get(col, 0)
            comparison[col] = {
                "postgresql": pg_count,
                "mongodb": mg_count,
                "difference": mg_count - pg_count,
                "match": pg_count == mg_count,
            }
        return comparison

    def verify_task_distributions(self) -> Dict[str, Any]:
        """Verify detailed distributions of task statuses, priorities, attempts, and completion."""
        # PostgreSQL Task metrics
        pg_tasks = list(self.db.scalars(select(Task)).all())
        pg_status_dist = {}
        pg_priority_dist = {}
        pg_total_attempts = 0
        pg_completed_count = 0

        for t in pg_tasks:
            status_val = t.status.value if isinstance(t.status, TaskStatus) else str(t.status)
            priority_val = t.priority.value if isinstance(t.priority, TaskPriority) else str(t.priority)
            pg_status_dist[status_val] = pg_status_dist.get(status_val, 0) + 1
            pg_priority_dist[priority_val] = pg_priority_dist.get(priority_val, 0) + 1
            pg_total_attempts += t.attempt_count
            if t.completed_at is not None or status_val == "completed":
                pg_completed_count += 1

        # MongoDB Task metrics
        mongo_tasks = list(self.mongo_db["tasks"].find({}))
        mg_status_dist = {}
        mg_priority_dist = {}
        mg_total_attempts = 0
        mg_completed_count = 0

        for doc in mongo_tasks:
            status_val = doc.get("status")
            priority_val = doc.get("priority")
            mg_status_dist[status_val] = mg_status_dist.get(status_val, 0) + 1
            mg_priority_dist[priority_val] = mg_priority_dist.get(priority_val, 0) + 1
            mg_total_attempts += doc.get("attempt_count", 0)
            if doc.get("completed_at") is not None or status_val == "completed":
                mg_completed_count += 1

        return {
            "status_distribution": {
                "postgresql": pg_status_dist,
                "mongodb": mg_status_dist,
                "match": pg_status_dist == mg_status_dist,
            },
            "priority_distribution": {
                "postgresql": pg_priority_dist,
                "mongodb": mg_priority_dist,
                "match": pg_priority_dist == mg_priority_dist,
            },
            "total_attempts": {
                "postgresql": pg_total_attempts,
                "mongodb": mg_total_attempts,
                "match": pg_total_attempts == mg_total_attempts,
            },
            "completed_count": {
                "postgresql": pg_completed_count,
                "mongodb": mg_completed_count,
                "match": pg_completed_count == mg_completed_count,
            },
        }

    def verify_checksums(
        self, transformed_data: Dict[str, List[Any]]
    ) -> List[ChecksumMismatch]:
        """Compute and compare SHA-256 fingerprints between transformed source records and MongoDB documents."""
        mismatches: List[ChecksumMismatch] = []

        for col, docs in transformed_data.items():
            if not docs:
                continue
            collection = self.mongo_db[col]
            # Batch load all MongoDB documents in this collection into an in-memory map by _id
            mongo_docs = {str(d["_id"]): d for d in collection.find({})}

            for doc in docs:
                if hasattr(doc, "to_mongo"):
                    source_dict = doc.to_mongo()
                elif hasattr(doc, "model_dump"):
                    source_dict = doc.model_dump(by_alias=True)
                else:
                    source_dict = dict(doc)

                doc_id = str(source_dict.get("_id") or source_dict.get("id"))
                pg_fingerprint = compute_fingerprint(source_dict, entity_type=col)

                mongo_doc = mongo_docs.get(doc_id)
                if not mongo_doc:
                    mismatches.append(
                        ChecksumMismatch(
                            entity=col,
                            entity_id=doc_id,
                            postgres_fingerprint=pg_fingerprint,
                            mongodb_fingerprint="<missing>",
                        )
                    )
                    continue

                mg_fingerprint = compute_fingerprint(mongo_doc, entity_type=col)
                if pg_fingerprint != mg_fingerprint:
                    mismatches.append(
                        ChecksumMismatch(
                            entity=col,
                            entity_id=doc_id,
                            postgres_fingerprint=pg_fingerprint,
                            mongodb_fingerprint=mg_fingerprint,
                            postgres_data=source_dict,
                            mongodb_data=mongo_doc,
                        )
                    )

        return mismatches
