# Phase 28 — MongoDB Infrastructure & Connection Scaffolding

**Project:** NextAction Production Deployment  
**Version:** 1.0.0 (Build 1)  
**Database Architecture:** Dual-Engine Persistence Framework (PostgreSQL Primary + MongoDB Scaffolding)  
**Status:** Implemented, Tested, and Verified (Zero Regressions on PostgreSQL).

---

## 1. Executive Summary

Phase 28 establishes the foundational infrastructure and connection layer for MongoDB without modifying, disrupting, or weakening the verified PostgreSQL/SQLAlchemy implementation.

The system now operates under a **Dual-Engine Architecture**:
- **Current Stable Engine:** PostgreSQL 16 + SQLAlchemy ORM + Alembic (Active and primary).
- **New Scaffolding Engine:** MongoDB + PyMongo 4.18.2 (Optional, toggled via `MONGODB_ENABLED=true/false`).

When `MONGODB_ENABLED=false` (the default), the application boots and operates in 100% pure PostgreSQL mode with zero overhead and zero network requests to MongoDB. When `MONGODB_ENABLED=true`, the application securely pools connections to MongoDB, verifies cluster reachability, manages multi-document sessions/transactions, and extends readiness probes to include MongoDB.

---

## 2. Selected Driver & Version

| Component | Selected Technology | Version | Rationale |
|---|---|---|---|
| **Driver** | **`pymongo`** | `4.18.2` (with `dnspython 2.8.0` for `mongodb+srv://` resolution) | Official MongoDB Python driver. Battle-tested, supports thread-safe connection pooling, replica sets, transactions, and native timezone-aware UTC datetime conversions. Aligns directly with FastAPI's AnyIO threadpool model for synchronous domain services. |

Dependency entry added to [`backend/requirements.txt`](file:///c:/bhanu/NEXT%20ACTION/backend/requirements.txt):
```ini
pymongo>=4.8.0
```

---

## 3. Configuration & Security Redaction

MongoDB settings have been integrated into [`backend/app/core/config.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/core/config.py) using Pydantic Settings:

| Environment Variable | Default Value | Purpose |
|---|---|---|
| `MONGODB_ENABLED` | `false` | Master toggle. Ensures PostgreSQL remains undisturbed by default. |
| `MONGODB_URI` | `None` | Cluster connection string (e.g. `mongodb+srv://user:pass@cluster.mongodb.net/nextaction`). |
| `MONGODB_DATABASE` | `nextaction` | Target database name. |
| `MONGODB_MIN_POOL_SIZE` | `1` | Minimum pre-warmed connection pool size. |
| `MONGODB_MAX_POOL_SIZE` | `50` | Maximum concurrent connections per backend worker. |
| `MONGODB_SERVER_SELECTION_TIMEOUT_MS` | `5000` | Maximum wait time for cluster heartbeat selection (5 seconds). |
| `MONGODB_CONNECT_TIMEOUT_MS` | `5000` | Network socket connection timeout (5 seconds). |

### Security & Credential Redaction
A dedicated sanitization helper, `redact_mongo_uri(uri)`, ensures that passwords in standard (`mongodb://`) or DNS seedlist (`mongodb+srv://`) URIs are never exposed in log outputs, terminal traces, or exception messages:
```python
def redact_mongo_uri(uri: Optional[str]) -> str:
    """Return a sanitized version of the MongoDB URI with passwords redacted."""
    if not uri:
        return ""
    import re
    return re.sub(r"://([^:@]+):([^@]+)@", r"://\1:***@", uri)
```

In addition, `validate_production_security()` enforces that if `MONGODB_ENABLED=true` in production, `MONGODB_URI` must be explicitly provided.

---

## 4. Connection Lifecycle & Lifespan Architecture

The MongoDB connection manager is encapsulated in [`backend/app/db/mongodb.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/db/mongodb.py):

- **Singleton Client**: Cached in `_mongo_client` with lazy accessors `get_mongo_client()` and `get_mongo_database()`.
- **FastAPI Lifespan Integration** ([`backend/app/main.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/main.py)):
  ```python
  @asynccontextmanager
  async def lifespan(app: FastAPI):
      # Startup phase
      setup_logging(settings.LOG_LEVEL)
      settings.validate_production_security()
      if settings.MONGODB_ENABLED:
          logger.info("Initializing MongoDB connection pool...")
          init_mongo_client()

      yield

      # Shutdown phase
      if settings.MONGODB_ENABLED:
          close_mongo_client()
      engine.dispose()
  ```
- **Fail-Fast Semantics**: If `MONGODB_ENABLED=true` and the cluster is unreachable, `init_mongo_client()` raises `ConnectionFailure` during startup, halting the service cleanly with a redacted error message rather than silently continuing in a broken state.

---

## 5. Health & Readiness Probe Architecture

The operational readiness probe (`GET /ready`) in [`backend/app/main.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/main.py) safely adapts to the dual-engine state:

1. **When `MONGODB_ENABLED=false` (Current Production Default):**
   - Probes PostgreSQL via `SELECT 1`.
   - Returns HTTP 200:
     ```json
     {
       "status": "ready",
       "database": "connected"
     }
     ```
   - 100% backward-compatible with Phase 21–25 tests and monitoring systems.
2. **When `MONGODB_ENABLED=true`:**
   - Probes PostgreSQL via `SELECT 1`.
   - Probes MongoDB via `client.admin.command('ping')`.
   - Returns HTTP 200 when both are healthy:
     ```json
     {
       "status": "ready",
       "database": "connected",
       "mongodb": "connected"
     }
     ```
   - Returns HTTP 503 if either database is unreachable.

---

## 6. Transaction & Session Capability

MongoDB Atlas M0 Free Tier operates as a **3-node replica set**, which natively supports multi-document ACID transactions.

The connection module provides a clean context manager interface:
```python
@contextmanager
def get_mongo_session(client: Optional[MongoClient] = None) -> Generator[ClientSession, None, None]:
    active_client = client or get_mongo_client()
    if active_client is None:
        raise RuntimeError("MongoDB client is not initialized or MONGODB_ENABLED is False.")
    session = active_client.start_session()
    try:
        yield session
    finally:
        session.end_session()
```

*Note on Local Standalone Containers:* In standalone (single-node non-replica-set) MongoDB installations, attempting `session.start_transaction()` raises a `ConfigurationError: Transaction numbers are only allowed on a replica set member or mongos`. Multi-document transactions will be exercised against replica sets in cloud deployment and replica-set local test environments.

---

## 7. Index Initialization Framework

The function `init_mongo_indexes(db: Database)` in [`backend/app/db/mongodb.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/db/mongodb.py) establishes an idempotent index registration pipeline:
- Executed automatically during `init_mongo_client()`.
- Idempotent: `db[collection].create_index()` checks existing indexes and creates only missing ones.
- For Phase 28, registers infrastructure verification index:
  ```python
  db["_infra_health"].create_index([("created_at", -1)], name="idx_infra_health_created_at")
  ```
- Will be expanded in Phase 29 to register indexes for domain collections (`users`, `tasks`, `notifications`, etc.).

---

## 8. Repository Foundation

The base repository class in [`backend/app/repositories/mongodb_base.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/repositories/mongodb_base.py) establishes reusable primitives for all future collections:

- **Collection Access**: `self.collection` accesses the underlying PyMongo `Collection`.
- **Identifier Strategy**:
  - `to_uuid_str(val)`: Converts incoming `uuid.UUID` or string values to lowercase hyphenated UUID strings (`str(uuid.UUID(...))`).
  - `format_document(doc)`: Automatically exposes `id = str(doc["_id"])` alongside `_id` so that API responses remain 100% compatible with existing Pydantic models expecting `id: uuid.UUID | str`.
- **Timestamp Strategy**:
  - `ensure_utc(dt)`: Forces naive datetimes to `timezone.utc` and normalizes existing timestamps.
  - All PyMongo connections are initialized with `tz_aware=True`, ensuring all dates returned from MongoDB are timezone-aware UTC datetimes.
- **Pagination Helper**:
  - `paginate_find(filter_query, sort_by, sort_order, page, page_size)`: Executes count and cursor pagination (`skip()` / `limit()`) returning `(items, total)`.

---

## 9. Local Verification Results

1. **Local Test Container Verification**:
   - Started a temporary local MongoDB 7 container (`mongo:7` on port 27017).
   - Executed live verification script:
     - MongoClient initialization: **PASSED**
     - Ping readiness check: **PASSED**
     - Document insertion via `BaseMongoRepository`: **PASSED**
     - Paginated retrieval & sorting: **PASSED**
     - Client session generation: **PASSED**
     - Clean shutdown: **PASSED**
   - Stopped and removed the temporary container (`docker stop nextaction_test_mongo`).
2. **Automated Unit & Integration Test Suite** ([`backend/tests/test_mongodb_infrastructure.py`](file:///c:/bhanu/NEXT%20ACTION/backend/tests/test_mongodb_infrastructure.py)):
   - 12/12 dedicated tests passed covering disabled defaults, health probes, URI redaction, production security validation, connection failures, readiness responses, repository helpers, and session lifecycle.

---

## 10. Phase 29 Handoff & Boundary Declaration

Phase 28 is strictly limited to connection and infrastructure scaffolding.

### Completed in Phase 28:
- [x] PyMongo 4.18.2 driver installed and registered in `requirements.txt`.
- [x] MongoDB configuration parameters and URI redaction helper added to `Settings`.
- [x] Dedicated connection manager [`backend/app/db/mongodb.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/db/mongodb.py) created.
- [x] FastAPI lifespan startup and shutdown hooks integrated in [`backend/app/main.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/main.py).
- [x] Dual-engine readiness probe (`/ready`) implemented with 100% backward compatibility.
- [x] Base repository class [`backend/app/repositories/mongodb_base.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/repositories/mongodb_base.py) created.
- [x] Safe placeholders added to [`.env.example`](file:///c:/bhanu/NEXT%20ACTION/.env.example).
- [x] 12 new infrastructure tests created and passing.
- [x] Full existing PostgreSQL test suite remains passing.

### Strictly Deferred to Phase 29:
- Entity-specific repository classes (`UserRepository`, `TaskRepository`, `ClientRepository`, `WorkflowRepository`, `NotificationRepository`).
- Domain Pydantic BSON schemas.
- Dual-engine service layer migration.
- Task attempt business logic migration.
