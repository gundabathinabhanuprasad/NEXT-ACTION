# Phase 31: Dual-Write & Controlled PostgreSQL → MongoDB Data Migration Report

## 1. Overview & Architecture

Phase 31 implements a controlled, local-only, reversible data migration system and dual-write mechanism that synchronizes PostgreSQL data to MongoDB without altering existing PostgreSQL transactions, API contracts, or Flutter applications.

- **Source Database**: PostgreSQL (Port 5432, engine `postgresql`)
- **Destination Database**: MongoDB (Port 27017, engine `mongodb`)
- **Cost**: ₹0/month. Completely local, zero cloud resources (no AWS, no Render, no Cloudflare, no Atlas).
- **Default Persistence Engine**: `postgresql`. PostgreSQL remains the single source of truth.
- **Invocation**: Explicit only via CLI or API coordinator. Never executed automatically during application startup or request processing.

```
                          +------------------------+
                          |   PostgreSQL Database  |
                          |  (Source of Truth)     |
                          +-----------+------------+
                                      |
                         [PostgreSQLExtractor]
                                      |
                         [EntityTransformer]
                                      |
                         [MigrationValidator] (Ref Integrity)
                                      |
                           [MongoDBLoader] (Upsert)
                                      |
                                      v
                          +------------------------+
                          |    MongoDB Database    |
                          |  (Document Collections)|
                          +-----------+------------+
                                      |
                         [MigrationVerifier] (Counts & SHA-256 Checksums)
                                      |
                         [MigrationReporter] (docs/migration-reports/)
```

---

## 2. Collection Mapping & Dependency-Safe Loading Order

The migration proceeds strictly in dependency order to ensure parent references are loaded prior to children:

1. `users`
2. `user_settings`
3. `clients`
4. `workflows`
5. `task_templates`
6. `recurring_tasks`
7. `tasks` (Embeds reminders and follow-ups)
8. `task_history`
9. `recurring_task_executions`
10. `notifications`
11. `events`
12. `refresh_tokens`

---

## 3. Transformation Rules & Embedded Modeling

### Exact ID Preservation
- PostgreSQL UUID values (`UUID(as_uuid=True)`) are preserved **identically** as string `_id` values in MongoDB.
- Zero ID regeneration occurs.
  ```json
  // PostgreSQL: id = 123e4567-e89b-12d3-a456-426614174000
  // MongoDB:    _id = "123e4567-e89b-12d3-a456-426614174000"
  ```

### Timestamp Preservation
- Timestamps are normalized to timezone-aware UTC ISO formats.
- Millisecond precision aligns with BSON `ISODate` representations.

### Tasks Embedding & Denormalization
PostgreSQL relational tables `reminders` and `follow_ups` are embedded directly into `tasks` documents:
- `reminders`: Array of `ReminderSubDocument` (with preserved `_id`, `remind_at`, `is_sent`, `sent_at`, `notes`, `created_at`).
- `follow_ups`: Array of `FollowUpSubDocument` (with preserved `_id`, `follow_up_date`, `notes`, `is_completed`, `completed_at`, `created_at`).
- Summary denormalizations are populated: `client_name`, `workflow_name`, `assigned_user_name`, `assigned_user_email`.

---

## 4. Referential Integrity Validation

Before writing any records to MongoDB, `MigrationValidator` validates:
- `task.client_id` references existing client.
- `task.workflow_id` references existing workflow.
- `task.assigned_user_id` references existing user.
- `task_history.task_id` references existing task.
- `notification.user_id` references existing user.
- `refresh_token.user_id` references existing user.
- `recurring_task_execution.recurring_task_id` references existing recurring task.

If any broken reference is detected, the migration safely halts without writing.

---

## 5. Upsert & Idempotency

- `MongoDBLoader` executes PyMongo `bulk_write` with `ReplaceOne({"_id": doc_id}, payload, upsert=True)`.
- Re-running migration produces 0 duplicates across tasks, embedded reminders, follow-ups, notifications, and history.

---

## 6. Checksum Verification

- Canonical JSON representations are fingerprinted via SHA-256 (`compute_fingerprint`).
- Compares PostgreSQL extracted records against MongoDB stored records.
- Flags mismatches immediately if any business data diverges.

---

## 7. Dual-Write Architecture

Controlled via configuration flag:
- `MONGODB_DUAL_WRITE_ENABLED=false` (Default: Disabled)
- In `.env.example` and `app.core.config.Settings`.

When enabled:
1. Writes to PostgreSQL first within the standard session/transaction.
2. Synchronizes the corresponding document to MongoDB via `DualWriter`.
3. If MongoDB write fails, the error is captured and logged into `DualWriteResult` without aborting PostgreSQL transaction (eventual consistency).

Core entities supported:
- `users`
- `clients`
- `workflows`
- `tasks`
- `task_history`
- `notifications`

---

## 8. Rollback Mechanism

- Every migrated MongoDB document is tagged with `_migration_id`.
- `MigrationRollback` removes only documents tagged with that `_migration_id`.
- PostgreSQL data is never modified, deleted, or rolled back.

---

## 9. CLI Usage

```powershell
# Dry run (simulation, zero writes)
python -m app.migration.cli --mode dry-run

# Controlled live migration (deterministic upsert)
python -m app.migration.cli --mode migrate --confirm

# Verification (counts, distributions, SHA-256 checksums)
python -m app.migration.cli --mode verify

# Rollback (reverts only tagged MongoDB documents)
python -m app.migration.cli --mode rollback --migration-id <id> --confirm
```

---

## 10. Verification Results Summary

- Backend pytest: 260/260 passed (245 base + 15 migration tests).
- All 15 migration scenarios verified:
  1. Dry-run execution (simulation - zero writes)
  2. Entity transformations accuracy
  3. Exact ID and UTC timestamp preservation
  4. Referential integrity validation
  5. Safe abort on broken references
  6. Controlled live migration and count parity
  7. Deterministic SHA-256 fingerprint checksum verification
  8. Idempotent repeat migration without duplication
  9. Reversible rollback removing only tagged MongoDB documents
  10. Dual-write disabled by default
  11. Dual-write success across core entities
  12. Dual-write MongoDB failure resilience
  13. Migration CLI interface
  14. Migration safety checks
  15. Migration report generation
