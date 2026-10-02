# Migration Audit Report: `test_rollback_d75038`

## 1. Execution Summary

- **Migration ID**: `test_rollback_d75038`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-09-30T17:42:49.188054+00:00`
- **End Time (UTC)**: `2026-09-30T17:43:03.531247+00:00`
- **Duration**: `14.34 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2135 | 0 | 2135 | 0 | 0 | 2135 | **MATCH** |
| `events` | 124 | 0 | 124 | 0 | 0 | 124 | **MATCH** |
| `notifications` | 8654 | 0 | 8654 | 0 | 0 | 8654 | **MATCH** |
| `recurring_task_executions` | 82 | 0 | 82 | 0 | 0 | 82 | **MATCH** |
| `recurring_tasks` | 78 | 0 | 78 | 0 | 0 | 78 | **MATCH** |
| `refresh_tokens` | 1132 | 0 | 1132 | 0 | 0 | 1132 | **MATCH** |
| `task_history` | 14280 | 0 | 14280 | 0 | 0 | 14280 | **MATCH** |
| `task_templates` | 211 | 0 | 211 | 0 | 0 | 211 | **MATCH** |
| `tasks` | 10003 | 0 | 10003 | 0 | 0 | 10003 | **MATCH** |
| `user_settings` | 472 | 0 | 472 | 0 | 0 | 472 | **MATCH** |
| `users` | 9275 | 0 | 9275 | 0 | 0 | 9275 | **MATCH** |
| `workflows` | 1852 | 0 | 1852 | 0 | 0 | 1852 | **MATCH** |

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
      "pending": 7511,
      "in_progress": 1209,
      "completed": 875,
      "cancelled": 408
    },
    "mongodb": {
      "pending": 7511,
      "completed": 875,
      "cancelled": 408,
      "in_progress": 1209
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 6082,
      "high": 1263,
      "urgent": 1337,
      "low": 1321
    },
    "mongodb": {
      "urgent": 1337,
      "low": 1321,
      "high": 1263,
      "medium": 6082
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4414,
    "mongodb": 4414,
    "match": true
  },
  "completed_count": {
    "postgresql": 875,
    "mongodb": 875,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
