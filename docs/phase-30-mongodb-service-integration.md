# Phase 30 — MongoDB Service-Layer Integration & Dual-Engine Dispatch Report

## 1. Executive Summary & Architectural Scope

Phase 30 successfully establishes the **dual-engine persistence boundary** across the NextAction service layer. The application now supports dynamic dispatch between **PostgreSQL (default, stable)** and **MongoDB (opt-in, internal)** persistence engines without modifying external API contracts, Pydantic schemas, or any line of Flutter client code.

```
+-------------------------------------------------------------+
|               NextAction Frontend (Flutter)                 |
|       (100% Unmodified, 500/500 Tests Green, 0 Issues)      |
+-------------------------------------------------------------+
                              | HTTP / JSON REST
                              v
+-------------------------------------------------------------+
|              FastAPI Application & Route Layer              |
|   (Unchanged API contracts, schemas, validation & errors)   |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|                Domain Public Service Layer                  |
|     (task_service, user_service, client_service, etc.)      |
+-------------------------------------------------------------+
                              |
               get_persistence_gateway()
                              v
     +------------------------------------------------+
     |       Persistence Gateway & Context Router     |
     |   - Controlled by PERSISTENCE_ENGINE config   |
     |   - Dynamic override for scoped test runs      |
     +------------------------------------------------+
             /                                \
   (PERSISTENCE_ENGINE=postgresql)     (PERSISTENCE_ENGINE=mongodb)
            /                                    \
           v                                      v
+---------------------------+        +---------------------------+
| PostgreSQL Service Layer  |        |  MongoDB Service Layer    |
| (SQLAlchemy 2.0 ORM)      |        |  (PyMongo Repositories)   |
| 100% Preserved & Default  |        |  Single-Doc Atomicity     |
+---------------------------+        +---------------------------+
           |                                      |
           v                                      v
+---------------------------+        +---------------------------+
| PostgreSQL 16 (Primary)   |        |  MongoDB 7 / Atlas M0     |
| Port 5432 (nextaction)    |        |  Port 27017 (nextaction)  |
+---------------------------+        +---------------------------+
```

> [!IMPORTANT]
> **PostgreSQL remains the default and stable primary engine.**
> Setting `PERSISTENCE_ENGINE=postgresql` (the default) routes all application traffic through the proven SQLAlchemy ORM implementation.
> MongoDB is available as an opt-in persistence engine via `PERSISTENCE_ENGINE=mongodb`, validated across all migrated core domain services.

---

## 2. Engine Selection & Configuration Design

### 2.1 Configuration Variables (`backend/app/core/config.py`)

A centralized configuration parameter governs persistence selection:

- `PERSISTENCE_ENGINE`: Literal string enum `postgresql` (default) or `mongodb`.
- Configuration validation ensures:
  1. Only valid engine strings (`postgresql`, `mongodb`) are accepted.
  2. When `PERSISTENCE_ENGINE=mongodb`, the application verifies that `MONGODB_ENABLED=True` and `MONGODB_URI` is populated; if not, startup fails fast with an explicit descriptive error.
  3. Under default `postgresql`, MongoDB is completely optional and non-blocking.

### 2.2 Dynamic Scoping & Test Overrides (`backend/app/persistence/context.py`)

To allow unit, integration, and repository tests to execute against specific persistence backends without altering system environment variables, a context manager is provided:

```python
with override_engine("mongodb"):
    # Code executed within this block routes via Mongo adapters
    service = get_persistence_gateway().tasks
```

The active engine is evaluated in priority order:
1. Thread-local context override (`override_engine()`)
2. Configuration setting (`settings.PERSISTENCE_ENGINE`)
3. Static default (`EngineType.POSTGRESQL`)

---

## 3. Persistence Abstraction & Service Adapters

To decouple business orchestration from underlying storage engines, formal `Protocol` interfaces define the required persistence capabilities in `backend/app/persistence/interfaces.py`:

| Interface Protocol | PostgreSQL Adapter (`app/persistence/postgres/`) | MongoDB Adapter (`app/persistence/mongodb/`) | Responsibilities |
| :--- | :--- | :--- | :--- |
| `TaskPersistenceService` | `PostgresTaskService` | `MongoTaskService` | CRUD, transitions, attempts, overrides, postponements |
| `UserPersistenceService` | `PostgresUserService` | `MongoUserService` | User lookup, authentication retrieval, listing, profile updates |
| `ClientPersistenceService` | `PostgresClientService` | `MongoClientService` | Client directory, unique naming, lifecycle management |
| `WorkflowPersistenceService`| `PostgresWorkflowService`| `MongoWorkflowService` | Workflow definitions, stage transitions, ordering |
| `SettingsPersistenceService`| `PostgresSettingsService`| `MongoSettingsService` | User preferences, timezone, theme, notification channels |
| `NotificationPersistenceService`| `PostgresNotificationService`| `MongoNotificationService` | Alerts, unread tracking, batch dismissal, deduplication |
| `ReminderPersistenceService`| `PostgresReminderService`| `MongoReminderService` | Due date reminders, embedded task subdocument management |
| `FollowUpPersistenceService`| `PostgresFollowUpService`| `MongoFollowUpService` | Follow-up action items, embedded subdocument management |
| `HistoryPersistenceService` | `PostgresHistoryService` | `MongoHistoryService` | Audit trail, state change history, timeline queries |

### 3.1 Persistence Gateway (`backend/app/persistence/gateway.py`)

The `PersistenceGateway` acts as the single point of resolution for persistence adapters, eliminating scattered conditional branching across the codebase:

```python
gateway = get_persistence_gateway(db=db)
task_adapter = gateway.tasks
user_adapter = gateway.users
```

When operating under `postgresql`, the gateway receives and binds the active SQLAlchemy `Session`. Under `mongodb`, the gateway instantiates MongoDB repository adapters communicating via PyMongo.

---

## 4. Single-Document Atomicity vs. Multi-Document Transactions

To ensure complete compatibility with standalone local MongoDB development instances and MongoDB Atlas M0 free-tier clusters (which may run as standalone nodes or without multi-document replica set transaction support), all MongoDB adapters are engineered around **single-document atomicity**:

1. **Attempt Counting & State Updates**:
   Task attempt increments, status transitions, and timestamp updates are combined into a single atomic `$set` and `$inc` pipeline within `TaskRepository.update()`.
2. **Embedded Subdocument Manipulation**:
   - Creating a reminder uses `$push` to append to the task's `reminders` array.
   - Deleting a reminder uses `$pull` matching `{ reminders: { id: reminder_id } }`.
   - Completing a follow-up uses array filter updates `$[elem]` to atomically toggle `is_completed=True` and `completed_at=utcnow()`.
3. **Notification Deduplication**:
   Idempotency queries check for existing pending alerts before issuing single-document insertions.
4. **User Settings Upserts**:
   Upsert operations pop immutable identifier fields (`_id`, `created_at`) from the `$set` payload, avoiding MongoDB `ConflictingUpdateOperators` errors while atomically initializing missing settings via `$setOnInsert`.
5. **Token Revocation**:
   Single-document hash updates atomically mark refresh tokens as revoked with timestamp audits.

---

## 5. Domain Service Integration & Parity

All 10 public service facades in `backend/app/services/` dispatch to the active engine via `PersistenceGateway`:

1. **`task_service.py`**:
   Dispatches `get_task`, `list_tasks`, `create_task`, `update_task`, `record_task_attempt`, `record_task_override_attempt`, `postpone_task`, `complete_task`, `reopen_task`, and `delete_task`. Records audit history in both engines.
2. **`user_service.py`**:
   Dispatches user creation, password verification, profile lookup, and directory search.
3. **`client_service.py`**:
   Dispatches client management and unique constraint validation.
4. **`workflow_service.py`**:
   Dispatches workflow schemas, stage definitions, and ordering.
5. **`settings_service.py`**:
   Dispatches user configuration, default settings creation, and preference updates.
6. **`notification_service.py`**:
   Dispatches notification retrieval, read state toggles, and alert dismissals.
7. **`reminder_service.py`**:
   Dispatches reminder creation and deletion against embedded task subdocuments.
8. **`follow_up_service.py`**:
   Dispatches follow-up creation and completion toggles.
9. **`history_service.py`**:
   Dispatches audit logging and task activity timeline retrieval.
10. **`auth_service.py`**:
    Dispatches user identity retrieval, registration, and refresh token validation across persistence boundaries.

### 5.1 Intentionally Deferred Services

The following operational services are intentionally deferred to Phase 31/32:
- **`reporting_service.py`**: Cross-collection aggregate reporting across tasks, clients, and workflows currently leverages relational SQL `GROUP BY` queries. MongoDB aggregation pipelines will be introduced during data migration validation.
- **`scheduler_service.py`**: Background cron scheduler and notification generation engine.
- **`template_service.py` & `recurring_service.py`**: Blueprint cloning and recurrence engines.

These services continue to operate seamlessly against PostgreSQL without disruption.

---

## 6. Zero API & Flutter Impact

- **API Contracts**: 100% unchanged. Pydantic request/response schemas in `backend/app/schemas/` were not modified.
- **Error Formats**: HTTP status codes (400, 401, 403, 404, 409, 422, 500) and error detail payloads match previous behavior exactly.
- **Flutter Frontend**: Zero files modified in `apps/mobile_web`.

---

## 7. Comprehensive Verification & Test Results

### 7.1 Backend Pytest Suite
- **MongoDB Service Integration Suite**: `pytest tests/test_mongodb_services.py` $\to$ **17 / 17 PASSED** (100%)
- **MongoDB Repository Suite**: `pytest tests/test_mongodb_repositories.py` $\to$ **16 / 16 PASSED** (100%)
- **MongoDB Infrastructure Suite**: `pytest tests/test_mongodb_infrastructure.py` $\to$ **12 / 12 PASSED** (100%)
- **Full Backend Suite**: `pytest tests/` $\to$ **245 / 245 PASSED** (100%, 67.62s)
  - All original 228 tests passing
  - All 17 new Phase 30 dual-engine service tests passing

### 7.2 Flutter Analysis & Test Suite
- **Static Analysis**: `flutter analyze` $\to$ **0 issues found** (1.3s)
- **Full Flutter Test Suite**: `flutter test -j 1` $\to$ **500 / 500 PASSED** (100%, 1m 21s)
  - Unit tests: 22 files passed
  - Widget tests: 1 file passed
  - Live Integration E2E suites: 25 files passed against live backend

### 7.3 Infrastructure & Probe Verification
- **`/health`**: Returns HTTP 200 `{"status": "healthy", "database": "connected"}`
- **`/ready`**: Returns HTTP 200 `{"status": "ready", "database": "connected"}`
- **PostgreSQL 16**: Port 5432, container `nextaction_postgres` healthy and active.
- **MongoDB 7**: Port 27017, container `nextaction_mongo_test` healthy and active.

---

## 8. Commitments & Boundary Guarantees

1. **PostgreSQL Default**: PostgreSQL remains the default engine (`PERSISTENCE_ENGINE=postgresql`).
2. **No Data Loss**: PostgreSQL schema, Alembic migrations, and relational data remain intact.
3. **Zero Cloud Resources Created**: No MongoDB Atlas, Render, Cloudflare, or AWS resources were created.
4. **No Production Migration**: Production data was not migrated.
5. **Phase 31 Boundary**: Phase 31 (Dual-Write & Live Data Migration) has NOT been started.
