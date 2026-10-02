"""MongoDB connection, pooling, health checks, and lifecycle management.

Provides dual-engine capability alongside existing PostgreSQL persistence.
Active only when MONGODB_ENABLED=True.
"""

from contextlib import contextmanager
import logging
from typing import Generator, Optional
from pymongo import ASCENDING, DESCENDING, IndexModel, MongoClient
from pymongo.database import Database
from pymongo.client_session import ClientSession
from pymongo.errors import ConnectionFailure, PyMongoError

from app.core.config import redact_mongo_uri, settings

logger = logging.getLogger("nextaction.mongodb")

_mongo_client: Optional[MongoClient] = None


def get_mongo_client() -> Optional[MongoClient]:
    """Retrieve the singleton MongoClient instance, or None if uninitialized or disabled."""
    return _mongo_client


def get_mongo_database(db_name: Optional[str] = None) -> Optional[Database]:
    """Retrieve the target MongoDB database instance, or None if client is uninitialized."""
    client = get_mongo_client()
    if client is None:
        return None
    name = db_name or settings.MONGODB_DATABASE
    return client[name]


def get_mongodb_database(db_name: Optional[str] = None) -> Database:
    """Retrieve or initialize the target MongoDB database instance with fallback."""
    db = get_mongo_database(db_name)
    if db is not None:
        return db
    client = init_mongo_client()
    if client is not None:
        return client[db_name or settings.MONGODB_DATABASE]
    fallback_client = MongoClient(
        getattr(settings, "MONGODB_URI", None) or "mongodb://localhost:27017",
        serverSelectionTimeoutMS=2000,
        tz_aware=True,
    )
    return fallback_client[db_name or settings.MONGODB_DATABASE]


def init_mongo_client() -> Optional[MongoClient]:
    """Initialize MongoClient connection pool, verify connectivity, and run index scaffolding.

    If MONGODB_ENABLED is False, no connection is established and None is returned.
    If MONGODB_ENABLED is True and connection fails, raises ConnectionFailure without exposing credentials.
    """
    global _mongo_client

    if not settings.MONGODB_ENABLED:
        logger.info("MongoDB is disabled (MONGODB_ENABLED=false). Running in PostgreSQL-only mode.")
        return None

    if not settings.MONGODB_URI or not settings.MONGODB_URI.strip():
        raise ValueError("MONGODB_ENABLED is True, but MONGODB_URI is empty or not configured.")

    sanitized_uri = redact_mongo_uri(settings.MONGODB_URI)
    logger.info(f"Connecting to MongoDB at {sanitized_uri} [database={settings.MONGODB_DATABASE}]...")

    try:
        client = MongoClient(
            settings.MONGODB_URI,
            minPoolSize=settings.MONGODB_MIN_POOL_SIZE,
            maxPoolSize=settings.MONGODB_MAX_POOL_SIZE,
            serverSelectionTimeoutMS=settings.MONGODB_SERVER_SELECTION_TIMEOUT_MS,
            connectTimeoutMS=settings.MONGODB_CONNECT_TIMEOUT_MS,
            tz_aware=True,
        )
        # Verify cluster reachability with an administrative ping
        client.admin.command("ping")
        logger.info(f"MongoDB ping succeeded on cluster [{sanitized_uri}].")

        _mongo_client = client

        # Initialize base infrastructure indexes
        db = client[settings.MONGODB_DATABASE]
        init_mongo_indexes(db)

        return _mongo_client
    except Exception as exc:
        logger.error(f"Failed to connect to MongoDB cluster at {sanitized_uri}: {exc.__class__.__name__}")
        _mongo_client = None
        raise ConnectionFailure(
            f"Could not establish connection to MongoDB at {sanitized_uri}. Check cluster availability and credentials."
        ) from None


def close_mongo_client() -> None:
    """Close the MongoClient connection pool and cleanly dispose of active resources."""
    global _mongo_client
    if _mongo_client is not None:
        try:
            logger.info("Closing MongoDB connection pool...")
            _mongo_client.close()
            logger.info("MongoDB connection pool cleanly closed.")
        except Exception as exc:
            logger.warning(f"Error while closing MongoDB client: {exc}")
        finally:
            _mongo_client = None


def check_mongo_ready() -> bool:
    """Perform a live ping readiness probe against the configured MongoDB database.

    Returns True if MongoDB is disabled or reachable, False if enabled and unreachable.
    """
    if not settings.MONGODB_ENABLED:
        return True

    client = get_mongo_client()
    if client is None:
        return False

    try:
        client.admin.command("ping")
        return True
    except Exception as exc:
        logger.warning(f"MongoDB readiness check failed: {exc.__class__.__name__}")
        return False


def init_mongo_indexes(db: Database) -> None:
    """Idempotently initialize required indexes across MongoDB collections.

    Ensures uniqueness constraints, query performance, and sorting support
    mirroring the relational integrity of PostgreSQL models.
    """
    try:
        # Minimal infrastructure validation collection
        db["_infra_health"].create_index(
            [("created_at", DESCENDING)],
            name="idx_infra_health_created_at",
        )

        # Users
        db["users"].create_indexes([
            IndexModel([("email", ASCENDING)], unique=True, name="idx_users_email_unique"),
            IndexModel([("google_id", ASCENDING)], name="idx_users_google_id", sparse=True),
            IndexModel([("is_active", ASCENDING)], name="idx_users_is_active"),
            IndexModel([("created_at", DESCENDING)], name="idx_users_created_at"),
        ])

        # User Settings
        db["user_settings"].create_indexes([
            IndexModel([("user_id", ASCENDING)], unique=True, name="idx_user_settings_user_id_unique"),
        ])

        # Clients
        db["clients"].create_indexes([
            IndexModel([("name", ASCENDING)], name="idx_clients_name"),
            IndexModel([("is_active", ASCENDING)], name="idx_clients_is_active"),
            IndexModel([("created_at", DESCENDING)], name="idx_clients_created_at"),
        ])

        # Workflows
        db["workflows"].create_indexes([
            IndexModel([("name", ASCENDING)], name="idx_workflows_name"),
            IndexModel([("is_active", ASCENDING)], name="idx_workflows_is_active"),
            IndexModel([("created_at", DESCENDING)], name="idx_workflows_created_at"),
        ])

        # Tasks
        db["tasks"].create_indexes([
            IndexModel([("status", ASCENDING)], name="idx_tasks_status"),
            IndexModel([("priority", ASCENDING)], name="idx_tasks_priority"),
            IndexModel([("assigned_user_id", ASCENDING)], name="idx_tasks_assigned_user_id"),
            IndexModel([("client_id", ASCENDING)], name="idx_tasks_client_id"),
            IndexModel([("workflow_id", ASCENDING)], name="idx_tasks_workflow_id"),
            IndexModel([("due_date", ASCENDING)], name="idx_tasks_due_date"),
            IndexModel([("next_action_date", ASCENDING)], name="idx_tasks_next_action_date"),
            IndexModel([("created_at", DESCENDING)], name="idx_tasks_created_at"),
            IndexModel([("updated_at", DESCENDING)], name="idx_tasks_updated_at"),
            # Compound query indexes matching frequent dashboard & filter patterns
            IndexModel([("assigned_user_id", ASCENDING), ("status", ASCENDING)], name="idx_tasks_user_status"),
            IndexModel([("client_id", ASCENDING), ("status", ASCENDING)], name="idx_tasks_client_status"),
            IndexModel([("workflow_id", ASCENDING), ("status", ASCENDING)], name="idx_tasks_workflow_status"),
            IndexModel([("status", ASCENDING), ("next_action_date", ASCENDING)], name="idx_tasks_status_next_action"),
        ])

        # Task History (audit log)
        db["task_history"].create_indexes([
            IndexModel([("task_id", ASCENDING), ("created_at", DESCENDING)], name="idx_task_history_task_created"),
            IndexModel([("created_at", DESCENDING)], name="idx_task_history_created_at"),
        ])

        # Notifications
        db["notifications"].create_indexes([
            IndexModel([("user_id", ASCENDING), ("created_at", DESCENDING)], name="idx_notifications_user_created"),
            IndexModel([("user_id", ASCENDING), ("is_read", ASCENDING), ("created_at", DESCENDING)], name="idx_notifications_user_read_created"),
            # Deduplication unique partial index: user_id + dedup_key when dedup_key is a non-null string
            IndexModel(
                [("user_id", ASCENDING), ("dedup_key", ASCENDING)],
                unique=True,
                partialFilterExpression={"dedup_key": {"$type": "string"}},
                name="idx_notifications_user_dedup_unique",
            ),
        ])

        # Refresh Tokens
        db["refresh_tokens"].create_indexes([
            IndexModel([("token_hash", ASCENDING)], unique=True, name="idx_refresh_tokens_hash_unique"),
            IndexModel([("user_id", ASCENDING), ("is_revoked", ASCENDING)], name="idx_refresh_tokens_user_revoked"),
            IndexModel([("expires_at", ASCENDING)], name="idx_refresh_tokens_expires_at"),
        ])

        # Task Templates
        db["task_templates"].create_indexes([
            IndexModel([("name", ASCENDING)], name="idx_task_templates_name"),
            IndexModel([("workflow_id", ASCENDING)], name="idx_task_templates_workflow_id"),
            IndexModel([("is_active", ASCENDING)], name="idx_task_templates_is_active"),
        ])

        # Recurring Tasks
        db["recurring_tasks"].create_indexes([
            IndexModel([("is_active", ASCENDING), ("next_run_at", ASCENDING)], name="idx_recurring_tasks_active_next_run"),
            IndexModel([("created_at", DESCENDING)], name="idx_recurring_tasks_created_at"),
        ])

        # Recurring Task Executions (idempotency enforcement)
        db["recurring_task_executions"].create_indexes([
            IndexModel(
                [("recurring_task_id", ASCENDING), ("scheduled_for", ASCENDING)],
                unique=True,
                name="idx_recurring_exec_task_sched_unique",
            ),
            IndexModel([("recurring_task_id", ASCENDING), ("executed_at", DESCENDING)], name="idx_recurring_exec_task_executed"),
        ])

        # Events
        db["events"].create_indexes([
            IndexModel([("start_at", ASCENDING)], name="idx_events_start_at"),
            IndexModel([("task_id", ASCENDING)], name="idx_events_task_id"),
            IndexModel([("client_id", ASCENDING)], name="idx_events_client_id"),
        ])

        logger.info("MongoDB domain collections and infrastructure indexes initialized successfully.")
    except Exception as exc:
        logger.error(f"Failed to initialize MongoDB indexes: {exc.__class__.__name__}: {exc}")
        raise


@contextmanager
def get_mongo_session(client: Optional[MongoClient] = None) -> Generator[ClientSession, None, None]:
    """Context manager providing a MongoDB ClientSession for multi-document operations and transactions."""
    active_client = client or get_mongo_client()
    if active_client is None:
        raise RuntimeError("MongoDB client is not initialized or MONGODB_ENABLED is False.")

    session = active_client.start_session()
    try:
        yield session
    finally:
        session.end_session()
