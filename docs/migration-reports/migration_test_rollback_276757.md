# Migration Audit Report: `test_rollback_276757`

## 1. Execution Summary

- **Migration ID**: `test_rollback_276757`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-10-02T02:52:05.342779+00:00`
- **End Time (UTC)**: `2026-10-02T02:52:22.879459+00:00`
- **Duration**: `17.54 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2447 | 0 | 2447 | 0 | 0 | 2447 | **MATCH** |
| `events` | 181 | 0 | 181 | 0 | 0 | 181 | **MATCH** |
| `notifications` | 10903 | 0 | 10903 | 0 | 0 | 10903 | **MATCH** |
| `recurring_task_executions` | 22 | 0 | 22 | 0 | 0 | 22 | **MATCH** |
| `recurring_tasks` | 23 | 0 | 23 | 0 | 0 | 23 | **MATCH** |
| `refresh_tokens` | 1570 | 0 | 1570 | 0 | 0 | 1570 | **MATCH** |
| `task_history` | 15901 | 0 | 15901 | 0 | 0 | 15901 | **MATCH** |
| `task_templates` | 285 | 0 | 285 | 0 | 0 | 285 | **MATCH** |
| `tasks` | 11306 | 0 | 11306 | 0 | 0 | 11306 | **MATCH** |
| `user_settings` | 590 | 0 | 590 | 0 | 0 | 590 | **MATCH** |
| `users` | 10492 | 0 | 10492 | 0 | 0 | 10492 | **MATCH** |
| `workflows` | 2126 | 0 | 2126 | 0 | 0 | 2126 | **MATCH** |

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
      "pending": 8409,
      "in_progress": 1404,
      "completed": 1033,
      "cancelled": 460
    },
    "mongodb": {
      "pending": 8409,
      "completed": 1033,
      "cancelled": 460,
      "in_progress": 1404
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 6817,
      "high": 1409,
      "urgent": 1531,
      "low": 1549
    },
    "mongodb": {
      "urgent": 1531,
      "low": 1549,
      "high": 1409,
      "medium": 6817
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 5076,
    "mongodb": 5076,
    "match": true
  },
  "completed_count": {
    "postgresql": 1033,
    "mongodb": 1033,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
