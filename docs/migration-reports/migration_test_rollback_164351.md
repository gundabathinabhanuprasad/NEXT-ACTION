# Migration Audit Report: `test_rollback_164351`

## 1. Execution Summary

- **Migration ID**: `test_rollback_164351`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-09-30T16:41:01.283735+00:00`
- **End Time (UTC)**: `2026-09-30T16:41:11.004883+00:00`
- **Duration**: `9.72 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2041 | 0 | 2041 | 0 | 0 | 2041 | **MATCH** |
| `events` | 104 | 0 | 104 | 0 | 0 | 104 | **MATCH** |
| `notifications` | 8364 | 0 | 8364 | 0 | 0 | 8364 | **MATCH** |
| `recurring_task_executions` | 57 | 0 | 57 | 0 | 0 | 57 | **MATCH** |
| `recurring_tasks` | 53 | 0 | 53 | 0 | 0 | 53 | **MATCH** |
| `refresh_tokens` | 979 | 0 | 979 | 0 | 0 | 979 | **MATCH** |
| `task_history` | 13851 | 0 | 13851 | 0 | 0 | 13851 | **MATCH** |
| `task_templates` | 186 | 0 | 186 | 0 | 0 | 186 | **MATCH** |
| `tasks` | 9658 | 0 | 9658 | 0 | 0 | 9658 | **MATCH** |
| `user_settings` | 435 | 0 | 435 | 0 | 0 | 435 | **MATCH** |
| `users` | 8930 | 0 | 8930 | 0 | 0 | 8930 | **MATCH** |
| `workflows` | 1769 | 0 | 1769 | 0 | 0 | 1769 | **MATCH** |

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
      "pending": 7284,
      "in_progress": 1152,
      "completed": 826,
      "cancelled": 396
    },
    "mongodb": {
      "pending": 7284,
      "completed": 826,
      "cancelled": 396,
      "in_progress": 1152
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 5904,
      "high": 1221,
      "urgent": 1277,
      "low": 1256
    },
    "mongodb": {
      "urgent": 1277,
      "low": 1256,
      "high": 1221,
      "medium": 5904
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4218,
    "mongodb": 4218,
    "match": true
  },
  "completed_count": {
    "postgresql": 826,
    "mongodb": 826,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
