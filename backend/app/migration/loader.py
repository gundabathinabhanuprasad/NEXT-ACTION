"""Loader layer: Deterministic upsert into MongoDB with dependency-safe ordering and migration tagging."""

from typing import Any, Dict, List, Tuple
from pymongo.database import Database
from app.migration.state import MigrationError, MigrationState

# Dependency-safe loading order
MIGRATION_ORDER: List[str] = [
    "users",
    "user_settings",
    "clients",
    "workflows",
    "task_templates",
    "recurring_tasks",
    "tasks",
    "task_history",
    "recurring_task_executions",
    "notifications",
    "events",
    "refresh_tokens",
]


class MongoDBLoader:
    """Loads transformed documents into MongoDB collections with deterministic upsert."""

    def __init__(self, mongo_db: Database, migration_id: str):
        self.db = mongo_db
        self.mongo_db = mongo_db
        self.migration_id = migration_id

    def load_collection(
        self, collection_name: str, documents: List[Any]
    ) -> Tuple[int, int, List[MigrationError]]:
        """Upsert documents into the target collection.

        Args:
            collection_name: Target MongoDB collection name.
            documents: List of transformed Pydantic documents.

        Returns:
            Tuple of (inserted_count, updated_count, errors_list).
        """
        if not documents:
            return 0, 0, []

        from pymongo import ReplaceOne

        collection = self.mongo_db[collection_name]
        inserted_count = 0
        updated_count = 0
        errors: List[MigrationError] = []
        operations = []
        for doc in documents:
            doc_id = None
            try:
                if hasattr(doc, "to_mongo"):
                    payload = doc.to_mongo()
                elif hasattr(doc, "model_dump"):
                    payload = doc.model_dump(by_alias=True)
                else:
                    payload = dict(doc)

                doc_id = payload.get("_id") or payload.get("id")
                if not doc_id:
                    errors.append(
                        MigrationError(
                            entity=collection_name,
                            entity_id=None,
                            message=f"Missing primary identifier _id on {collection_name} document",
                        )
                    )
                    continue

                payload["_id"] = str(doc_id)
                if "id" in payload and payload["id"] == payload["_id"]:
                    del payload["id"]

                payload["_migration_id"] = self.migration_id
                operations.append(ReplaceOne({"_id": payload["_id"]}, payload, upsert=True))
            except Exception as e:
                errors.append(
                    MigrationError(
                        entity=collection_name,
                        entity_id=str(doc_id) if doc_id else None,
                        message=f"Document serialization error on {collection_name}: {e}",
                    )
                )

        if not operations:
            return 0, 0, errors

        batch_size = 1000
        for i in range(0, len(operations), batch_size):
            batch = operations[i : i + batch_size]
            try:
                res = collection.bulk_write(batch, ordered=False)
                inserted_count += res.upserted_count
                updated_count += res.matched_count
            except Exception as bulk_err:
                errors.append(
                    MigrationError(
                        entity=collection_name,
                        entity_id=None,
                        message=f"Bulk write error on {collection_name}: {bulk_err}",
                    )
                )

        return inserted_count, updated_count, errors

    def load_all(
        self, transformed_data: Dict[str, List[Any]], state: MigrationState
    ) -> MigrationState:
        """Load all transformed entities in dependency-safe order, recording metrics in state."""
        for col in MIGRATION_ORDER:
            docs = transformed_data.get(col, [])
            inserted, updated, errors = self.load_collection(col, docs)

            state.inserted[col] = inserted
            state.updated[col] = updated
            state.failed[col] = len(errors)
            state.errors.extend(errors)

        return state
