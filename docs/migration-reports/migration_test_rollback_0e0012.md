# Migration Audit Report: `test_rollback_0e0012`

## 1. Execution Summary

- **Migration ID**: `test_rollback_0e0012`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-10-02T02:46:24.196343+00:00`
- **End Time (UTC)**: `2026-10-02T02:46:41.606218+00:00`
- **Duration**: `17.41 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2393 | 0 | 2393 | 0 | 0 | 2393 | **MATCH** |
| `events` | 171 | 0 | 171 | 0 | 0 | 171 | **MATCH** |
| `notifications` | 10462 | 0 | 10462 | 0 | 0 | 10462 | **MATCH** |
| `recurring_task_executions` | 10 | 0 | 10 | 0 | 0 | 10 | **MATCH** |
| `recurring_tasks` | 11 | 0 | 11 | 0 | 0 | 11 | **MATCH** |
| `refresh_tokens` | 1500 | 0 | 1500 | 0 | 0 | 1500 | **MATCH** |
| `task_history` | 15659 | 0 | 15659 | 0 | 0 | 15659 | **MATCH** |
| `task_templates` | 273 | 0 | 273 | 0 | 0 | 273 | **MATCH** |
| `tasks` | 11087 | 0 | 11087 | 0 | 0 | 11087 | **MATCH** |
| `user_settings` | 570 | 0 | 570 | 0 | 0 | 570 | **MATCH** |
| `users` | 10260 | 0 | 10260 | 0 | 0 | 10260 | **MATCH** |
| `workflows` | 2079 | 0 | 2079 | 0 | 0 | 2079 | **MATCH** |

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
      "pending": 8260,
      "in_progress": 1371,
      "completed": 1006,
      "cancelled": 450
    },
    "mongodb": {
      "pending": 8260,
      "completed": 1006,
      "cancelled": 450,
      "in_progress": 1371
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 6691,
      "high": 1387,
      "urgent": 1500,
      "low": 1509
    },
    "mongodb": {
      "urgent": 1500,
      "low": 1509,
      "high": 1387,
      "medium": 6691
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4958,
    "mongodb": 4958,
    "match": true
  },
  "completed_count": {
    "postgresql": 1006,
    "mongodb": 1006,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
