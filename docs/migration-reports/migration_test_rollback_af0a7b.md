# Migration Audit Report: `test_rollback_af0a7b`

## 1. Execution Summary

- **Migration ID**: `test_rollback_af0a7b`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-10-01T17:25:51.358679+00:00`
- **End Time (UTC)**: `2026-10-01T17:26:02.940857+00:00`
- **Duration**: `11.58 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2338 | 0 | 2338 | 0 | 0 | 2338 | **MATCH** |
| `events` | 160 | 0 | 160 | 0 | 0 | 160 | **MATCH** |
| `notifications` | 9761 | 0 | 9761 | 0 | 0 | 9761 | **MATCH** |
| `recurring_task_executions` | 148 | 0 | 148 | 0 | 0 | 148 | **MATCH** |
| `recurring_tasks` | 124 | 0 | 124 | 0 | 0 | 124 | **MATCH** |
| `refresh_tokens` | 1419 | 0 | 1419 | 0 | 0 | 1419 | **MATCH** |
| `task_history` | 15210 | 0 | 15210 | 0 | 0 | 15210 | **MATCH** |
| `task_templates` | 257 | 0 | 257 | 0 | 0 | 257 | **MATCH** |
| `tasks` | 10781 | 0 | 10781 | 0 | 0 | 10781 | **MATCH** |
| `user_settings` | 549 | 0 | 549 | 0 | 0 | 549 | **MATCH** |
| `users` | 10014 | 0 | 10014 | 0 | 0 | 10014 | **MATCH** |
| `workflows` | 2031 | 0 | 2031 | 0 | 0 | 2031 | **MATCH** |

---

## 3. Relationship & Referential Integrity Validation

All foreign key relationships and parent references validated with **0 errors**.


---

## 4. Checksum & Fingerprint Integrity Verification

All record SHA-256 fingerprints between PostgreSQL and MongoDB matched with **100% parity**.


---

## 5. Task Distribution Parity

```json
{
  "status_distribution": {
    "postgresql": {
      "pending": 8035,
      "in_progress": 1331,
      "completed": 975,
      "cancelled": 440
    },
    "mongodb": {
      "pending": 8035,
      "completed": 975,
      "cancelled": 440,
      "in_progress": 1331
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 6492,
      "high": 1359,
      "urgent": 1462,
      "low": 1468
    },
    "mongodb": {
      "urgent": 1462,
      "low": 1468,
      "high": 1359,
      "medium": 6492
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4833,
    "mongodb": 4833,
    "match": true
  },
  "completed_count": {
    "postgresql": 975,
    "mongodb": 975,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
