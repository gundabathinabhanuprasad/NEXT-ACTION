# Migration Audit Report: `test_rollback_6c76cc`

## 1. Execution Summary

- **Migration ID**: `test_rollback_6c76cc`
- **Execution Mode**: `MIGRATE`
- **Status**: `FAILED`
- **Start Time (UTC)**: `2026-09-30T16:39:24.471198+00:00`
- **End Time (UTC)**: `2026-09-30T16:39:30.249805+00:00`
- **Duration**: `5.78 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2029 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `events` | 95 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `notifications` | 8353 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `recurring_task_executions` | 48 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `recurring_tasks` | 44 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `refresh_tokens` | 970 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `task_history` | 13840 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `task_templates` | 177 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `tasks` | 9639 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `user_settings` | 426 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `users` | 8911 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `workflows` | 1759 | 0 | 0 | 0 | 0 | 0 | **DELTA** |

---

## 3. Relationship & Referential Integrity Validation

All foreign key relationships and parent references validated with **0 errors**.


---

## 4. Checksum & Fingerprint Integrity Verification

All record SHA-256 fingerprints between PostgreSQL and MongoDB matched with **100% parity**.


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
