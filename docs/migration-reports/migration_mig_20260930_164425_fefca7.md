# Migration Audit Report: `mig_20260930_164425_fefca7`

## 1. Execution Summary

- **Migration ID**: `mig_20260930_164425_fefca7`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-09-30T16:44:25.777978+00:00`
- **End Time (UTC)**: `2026-09-30T16:44:48.881286+00:00`
- **Duration**: `23.10 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2068 | 0 | 2068 | 0 | 0 | 2068 | **MATCH** |
| `events` | 113 | 0 | 113 | 0 | 0 | 113 | **MATCH** |
| `notifications` | 8404 | 0 | 8404 | 0 | 0 | 8404 | **MATCH** |
| `recurring_task_executions` | 66 | 0 | 66 | 0 | 0 | 66 | **MATCH** |
| `recurring_tasks` | 63 | 0 | 63 | 0 | 0 | 63 | **MATCH** |
| `refresh_tokens` | 1026 | 0 | 1026 | 0 | 0 | 1026 | **MATCH** |
| `task_history` | 13959 | 0 | 13959 | 0 | 0 | 13959 | **MATCH** |
| `task_templates` | 196 | 0 | 196 | 0 | 0 | 196 | **MATCH** |
| `tasks` | 9748 | 0 | 9748 | 0 | 0 | 9748 | **MATCH** |
| `user_settings` | 445 | 0 | 445 | 0 | 0 | 445 | **MATCH** |
| `users` | 9034 | 0 | 9034 | 0 | 0 | 9034 | **MATCH** |
| `workflows` | 1793 | 0 | 1793 | 0 | 0 | 1793 | **MATCH** |

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
      "in_progress": 1170,
      "completed": 842,
      "cancelled": 397
    },
    "mongodb": {
      "pending": 7339,
      "completed": 842,
      "cancelled": 397,
      "in_progress": 1170
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 5950,
      "high": 1229,
      "urgent": 1295,
      "low": 1274
    },
    "mongodb": {
      "urgent": 1295,
      "low": 1274,
      "high": 1229,
      "medium": 5950
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4278,
    "mongodb": 4278,
    "match": true
  },
  "completed_count": {
    "postgresql": 842,
    "mongodb": 842,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
