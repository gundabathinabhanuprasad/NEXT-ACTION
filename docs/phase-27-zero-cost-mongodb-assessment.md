# Phase 27 — Zero-Cost Production Architecture & MongoDB Migration Assessment

**Project:** NextAction Production Deployment  
**Current Application Version:** 1.0.0 (Build 1)  
**Primary Strategic Mandate:** Transition to ₹0/month hosting cost while migrating persistence from PostgreSQL/SQLAlchemy to MongoDB.  
**Assessment Status:** Complete Technical Assessment & Architecture Specification (Zero application code modified / PostgreSQL remains 100% intact).

---

## 1. Executive Summary & Context

NextAction v1.0.0 has completed comprehensive development, hardening, and verification across Phases 1 through 25, passing 100% of automated tests (200/200 backend, 500/500 Flutter, 35/35 live HTTPS production checks).

However, traditional public cloud infrastructure (such as AWS EC2 + RDS + ElastiCache) carries recurring monthly commitments (~$33 to $75+/month). To achieve long-term sustainability without operational expenditure, the project has mandated a **hard requirement of ₹0/month hosting cost** and established **MongoDB as the strategic database direction**.

Because the current application relies on relational paradigms (SQLAlchemy ORM, Alembic migrations, foreign key cascades, partial unique indexes, multi-table joins, and complex conditional aggregations), a naive or rushed migration would introduce severe architectural and operational regressions.

This document delivers a thorough, evidence-based migration assessment and establishes a proven, concrete zero-cost target architecture without modifying existing application code or breaking the verified PostgreSQL stack.

---

## 2. PostgreSQL Dependency Inventory & Categorization

A comprehensive scan of the `backend/` codebase identified all occurrences of SQLAlchemy, Alembic, PostgreSQL-specific SQL, transactions, constraints, and relational patterns.

### 2.1. Categorization Taxonomy
- **Category A (Easy MongoDB Replacement):** Direct key-value or document CRUD with minimal relational coupling.
- **Category B (Requires Service-Layer Rewrite):** Methods relying on `db.add()`, `db.flush()`, `db.commit()`, `db.refresh()`, or ORM relationship lazy/joined loading.
- **Category C (Requires Query Redesign):** Multi-table joins (`outerjoin`), conditional counts (`func.count(case(...))`), and cross-entity filtering.
- **Category D (Requires Data-Model Redesign):** Relational normalization requiring strategic embedding vs. referencing decisions.
- **Category E (PostgreSQL-Specific / Obsolete in Mongo):** Alembic migrations, PostgreSQL UUID types, `native_enum`, `postgresql_where` partial indexes.
- **Category F (Potentially Difficult / High-Risk Consistency):** Cross-collection transactional atomicity, race-safe deduplication, attempt limit concurrency.

### 2.2. Dependency Mapping Matrix

| Component / File | Primary Relational Dependencies | Impact Category | MongoDB Migration Strategy |
|---|---|---|---|
| **`app/models/*` (14 Models)** | `Mapped`, `mapped_column`, `ForeignKey`, `relationship`, `UUID`, `Enum` | **D, E** | Replace with Pydantic v2 domain schemas or Mongo ODM documents with string/BSON ObjectId identifiers. |
| **`app/db/session.py`** | `create_engine`, `sessionmaker`, `pool_size`, `max_overflow`, `get_db()` | **E** | Replace with `AsyncMongoClient` (Motor) or thread-safe `MongoClient` (PyMongo) connection pooling singleton. |
| **`app/api/dependencies.py`** | `Session = Depends(get_db)` | **B** | Inject MongoDB database/collection dependencies into FastAPI endpoints. |
| **`app/services/task_service.py`** | `outerjoin(Client, User, Workflow)`, `ilike`, `nullslast()`, `db.flush()`, `db.commit()` | **B, C, F** | Redesign with denormalized client/workflow/user summary fields or `$lookup` aggregation pipelines; atomic `$inc` for attempts. |
| **`app/services/auth_service.py`** | `select(User)`, `select(RefreshToken)`, `update(RefreshToken).where(...)` | **B, F** | Atomic `find_one_and_update` on token rotation; cascading session invalidation via `update_many`. |
| **`app/services/dashboard_service.py`** | Complex `func.count(case(...))`, daily time-series grouping, multi-join stats | **C** | Rewrite using MongoDB Aggregation Pipeline (`$match`, `$facet`, `$group`, `$cond`, `$dateTrunc`). |
| **`app/services/report_service.py`** | Dynamic multi-filter queries, `joinedload`, CSV cursor streaming | **C** | Aggregation pipeline with `$facet` for data and count; cursor-based batch streaming for CSV generation. |
| **`app/services/scheduling_service.py`** | Savepoints, `IntegrityError` on `uq_notifications_user_dedup`, calendar bounds | **B, F** | Unique partial index in MongoDB (`partialFilterExpression`); atomic upsert or deduplication check. |
| **`app/services/notification_service.py`** | Partial unique constraint on `(user_id, dedup_key)`, unread filtering | **A, B** | Dedicated `notifications` collection with compound index `{ user_id: 1, dedup_key: 1 }`. |
| **`app/services/history_service.py`** | Append-only audit logging, `SET NULL` on user/task deletion | **A** | Append-only `task_history` collection or embedded historical audit log array. |
| **`app/services/recurring_task_service.py`** | `UniqueConstraint("recurring_task_id", "scheduled_for")`, transaction rollback | **B, F** | Compound unique index `{ recurring_task_id: 1, scheduled_for: 1 }`; atomic execution logging. |
| **`app/services/settings_service.py`** | 1-to-1 relationship with User, cascade delete | **A, D** | Embed directly inside `users` document (`user.settings`). Eliminates all joins. |
| **`alembic/*` (9 Revisions)** | Table creation, foreign key constraints, column additions, indexes | **E** | Deprecate Alembic; replace with automated idempotent index initialization script on startup (`init_mongo_indexes()`). |

---

## 3. Database Model Inventory

The application currently manages 14 relational models:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Current Relational Schema                       │
├────────────────────┬────────────────────┬──────────────────────────────┤
│ Model              │ Primary Key        │ Foreign Keys & Relationships │
├────────────────────┼────────────────────┼──────────────────────────────┤
│ User               │ UUID               │ 1:1 UserSettings, 1:N Tasks  │
│ UserSettings       │ UUID               │ FK -> users.id (Unique, Cas) │
│ Client             │ UUID               │ 1:N Tasks, 1:N Events        │
│ Workflow           │ UUID               │ 1:N Tasks                    │
│ Task               │ UUID               │ FK -> clients, workflows,    │
│                    │                    │       users, templates, rec. │
│ FollowUp           │ UUID               │ FK -> tasks.id (Cascade)     │
│ Reminder           │ UUID               │ FK -> tasks.id (Cascade)     │
│ Event              │ UUID               │ FK -> tasks.id, clients.id   │
│ TaskHistory        │ UUID               │ FK -> tasks.id, users.id     │
│ Notification       │ UUID               │ FK -> users.id, tasks.id     │
│ TaskTemplate       │ UUID               │ FK -> users, workflows, cli. │
│ RecurringTask      │ UUID               │ FK -> templates, workflows   │
│ RecurringTaskExec  │ UUID               │ FK -> recurring_tasks.id     │
│ RefreshToken       │ UUID               │ FK -> users.id (Cascade)     │
└────────────────────┴────────────────────┴──────────────────────────────┘
```

---

## 4. MongoDB Data Model Design (Embedding vs. Referencing)

In MongoDB, blindly embedding every child document leads to unbounded document growth (exceeding BSON 16 MB limits) and poor indexing performance. Conversely, normalizing everything creates excessive `$lookup` joins. The optimal design balances atomic reads with controlled document sizing:

### 4.1. Entity Storage Strategy

| Entity | Storage Pattern | Justification |
|---|---|---|
| **`users`** | **Top-Level Collection** | Core actor entity. Includes embedded `settings` subdocument (1:1 relationship, accessed together on every authenticated request). |
| **`user_settings`** | **Embedded in `users`** | Exactly one settings record exists per user. Embedding eliminates 100% of joins on `/auth/me` and preference lookups. |
| **`refresh_tokens`** | **Top-Level Collection** | High churn rate and security rotation. Storing separately prevents unbounded growth of the `users` document and allows TTL index expiration. |
| **`clients`** | **Top-Level Collection** | Independent CRM business entity shared across multiple tasks and events. |
| **`workflows`** | **Top-Level Collection** | Organizational categorization shared across many tasks. |
| **`tasks`** | **Top-Level Collection** | Central transactional entity. Contains denormalized snapshots of `client_name`, `workflow_name`, and `assignee_name` for zero-join listing. |
| **`reminders`** | **Embedded in `tasks`** | Tasks rarely have more than 5 reminders. Reminders are lifecycle-bound to tasks and deleted with them. |
| **`follow_ups`** | **Embedded in `tasks`** | Follow-ups are direct sub-items of a task (typically 1-10 items). Embedding ensures atomic task updates. |
| **`task_history`** | **Top-Level Collection** | Audit trails for active tasks grow indefinitely. Storing in a separate collection (`task_id` indexed) prevents task documents from expanding unpredictably. |
| **`notifications`** | **Top-Level Collection** | Independent high-volume entity queried by `user_id` and `is_read`. Cannot be embedded in tasks because notifications outlive tasks. |
| **`task_templates`** | **Top-Level Collection** | Reusable blueprints for ad-hoc and recurring task creation. |
| **`recurring_tasks`** | **Top-Level Collection** | Active schedule definitions evaluated by the automated scheduler. |
| **`recurring_task_executions`** | **Top-Level Collection** | High-volume idempotency execution logs. Indexed by `{ recurring_task_id: 1, scheduled_for: 1 }`. |
| **`events`** | **Top-Level Collection** | Calendar appointments linked optionally to tasks or clients. |

### 4.2. Sample Proposed MongoDB Document Structures

#### `tasks` Collection Document
```json
{
  "_id": "c1f2e3d4-b5a6-4c7d-8e9f-0a1b2c3d4e5f",
  "title": "Review Quarterly Financial Audit",
  "description": "Examine reconciliation statements",
  "subject_line": "Urgent Q3 Audit Review",
  "status": "pending",
  "priority": "urgent",
  "client": {
    "id": "a1b2c3d4-...",
    "name": "Acme Global Industries"
  },
  "workflow": {
    "id": "w1w2w3w4-...",
    "name": "Finance & Compliance"
  },
  "assigned_user": {
    "id": "u1u2u3u4-...",
    "name": "Bhanu Prakash",
    "email": "bhanu@nextaction.io"
  },
  "template_id": null,
  "recurring_task_id": null,
  "due_date": "2026-10-05T18:00:00Z",
  "next_action_date": "2026-10-02T09:00:00Z",
  "attempt_count": 1,
  "max_attempts": 2,
  "completed_at": null,
  "reminders": [
    {
      "id": "r1r2...",
      "remind_at": "2026-10-02T08:30:00Z",
      "message": "Call client CFO",
      "is_sent": false
    }
  ],
  "follow_ups": [
    {
      "id": "f1f2...",
      "scheduled_at": "2026-10-03T10:00:00Z",
      "completed_at": null,
      "notes": "Verify ledger entry"
    }
  ],
  "created_at": "2026-09-30T08:00:00Z",
  "updated_at": "2026-09-30T08:15:00Z"
}
```

---

## 5. Database Access Layer Architecture

### 5.1. Driver Evaluation: PyMongo vs. Motor
- **FastAPI Threading Model:** The current NextAction backend implements synchronous route endpoints (`def get_task(...)`, `def create_task(...)`). FastAPI automatically offloads synchronous endpoints to AnyIO worker threadpools.
- **Option 1: PyMongo:**
  - *Pros:* Drop-in replacement for synchronous service methods without converting hundreds of functions into `async def`. Native connection pooling. Full replica set and transaction support.
  - *Cons:* Executes synchronously within worker threads.
- **Option 2: Motor (Async):**
  - *Pros:* Native `async`/`await` non-blocking I/O. Ideal for high concurrency.
  - *Cons:* Requires converting every service method, repository method, and route handler into `async def`, causing massive refactoring churn.
- **Selected Recommendation:** **Repository Pattern backed by PyMongo** (or hybrid where database operations are encapsulated in clean Repository classes). This isolates persistence logic from business logic and allows synchronous execution today while permitting async transition later.

---

## 6. Business Rule Preservation Guarantees

Every core business rule from Phases 1–25 will be preserved identically in MongoDB:

1. **Task Attempts (Default 2, Max Enforcement, Authorized Override):**
   - *PostgreSQL:* Checked via Python logic and incremented in session.
   - *MongoDB:* Atomic `$inc: { attempt_count: 1 }` with query filter `{ _id: task_id, attempt_count: { $lt: max_attempts } }`. If matched count is 0, the operation is rejected with `MaxAttemptsReachedError (HTTP 409)`. Authorized overrides supply `reason` and bypass the ceiling atomically.
2. **Postponement (Reason Mandatory):**
   - Validates non-empty string in business service before executing `$set: { next_action_date: ..., due_date: ... }`. Logs audit entry to `task_history`.
3. **Reopening (Reason Mandatory, Restore to PENDING):**
   - Updates status to `pending`, clears `completed_at`, records justification reason, and logs history.
4. **Refresh Token Rotation & Replay Attack Detection:**
   - On rotation, `find_one_and_update({ token_hash: hash, is_revoked: false }, { $set: { is_revoked: true, replaced_by_id: new_id } })`. If token was already revoked, execute `update_many({ user_id: uid }, { $set: { is_revoked: true } })` to revoke all active sessions.
5. **Notification Deduplication:**
   - Compound unique index on `{ user_id: 1, dedup_key: 1 }` with `partialFilterExpression: { dedup_key: { $type: "string" } }`. Rejects duplicate inserts with `DuplicateKeyError` (handled as idempotent no-op).

---

## 7. MongoDB Index Design Specification

To ensure sub-50ms query latency on free-tier compute, the following indexes are specified:

```javascript
// tasks collection
db.tasks.createIndex({ status: 1, priority: 1 });
db.tasks.createIndex({ assigned_user_id: 1, status: 1 });
db.tasks.createIndex({ due_date: 1 }, { sparse: true });
db.tasks.createIndex({ next_action_date: 1 }, { sparse: true });
db.tasks.createIndex({ client_id: 1 });
db.tasks.createIndex({ workflow_id: 1 });
db.tasks.createIndex({ created_at: -1 });
db.tasks.createIndex({
  title: "text",
  description: "text",
  subject_line: "text",
  "client.name": "text",
  "workflow.name": "text",
  "assigned_user.name": "text"
});

// notifications collection
db.notifications.createIndex({ user_id: 1, is_read: 1, created_at: -1 });
db.notifications.createIndex(
  { user_id: 1, dedup_key: 1 },
  { unique: true, partialFilterExpression: { dedup_key: { $type: "string" } } }
);

// refresh_tokens collection
db.refresh_tokens.createIndex({ token_hash: 1 }, { unique: true });
db.refresh_tokens.createIndex({ user_id: 1, is_revoked: 1 });
db.refresh_tokens.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 }); // Native TTL cleanup!

// task_history collection
db.task_history.createIndex({ task_id: 1, created_at: -1 });
db.task_history.createIndex({ created_by_user_id: 1 });

// recurring_task_executions collection
db.recurring_task_executions.createIndex(
  { recurring_task_id: 1, scheduled_for: 1 },
  { unique: true }
);
```

---

## 8. Search & Aggregation Pipeline Redesign

### 8.1. Full-Text Search Without Elasticsearch
Instead of relying on costly external search clusters (OpenSearch/Elasticsearch):
- NextAction will use MongoDB’s built-in `$text` compound index or case-insensitive regex `$regex: term, $options: "i"` across denormalized fields.
- For free-tier efficiency, compound regex queries across indexed fields (`title`, `client.name`) guarantee zero additional infrastructure costs.

### 8.2. Dashboard & Report Aggregation Pipelines
The complex SQL `case()` aggregation in `dashboard_service.py` translates directly into a single `$facet` pipeline:

```javascript
db.tasks.aggregate([
  {
    $facet: {
      status_distribution: [
        { $group: { _id: "$status", count: { $sum: 1 } } }
      ],
      priority_distribution: [
        { $match: { status: { $in: ["pending", "in_progress"] } } },
        { $group: { _id: "$priority", count: { $sum: 1 } } }
      ],
      attention_metrics: [
        {
          $group: {
            _id: null,
            overdue: {
              $sum: {
                $cond: [{ $and: [{ $lt: ["$due_date", new Date()] }, { $in: ["$status", ["pending", "in_progress"]] }] }, 1, 0]
              }
            },
            near_max_attempts: {
              $sum: {
                $cond: [{ $gte: ["$attempt_count", { $subtract: ["$max_attempts", 1] }] }, 1, 0]
              }
            }
          }
        }
      ]
    }
  }
]);
```

---

## 9. Transaction & Consistency Analysis

- **Multi-Document ACID Transactions:** MongoDB Atlas Free Tier (M0) runs on a **3-node replica set**. MongoDB natively supports multi-document ACID transactions across replica sets (`client.start_session()`, `with session.start_transaction():`).
- **Atomic Operations Over Transactions:** Transactions introduce latency and lock overhead. Wherever possible, single-document atomic updates (e.g. `$inc`, `$set`, `$push` to embedded reminders/follow-ups) will be used to ensure sub-millisecond execution without distributed locks.
- **Audit Consistency:** When a task attempt or status change occurs, a transactional session commits both the task update and the `task_history` document.

---

## 10. Provider Free-Tier Research & Verification (₹0/Month)

All provider capabilities were investigated and verified under current active policies:

### 10.1. Database: MongoDB Atlas (M0 Free Cluster)
- **Monthly Cost:** **₹0 / $0 permanently free**
- **Storage:** **512 MB** fixed storage (sufficient for ~250,000 NextAction tasks and audit records).
- **RAM / vCPU:** Shared multi-tenant compute.
- **Connections:** Up to **500 concurrent connections** (more than adequate for FastAPI connection pool of 20–50).
- **Replica Set:** 3-node replica set with automatic primary failover.
- **Credit Card Required:** **NO** (Sign up with email/GitHub, zero payment info required).
- **Idle Behavior:** Clusters with 0 traffic for 60 consecutive days may be paused; auto-unpauses on user request or keepalive traffic.
- **Backups:** No automated cloud snapshots. Requires automated client-side `mongodump`.

### 10.2. Backend Hosting: Render Free Web Service
- **Monthly Cost:** **₹0 / $0 free tier**
- **Compute Allowance:** **750 free instance hours per month** (sufficient to run 1 service 24/7 all month).
- **RAM / vCPU:** 512 MB RAM, 0.1 vCPU.
- **Sleep Policy:** Automatically spins down after **15 minutes of inactivity**. Cold start wakes in ~45–60 seconds upon first HTTP request.
- **Credit Card Required:** **NO**.
- **Custom Domains & TLS:** Automated free Let's Encrypt certificates for custom domains (`api.nextaction.io`).
- **Rejected Alternatives:**
  - *Railway:* Free tier discontinued; requires paid Hobby subscription.
  - *Fly.io:* Requires credit card on file even for free allowances.
  - *Koyeb:* Imposes a **$29 pre-authorization hold** on credit cards during verification.

### 10.3. Frontend Hosting: Cloudflare Pages
- **Monthly Cost:** **₹0 / $0 permanently free**
- **Bandwidth:** **UNLIMITED, unmetered bandwidth** on global Anycast edge network.
- **Custom Domain & TLS:** Free custom domain (`app.nextaction.io`) with automated global TLS edge termination.
- **SPA Routing:** Native Single-Page Application fallback support via `_redirects` file (`/* /index.html 200`).
- **Credit Card Required:** **NO**.
- **Build Limits:** 500 build minutes/month (ample for Flutter Web release deployments).

### 10.4. Distributed Rate Limiter: Upstash Redis (Free Tier) + In-Memory Fallback
- **Monthly Cost:** **₹0 / $0 free tier**
- **Allowance:** **500,000 commands per month**, 256 MB data storage.
- **Credit Card Required:** **NO**.
- **Resilience:** If Upstash monthly limit is reached, NextAction’s verified sliding-window rate limiter automatically falls back to in-memory tracking with zero downtime.

### 10.5. Automated Scheduler: GitHub Actions Scheduled Cron / Cloudflare Workers
- **Monthly Cost:** **₹0 / $0 free tier**
- **Approach:** A GitHub Actions cron workflow (`.github/workflows/scheduler.yml`) executes every 15 minutes (`*/15 * * * *`):
  ```yaml
  name: Trigger Scheduler Evaluation
  on:
    schedule:
      - cron: '*/15 * * * *'
    workflow_dispatch:
  jobs:
    evaluate:
      runs-on: ubuntu-latest
      steps:
        - name: Call Scheduler API
          run: |
            curl -f -X POST "https://api.nextaction.io/api/v1/scheduler/evaluate" \
              -H "Authorization: Bearer ${{ secrets.SCHEDULER_API_SECRET }}"
  ```
- **Dual Benefit:**
  1. Guarantees deterministic evaluation of due reminders, overdue follow-ups, and recurring tasks.
  2. The 15-minute ping prevents the Render backend from spinning down during peak operational hours!

---

## 11. Concrete Zero-Cost Target Architecture (₹0/Month)

```
 [ Client Web Browser ]
         │
         │ HTTPS (Port 443)
         ▼
 ┌────────────────────────────────────────────────────────┐
 │ Cloudflare Pages (Free Tier - Global Anycast CDN)      │
 │   - URL: https://app.nextaction.io                     │
 │   - Static Hosting: Flutter Web Release Build (SPA)    │
 │   - SPA Fallback: /* -> /index.html (HTTP 200)         │
 │   - Bandwidth: Unlimited                               │
 └───────────────────────┬────────────────────────────────┘
                         │
                         │ HTTPS REST API Calls (/api/v1/*)
                         ▼
 ┌────────────────────────────────────────────────────────┐
 │ Render Free Web Service (750 Hours/Month Free)         │
 │   - URL: https://api.nextaction.io                     │
 │   - Runtime: FastAPI / Python 3.11                     │
 │   - TLS: Automated Let's Encrypt Managed TLS           │
 │   - Rate Limiter: Upstash Redis + In-Memory Fallback   │
 └──────────────┬──────────────────────────┬──────────────┘
                │                          │
   MongoDB Wire │ Protocol (TLS)           │ Redis RESP (TLS)
                ▼                          ▼
 ┌───────────────────────────┐  ┌───────────────────────────┐
 │ MongoDB Atlas (M0 Cluster)│  │ Upstash Redis (Free Tier) │
 │   - 512 MB Storage        │  │   - 500,000 Cmds / Month  │
 │   - 3-Node Replica Set    │  │   - 256 MB Storage        │
 │   - Cost: ₹0 / month      │  │   - Rate Limit Counters   │
 │   - Automated Failover    │  │   - Cost: ₹0 / month      │
 └──────────────┬────────────┘  └───────────────────────────┘
                │
                ▼ Client-side mongodump export
 ┌────────────────────────────────────────────────────────┐
 │ GitHub Actions Automated Backup & Scheduler Trigger    │
 │   - Cron every 15 min: Calls /scheduler/evaluate       │
 │   - Nightly Cron: mongodump -> GPG -> S3/Artifacts     │
 │   - Cost: ₹0 / month (Public or Free Actions Tier)     │
 └────────────────────────────────────────────────────────┘
```

---

## 12. Strategic Phased Migration Plan

To maintain strict stability and avoid breaking changes, the migration must occur across isolated, verified phases:

- **Phase 28: MongoDB Infrastructure & Connection Scaffolding**  
  Add `pymongo` / `motor`, create MongoDB connection manager, environment variables (`MONGODB_URI`), and verify Atlas M0 connection. (PostgreSQL remains active).
- **Phase 29: MongoDB Repository Layer & Schema Definitions**  
  Implement Pydantic document schemas and Repository classes for `users`, `tasks`, `notifications`, `clients`, `workflows`.
- **Phase 30: Service-Layer Migration (Dual-Engine Capability)**  
  Implement MongoDB-backed service implementations with feature-flag toggling (`DATABASE_ENGINE=postgres|mongodb`).
- **Phase 31: Authentication, Tokens & Security Migration**  
  Migrate user registration, password hashing, JWT claims, refresh-token rotation, and replay detection to MongoDB.
- **Phase 32: Notifications, Reminders & Scheduler Engine Migration**  
  Migrate calendar bounds, partial unique index deduplication, and scheduler sweep logic to MongoDB.
- **Phase 33: Dashboard, Reports & Aggregation Pipelines**  
  Migrate conditional count KPIs, time-series trends, and CSV exports to MongoDB `$facet` aggregation pipelines.
- **Phase 34: Flutter Web Integration & Cloudflare Pages Build**  
  Verify end-to-end integration between Flutter Web SPA and MongoDB-backed backend.
- **Phase 35: Full Regression Testing & Parity Verification**  
  Execute all unit, integration, and E2E test suites against MongoDB until achieving 100% parity with Phase 25 results.
- **Phase 36: Zero-Cost Production Deployment**  
  Deploy Flutter Web to Cloudflare Pages and FastAPI to Render; connect to MongoDB Atlas M0; verify live production operation at ₹0/month.

---

## 13. Risk Assessment & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **Render Cold Start Latency (45–60s)** | Initial user request after idle period experiences delay. | GitHub Actions scheduler pinging every 15 minutes keeps the service warm during operating hours. Flutter UI displays a clean loading spinner on initial cold start. |
| **Atlas 512 MB Storage Limit** | Storage exhaustion after substantial data creation. | Implement TTL indexes on `refresh_tokens` and archived notifications; purge completed tasks or export old audit logs via nightly backup. 512 MB accommodates ~250,000 documents. |
| **Accidental Data Inconsistency** | Lack of relational foreign keys could allow orphaned records. | Enforce integrity in Repository layer (e.g. cascading deletes handled in application logic); wrap multi-entity mutations in replica set transactions. |
| **Vendor Terms Change** | A free-tier provider alters terms. | Architecture is provider-neutral: Render can be replaced by Koyeb/HuggingFace Spaces; Cloudflare Pages can be replaced by GitHub Pages/Netlify. |

---

## 14. Conclusion & Next Steps

The assessment confirms that **a zero-cost (₹0/month) production architecture for NextAction is 100% technically feasible** by pairing:
1. **Cloudflare Pages** for frontend SPA delivery.
2. **Render Free Tier** for FastAPI compute.
3. **MongoDB Atlas M0** for 3-node replica set persistence.
4. **Upstash Redis + In-Memory Fallback** for sliding-window rate limiting.
5. **GitHub Actions** for scheduling and keepalive.

**PostgreSQL remains completely operational and untouched.** Phase 28 may proceed when scheduled.
