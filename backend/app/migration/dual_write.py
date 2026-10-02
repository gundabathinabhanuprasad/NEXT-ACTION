"""Controlled dual-write synchronization layer (PostgreSQL -> MongoDB).

Writes commit to PostgreSQL first (source of truth), then asynchronously or synchronously
synchronizes the equivalent document representation to MongoDB under an eventual-consistency contract.
"""

from contextlib import contextmanager
from contextvars import ContextVar
from datetime import datetime, timezone
from enum import Enum
import logging
from typing import Any, Callable, Dict, List, Optional
from pydantic import BaseModel, Field
from pymongo.database import Database

from app.core.config import settings
from app.db.mongodb import get_mongodb_database
from app.migration.transformer import EntityTransformer

logger = logging.getLogger("nextaction.dual_write")

_dual_write_override: ContextVar[Optional[bool]] = ContextVar("dual_write_override", default=None)


class DualWriteOperation(str, Enum):
    """Operation type for dual-write persistence synchronization."""

    CREATE = "CREATE"
    UPDATE = "UPDATE"
    DELETE = "DELETE"


class DualWriteResult(BaseModel):
    """Observable record of a MongoDB dual-write synchronization event."""

    success: bool
    entity: str
    entity_id: str
    operation: DualWriteOperation
    error: Optional[str] = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


def is_dual_write_enabled() -> bool:
    """Check if dual-write synchronization is currently active."""
    override = _dual_write_override.get()
    if override is not None:
        return override
    return getattr(settings, "MONGODB_DUAL_WRITE_ENABLED", False)


@contextmanager
def override_dual_write(enabled: bool = True):
    """Context manager for temporarily enabling or disabling dual-write in scoped blocks/tests."""
    token = _dual_write_override.set(enabled)
    try:
        yield
    finally:
        _dual_write_override.reset(token)


class DualWriter:
    """Manages dual-write replication from PostgreSQL to MongoDB."""

    def __init__(self, mongo_db: Optional[Database] = None):
        self._mongo_db = mongo_db
        self._recent_results: List[DualWriteResult] = []
        self._failure_hook: Optional[Callable[[DualWriteResult], None]] = None

    def _get_db(self) -> Optional[Database]:
        if self._mongo_db is not None:
            return self._mongo_db
        try:
            return get_mongodb_database()
        except Exception:
            return None

    def set_failure_hook(self, hook: Optional[Callable[[DualWriteResult], None]]) -> None:
        """Register a callback for dual-write synchronization failures."""
        self._failure_hook = hook

    def get_recent_results(self) -> List[DualWriteResult]:
        """Return audit history of recent dual-write synchronization results."""
        return list(self._recent_results)

    def clear_recent_results(self) -> None:
        """Clear recorded dual-write results."""
        self._recent_results.clear()

    def _record_result(self, result: DualWriteResult) -> DualWriteResult:
        """Record and log synchronization result with observable status."""
        self._recent_results.append(result)
        if not result.success:
            logger.error(
                f"[DUAL-WRITE ERROR] Sync failed for {result.entity} (id={result.entity_id}, op={result.operation}): {result.error}"
            )
            if self._failure_hook:
                try:
                    self._failure_hook(result)
                except Exception as hook_err:
                    logger.error(f"[DUAL-WRITE HOOK ERROR] Failure hook threw: {hook_err}")
        else:
            logger.debug(
                f"[DUAL-WRITE SUCCESS] Synced {result.entity} (id={result.entity_id}, op={result.operation})"
            )
        return result

    def sync_user(self, user: Any, operation: DualWriteOperation) -> DualWriteResult:
        """Sync User entity to MongoDB."""
        if not is_dual_write_enabled():
            return DualWriteResult(
                success=True, entity="users", entity_id=str(getattr(user, "id", "")), operation=operation
            )

        user_id = str(getattr(user, "id", ""))
        db = self._get_db()
        if db is None:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="users",
                    entity_id=user_id,
                    operation=operation,
                    error="MongoDB database connection unavailable",
                )
            )

        try:
            if operation == DualWriteOperation.DELETE:
                db["users"].delete_one({"_id": user_id})
            else:
                doc = EntityTransformer.transform_user(user)
                payload = doc.to_mongo()
                db["users"].replace_one({"_id": user_id}, payload, upsert=True)
            return self._record_result(
                DualWriteResult(success=True, entity="users", entity_id=user_id, operation=operation)
            )
        except Exception as e:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="users",
                    entity_id=user_id,
                    operation=operation,
                    error=str(e),
                )
            )

    def sync_client(self, client: Any, operation: DualWriteOperation) -> DualWriteResult:
        """Sync Client entity to MongoDB."""
        if not is_dual_write_enabled():
            return DualWriteResult(
                success=True, entity="clients", entity_id=str(getattr(client, "id", "")), operation=operation
            )

        client_id = str(getattr(client, "id", ""))
        db = self._get_db()
        if db is None:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="clients",
                    entity_id=client_id,
                    operation=operation,
                    error="MongoDB database connection unavailable",
                )
            )

        try:
            if operation == DualWriteOperation.DELETE:
                db["clients"].delete_one({"_id": client_id})
            else:
                doc = EntityTransformer.transform_client(client)
                payload = doc.to_mongo()
                db["clients"].replace_one({"_id": client_id}, payload, upsert=True)
            return self._record_result(
                DualWriteResult(success=True, entity="clients", entity_id=client_id, operation=operation)
            )
        except Exception as e:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="clients",
                    entity_id=client_id,
                    operation=operation,
                    error=str(e),
                )
            )

    def sync_workflow(self, workflow: Any, operation: DualWriteOperation) -> DualWriteResult:
        """Sync Workflow entity to MongoDB."""
        if not is_dual_write_enabled():
            return DualWriteResult(
                success=True, entity="workflows", entity_id=str(getattr(workflow, "id", "")), operation=operation
            )

        wf_id = str(getattr(workflow, "id", ""))
        db = self._get_db()
        if db is None:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="workflows",
                    entity_id=wf_id,
                    operation=operation,
                    error="MongoDB database connection unavailable",
                )
            )

        try:
            if operation == DualWriteOperation.DELETE:
                db["workflows"].delete_one({"_id": wf_id})
            else:
                doc = EntityTransformer.transform_workflow(workflow)
                payload = doc.to_mongo()
                db["workflows"].replace_one({"_id": wf_id}, payload, upsert=True)
            return self._record_result(
                DualWriteResult(success=True, entity="workflows", entity_id=wf_id, operation=operation)
            )
        except Exception as e:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="workflows",
                    entity_id=wf_id,
                    operation=operation,
                    error=str(e),
                )
            )

    def sync_task(self, task: Any, operation: DualWriteOperation) -> DualWriteResult:
        """Sync Task entity (with embedded reminders & follow-ups) to MongoDB."""
        if not is_dual_write_enabled():
            return DualWriteResult(
                success=True, entity="tasks", entity_id=str(getattr(task, "id", "")), operation=operation
            )

        task_id = str(getattr(task, "id", ""))
        db = self._get_db()
        if db is None:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="tasks",
                    entity_id=task_id,
                    operation=operation,
                    error="MongoDB database connection unavailable",
                )
            )

        try:
            if operation == DualWriteOperation.DELETE:
                db["tasks"].delete_one({"_id": task_id})
            else:
                doc = EntityTransformer.transform_task(task)
                payload = doc.to_mongo()
                db["tasks"].replace_one({"_id": task_id}, payload, upsert=True)
            return self._record_result(
                DualWriteResult(success=True, entity="tasks", entity_id=task_id, operation=operation)
            )
        except Exception as e:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="tasks",
                    entity_id=task_id,
                    operation=operation,
                    error=str(e),
                )
            )

    def sync_task_history(self, history: Any, operation: DualWriteOperation) -> DualWriteResult:
        """Sync TaskHistory audit log to MongoDB."""
        if not is_dual_write_enabled():
            return DualWriteResult(
                success=True,
                entity="task_history",
                entity_id=str(getattr(history, "id", "")),
                operation=operation,
            )

        hist_id = str(getattr(history, "id", ""))
        db = self._get_db()
        if db is None:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="task_history",
                    entity_id=hist_id,
                    operation=operation,
                    error="MongoDB database connection unavailable",
                )
            )

        try:
            if operation == DualWriteOperation.DELETE:
                db["task_history"].delete_one({"_id": hist_id})
            else:
                doc = EntityTransformer.transform_task_history(history)
                payload = doc.to_mongo()
                db["task_history"].replace_one({"_id": hist_id}, payload, upsert=True)
            return self._record_result(
                DualWriteResult(success=True, entity="task_history", entity_id=hist_id, operation=operation)
            )
        except Exception as e:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="task_history",
                    entity_id=hist_id,
                    operation=operation,
                    error=str(e),
                )
            )

    def sync_notification(self, notification: Any, operation: DualWriteOperation) -> DualWriteResult:
        """Sync Notification to MongoDB."""
        if not is_dual_write_enabled():
            return DualWriteResult(
                success=True,
                entity="notifications",
                entity_id=str(getattr(notification, "id", "")),
                operation=operation,
            )

        nid = str(getattr(notification, "id", ""))
        db = self._get_db()
        if db is None:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="notifications",
                    entity_id=nid,
                    operation=operation,
                    error="MongoDB database connection unavailable",
                )
            )

        try:
            if operation == DualWriteOperation.DELETE:
                db["notifications"].delete_one({"_id": nid})
            else:
                doc = EntityTransformer.transform_notification(notification)
                payload = doc.to_mongo()
                db["notifications"].replace_one({"_id": nid}, payload, upsert=True)
            return self._record_result(
                DualWriteResult(success=True, entity="notifications", entity_id=nid, operation=operation)
            )
        except Exception as e:
            return self._record_result(
                DualWriteResult(
                    success=False,
                    entity="notifications",
                    entity_id=nid,
                    operation=operation,
                    error=str(e),
                )
            )


# Default global dual-writer instance
dual_writer = DualWriter()
