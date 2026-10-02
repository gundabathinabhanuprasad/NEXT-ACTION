# Migration Audit Report: `test_rollback_011c74`

## 1. Execution Summary

- **Migration ID**: `test_rollback_011c74`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-09-30T17:48:13.791713+00:00`
- **End Time (UTC)**: `2026-09-30T17:48:28.114257+00:00`
- **Duration**: `14.32 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2189 | 0 | 2189 | 0 | 0 | 2189 | **MATCH** |
| `events` | 134 | 0 | 134 | 0 | 0 | 134 | **MATCH** |
| `notifications` | 8854 | 0 | 8854 | 0 | 0 | 8854 | **MATCH** |
| `recurring_task_executions` | 94 | 0 | 94 | 0 | 0 | 94 | **MATCH** |
| `recurring_tasks` | 90 | 0 | 90 | 0 | 0 | 90 | **MATCH** |
| `refresh_tokens` | 1207 | 0 | 1207 | 0 | 0 | 1207 | **MATCH** |
| `task_history` | 14504 | 0 | 14504 | 0 | 0 | 14504 | **MATCH** |
| `task_templates` | 223 | 0 | 223 | 0 | 0 | 223 | **MATCH** |
| `tasks` | 10210 | 0 | 10210 | 0 | 0 | 10210 | **MATCH** |
| `user_settings` | 492 | 0 | 492 | 0 | 0 | 492 | **MATCH** |
| `users` | 9491 | 0 | 9491 | 0 | 0 | 9491 | **MATCH** |
| `workflows` | 1899 | 0 | 1899 | 0 | 0 | 1899 | **MATCH** |

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
      "pending": 7648,
      "in_progress": 1242,
      "completed": 902,
      "cancelled": 418
    },
    "mongodb": {
      "pending": 7648,
      "completed": 902,
      "cancelled": 418,
      "in_progress": 1242
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 6196,
      "high": 1285,
      "urgent": 1368,
      "low": 1361
    },
    "mongodb": {
      "urgent": 1368,
      "low": 1361,
      "high": 1285,
      "medium": 6196
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4530,
    "mongodb": 4530,
    "match": true
  },
  "completed_count": {
    "postgresql": 902,
    "mongodb": 902,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
