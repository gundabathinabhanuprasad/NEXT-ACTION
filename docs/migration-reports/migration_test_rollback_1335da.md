# Migration Audit Report: `test_rollback_1335da`

## 1. Execution Summary

- **Migration ID**: `test_rollback_1335da`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-09-30T16:45:14.267012+00:00`
- **End Time (UTC)**: `2026-09-30T16:45:38.525824+00:00`
- **Duration**: `24.26 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2069 | 0 | 2069 | 0 | 0 | 2069 | **MATCH** |
| `events` | 114 | 0 | 114 | 0 | 0 | 114 | **MATCH** |
| `notifications` | 8405 | 0 | 8405 | 0 | 0 | 8405 | **MATCH** |
| `recurring_task_executions` | 67 | 0 | 67 | 0 | 0 | 67 | **MATCH** |
| `recurring_tasks` | 64 | 0 | 64 | 0 | 0 | 64 | **MATCH** |
| `refresh_tokens` | 1027 | 0 | 1027 | 0 | 0 | 1027 | **MATCH** |
| `task_history` | 13960 | 0 | 13960 | 0 | 0 | 13960 | **MATCH** |
| `task_templates` | 197 | 0 | 197 | 0 | 0 | 197 | **MATCH** |
| `tasks` | 9750 | 0 | 9750 | 0 | 0 | 9750 | **MATCH** |
| `user_settings` | 446 | 0 | 446 | 0 | 0 | 446 | **MATCH** |
| `users` | 9036 | 0 | 9036 | 0 | 0 | 9036 | **MATCH** |
| `workflows` | 1794 | 0 | 1794 | 0 | 0 | 1794 | **MATCH** |

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
      "pending": 7339,
      "in_progress": 1171,
      "completed": 843,
      "cancelled": 397
    },
    "mongodb": {
      "pending": 7339,
      "completed": 843,
      "cancelled": 397,
      "in_progress": 1171
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 5950,
      "high": 1229,
      "urgent": 1296,
      "low": 1275
    },
    "mongodb": {
      "urgent": 1296,
      "low": 1275,
      "high": 1229,
      "medium": 5950
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4281,
    "mongodb": 4281,
    "match": true
  },
  "completed_count": {
    "postgresql": 843,
    "mongodb": 843,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
