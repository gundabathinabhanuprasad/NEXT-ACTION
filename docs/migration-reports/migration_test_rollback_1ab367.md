# Migration Audit Report: `test_rollback_1ab367`

## 1. Execution Summary

- **Migration ID**: `test_rollback_1ab367`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-10-02T03:20:34.428609+00:00`
- **End Time (UTC)**: `2026-10-02T03:20:55.817042+00:00`
- **Duration**: `21.39 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2501 | 0 | 2501 | 0 | 0 | 2501 | **MATCH** |
| `events` | 191 | 0 | 191 | 0 | 0 | 191 | **MATCH** |
| `notifications` | 11078 | 0 | 11078 | 0 | 0 | 11078 | **MATCH** |
| `recurring_task_executions` | 34 | 0 | 34 | 0 | 0 | 34 | **MATCH** |
| `recurring_tasks` | 35 | 0 | 35 | 0 | 0 | 35 | **MATCH** |
| `refresh_tokens` | 1640 | 0 | 1640 | 0 | 0 | 1640 | **MATCH** |
| `task_history` | 16125 | 0 | 16125 | 0 | 0 | 16125 | **MATCH** |
| `task_templates` | 297 | 0 | 297 | 0 | 0 | 297 | **MATCH** |
| `tasks` | 11513 | 0 | 11513 | 0 | 0 | 11513 | **MATCH** |
| `user_settings` | 610 | 0 | 610 | 0 | 0 | 610 | **MATCH** |
| `users` | 10703 | 0 | 10703 | 0 | 0 | 10703 | **MATCH** |
| `workflows` | 2173 | 0 | 2173 | 0 | 0 | 2173 | **MATCH** |

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
      "pending": 8546,
      "in_progress": 1437,
      "completed": 1060,
      "cancelled": 470
    },
    "mongodb": {
      "pending": 8546,
      "completed": 1060,
      "cancelled": 470,
      "in_progress": 1437
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 6931,
      "high": 1431,
      "urgent": 1562,
      "low": 1589
    },
    "mongodb": {
      "urgent": 1562,
      "low": 1589,
      "high": 1431,
      "medium": 6931
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 5192,
    "mongodb": 5192,
    "match": true
  },
  "completed_count": {
    "postgresql": 1060,
    "mongodb": 1060,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
