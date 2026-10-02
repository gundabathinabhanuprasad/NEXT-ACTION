# Migration Audit Report: `test_rollback_c2cca6`

## 1. Execution Summary

- **Migration ID**: `test_rollback_c2cca6`
- **Execution Mode**: `MIGRATE`
- **Status**: `FAILED`
- **Start Time (UTC)**: `2026-09-30T16:38:12.499154+00:00`
- **End Time (UTC)**: `2026-09-30T16:38:18.213622+00:00`
- **Duration**: `5.71 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2017 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `events` | 86 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `notifications` | 8342 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `recurring_task_executions` | 39 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `recurring_tasks` | 35 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `refresh_tokens` | 961 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `task_history` | 13829 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `task_templates` | 168 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `tasks` | 9620 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `user_settings` | 417 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `users` | 8892 | 0 | 0 | 0 | 0 | 0 | **DELTA** |
| `workflows` | 1749 | 0 | 0 | 0 | 0 | 0 | **DELTA** |

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
