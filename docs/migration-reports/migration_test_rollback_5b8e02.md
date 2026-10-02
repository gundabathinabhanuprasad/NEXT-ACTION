# Migration Audit Report: `test_rollback_5b8e02`

## 1. Execution Summary

- **Migration ID**: `test_rollback_5b8e02`
- **Execution Mode**: `MIGRATE`
- **Status**: `COMPLETED`
- **Start Time (UTC)**: `2026-10-01T02:06:27.650965+00:00`
- **End Time (UTC)**: `2026-10-01T02:06:39.047715+00:00`
- **Duration**: `11.40 seconds`
- **Source Database**: `postgresql` (PostgreSQL 16)
- **Destination Database**: `mongodb` (MongoDB 7 / M0)

---

## 2. Collection Entity Counts & Loading Operations

| Collection | Source (PG) | Destination (Before) | Inserted | Updated | Failed | Destination (After) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `clients` | 2254 | 0 | 2254 | 0 | 0 | 2254 | **MATCH** |
| `events` | 144 | 0 | 144 | 0 | 0 | 144 | **MATCH** |
| `notifications` | 9081 | 0 | 9081 | 0 | 0 | 9081 | **MATCH** |
| `recurring_task_executions` | 109 | 0 | 109 | 0 | 0 | 109 | **MATCH** |
| `recurring_tasks` | 104 | 0 | 104 | 0 | 0 | 104 | **MATCH** |
| `refresh_tokens` | 1310 | 0 | 1310 | 0 | 0 | 1310 | **MATCH** |
| `task_history` | 14822 | 0 | 14822 | 0 | 0 | 14822 | **MATCH** |
| `task_templates` | 237 | 0 | 237 | 0 | 0 | 237 | **MATCH** |
| `tasks` | 10462 | 0 | 10462 | 0 | 0 | 10462 | **MATCH** |
| `user_settings` | 518 | 0 | 518 | 0 | 0 | 518 | **MATCH** |
| `users` | 9729 | 0 | 9729 | 0 | 0 | 9729 | **MATCH** |
| `workflows` | 1956 | 0 | 1956 | 0 | 0 | 1956 | **MATCH** |

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
      "pending": 7820,
      "in_progress": 1280,
      "completed": 933,
      "cancelled": 429
    },
    "mongodb": {
      "pending": 7820,
      "completed": 933,
      "cancelled": 429,
      "in_progress": 1280
    },
    "match": true
  },
  "priority_distribution": {
    "postgresql": {
      "medium": 6328,
      "high": 1318,
      "urgent": 1409,
      "low": 1407
    },
    "mongodb": {
      "urgent": 1409,
      "low": 1407,
      "high": 1318,
      "medium": 6328
    },
    "match": true
  },
  "total_attempts": {
    "postgresql": 4663,
    "mongodb": 4663,
    "match": true
  },
  "completed_count": {
    "postgresql": 933,
    "mongodb": 933,
    "match": true
  }
}
```


---

## 6. Safety & Rollback Verification

- PostgreSQL was **NEVER** modified, deleted, or rolled back.
- In rollback mode, only MongoDB documents with `_migration_id` are removed.
- Production architecture remains ₹0/month with zero cloud resources created.
