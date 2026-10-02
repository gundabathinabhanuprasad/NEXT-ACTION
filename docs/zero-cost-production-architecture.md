# NextAction Zero-Cost Production Architecture Specification

**Monthly Hosting Cost:** **₹0 / $0 (Permanently Free-Tier Operating Model)**  
**Application Target:** NextAction v1.0.0 (Production Release)  
**Database Architecture:** MongoDB Atlas Free Tier (M0 3-Node Replica Set)  
**Edge & Compute:** Cloudflare Pages (Frontend) + Render Free Web Service (Backend)

---

## 1. High-Level Architecture Diagram

```
                              [ User / Client Devices ]
                                         │
                                         │ HTTPS (TLS 1.3)
                                         ▼
                     ┌───────────────────────────────────────┐
                     │           Cloudflare Pages            │
                     │  (Global Anycast Edge CDN - ₹0/month) │
                     │  - Custom Domain: app.nextaction.io   │
                     │  - Flutter Web Production SPA Build   │
                     │  - Unlimited Global Bandwidth         │
                     │  - Single Page App Rewrite (/* 200)   │
                     └───────────────────┬───────────────────┘
                                         │
                                         │ HTTPS REST API Requests (/api/v1/*)
                                         ▼
                     ┌───────────────────────────────────────┐
                     │        Render Free Web Service        │
                     │     (Python 3.11 / FastAPI Engine)    │
                     │  - Custom Domain: api.nextaction.io   │
                     │  - 750 Free Instance Hours / Month    │
                     │  - Non-root Execution Environment     │
                     │  - Automated TLS Certificate (ACME)   │
                     └───────┬───────────┬───────────┬───────┘
                             │           │           │
            MongoDB Wire TLS │           │ Redis TLS │ Inbound HTTPS
                             ▼           ▼           ▲
┌──────────────────────────────┐ ┌───────────────┐   │
│   MongoDB Atlas Free Tier    │ │ Upstash Redis │   │
│     (M0 3-Node Replica Set)  │ │  (Free Tier)  │   │
│ - Storage: 512 MB Free       │ │ - 500k Cmds/Mo│   │
│ - Connections: Up to 500     │ │ - 256 MB RAM  │   │
│ - Multi-Document Transaction │ │ - Rate Limits │   │
│ - 99.9% Uptime SLA           │ └───────┬───────┘   │
└──────────────┬───────────────┘         │           │
               │ (Keepalive & Backup)    │ Fallback  │
               │                         ▼           │
               │               ┌───────────────────┐ │
               │               │ In-Memory Sliding │ │
               │               │  Window Fallback  │ │
               │               └───────────────────┘ │
               │                                     │
               ▼ Nightly mongodump                   │ 15-Minute Trigger
┌────────────────────────────────────────────────────┴───────────────┐
│              GitHub Actions Automation & Keepalive                 │
│  - Scheduled Cron (`*/15 * * * *`): POST /scheduler/evaluate       │
│  - Nightly Backup: Automated mongodump export to encrypted archive │
│  - Cost: ₹0 / month                                                │
└────────────────────────────────────────────────────────────────────┘
```

---

## 2. Component Taxonomy & Free-Tier Verification

| Architectural Role | Service Provider | Plan / Tier | Verified Limits | Monthly Cost |
|---|---|---|---|---|
| **Frontend SPA Hosting** | **Cloudflare Pages** | Free Tier | Unlimited bandwidth, custom domain, automated edge SSL | **₹0** |
| **Backend API Engine** | **Render** | Free Web Service | 750 instance hours/month, 512 MB RAM, 0.1 vCPU | **₹0** |
| **Document Database** | **MongoDB Atlas** | M0 Sandbox Cluster | 512 MB storage, 3-node replica set, 500 connections | **₹0** |
| **Distributed Rate Limiter** | **Upstash Redis** | Free Tier | 500,000 commands/month, 256 MB data storage | **₹0** |
| **Rate Limit Fallback** | **FastAPI In-Memory** | Native Python | Embedded in-process sliding window limiter | **₹0** |
| **Automated Scheduler** | **GitHub Actions** | Free Tier | 2,000 free workflow minutes/month (Public: unlimited) | **₹0** |
| **DNS & Edge Security** | **Cloudflare DNS** | Free Tier | Managed DNS, DDoS protection, edge caching | **₹0** |
| **TLS Certificates** | **Cloudflare / Let's Encrypt** | Automated Free | Zero-touch SSL/TLS certificate management | **₹0** |
| **Total Production Cost** | | | | **₹0 / month** |

---

## 3. End-to-End Operational Flows

### 3.1. General Data Flow (Read / Write Lifecycle)

```
[Browser] ──(1. Get Tasks)──> [Cloudflare Pages] ──(Serve SPA)──> [Flutter Web]
                                                                        │
   ┌────────────────────────────────────────────────────────────────────┘
   ▼
[Flutter Web] ──(2. GET /api/v1/tasks?status=pending)──> [Render API Engine]
                                                               │
   ┌───────────────────────────────────────────────────────────┴─────────────┐
   ▼                                                                         ▼
[Check Rate Limit] ──(Upstash Redis)                                  [Validate JWT]
   │ (Allowed)                                                               │
   └───────────────────────────────────┬─────────────────────────────────────┘
                                       ▼
                       [MongoDB Atlas: db.tasks.find()]
                        - Indexed query on { status: 1 }
                        - Denormalized client/workflow
                                       │
                                       ▼ (BSON Document Stream)
                       [FastAPI Pydantic v2 Serialization]
                                       │
                                       ▼ (JSON Payload)
[Browser] <──(200 OK Array of Task Objects)───────────────────────────────────┘
```

### 3.2. Authentication & Refresh Token Rotation Flow

```
1. Registration & Login:
   Client POST /auth/login { email, password }
     -> API fetches User from MongoDB
     -> Verifies Bcrypt hash ($2b$12)
     -> Generates JWT Access Token (60 min expiry)
     -> Generates High-Entropy Refresh Token (SHA-256 stored in `refresh_tokens`)
     -> Returns { access_token, refresh_token }

2. Token Rotation (Single-Use Guarantee):
   Client POST /auth/refresh { refresh_token }
     -> API hashes incoming token
     -> Searches `refresh_tokens` collection
     ├── Case A: Token is valid and is_revoked == false:
     │     -> Atomically sets is_revoked = true, revoked_at = now
     │     -> Generates new access token and new refresh token
     │     -> Returns updated key pair
     │
     └── Case B: Token was ALREADY revoked (Replay Attack Detected!):
           -> Adversary intercepted old token
           -> API immediately executes:
              db.refresh_tokens.updateMany({ user_id: uid }, { $set: { is_revoked: true } })
           -> Invalidates ALL sessions for that user across all devices
           -> Returns HTTP 401 Unauthorized ("Replay detected; sessions terminated")
```

### 3.3. Automated Scheduler Flow (15-Minute Keepalive & Evaluation)

```
[GitHub Actions Cron Workflow]
           │
           │ Triggers every 15 minutes (`*/15 * * * *`)
           ▼
[cURL Request to Render Backend]
   Header: Authorization: Bearer <SCHEDULER_SECRET>
   Path:   POST https://api.nextaction.io/api/v1/scheduler/evaluate
           │
           ├─> (Side-Effect: Keeps Render service warm, avoiding cold starts)
           ▼
[FastAPI Scheduling Engine]
   1. Evaluate Due Reminders:
      - Queries `tasks` where `reminders.remind_at <= now` and `is_sent == false`
      - Dispatches in-app notification to `notifications` collection
      - Marks reminder `is_sent = true` atomically
   2. Evaluate Due / Overdue Follow-ups:
      - Queries `tasks` where `follow_ups.scheduled_at <= now` and `completed_at == null`
      - Creates deduplicated notification
   3. Evaluate Overdue Tasks:
      - Compares `due_date < now` for open tasks (`pending`, `in_progress`)
   4. Evaluate Recurring Tasks:
      - Checks `recurring_tasks` where `next_run_at <= now` and `is_active == true`
      - Verifies idempotency against `recurring_task_executions` unique index
      - Generates new task instance and advances `next_run_at`
```

### 3.4. Notification Delivery & Deduplication Flow

```
[Task Event or Scheduler]
           │
           ▼
[Check User Preferences (Embedded in user.settings)]
   - Is `notify_reminder_due` enabled?
   - Is `notify_task_overdue` enabled?
   ├── If disabled: Suppress creation (Zero overhead)
   └── If enabled:
           │
           ▼
   [Generate Deduplication Key]
   e.g. "reminder:task_123:reminder_456:2026-09-30"
           │
           ▼
   [Atomic MongoDB Insert to `notifications`]
   Index: { user_id: 1, dedup_key: 1 } (UNIQUE, partial where dedup_key != null)
   ├── First execution: Document created -> Unread notification ready for user
   └── Duplicate execution: MongoDB throws DuplicateKeyError (11000)
         -> Caught cleanly by Service Layer as idempotent no-op (Zero duplicates)
```

### 3.5. Automated Backup & Disaster Recovery Flow

```
[GitHub Actions Scheduled Backup Job (Nightly at 03:00 UTC)]
           │
           ▼
[Runner initializes mongodump utility]
   - Connects to MongoDB Atlas M0 via TLS URI string
   - Executes: mongodump --uri="$MONGODB_URI" --gzip --archive=nextaction_prod_backup.gz
           │
           ▼
[Integrity Check]
   - Verifies archive size > 5,000 bytes
           │
           ▼
[GPG Symmetric Encryption]
   - Encrypts archive using AES-256 with repository backup secret
           │
           ▼
[Off-Site Storage Upload]
   - Uploads encrypted archive to GitHub Artifacts (90-day retention)
     and/or free Cloudflare R2 object storage (10 GB free permanently)
```

---

## 4. Cold Start & Inactivity Mitigation Strategy

Because Render’s free tier spins down after 15 minutes of inactivity:
1. **The 15-Minute Keepalive**: The GitHub Actions scheduler cron runs every 15 minutes, sending a lightweight keepalive ping that prevents Render from sleeping during critical working hours.
2. **Graceful Client Reconnection**: The Flutter Web frontend implements an exponential backoff retry interceptor in `ApiClient`. If a request encounters a cold start (HTTP 502/504 while waking), the client displays a non-intrusive status banner (*"Connecting to service..."*) and retries automatically until the server responds.

---

## 5. Architectural Verification & Guarantees

- **No AWS EC2:** Removed completely from production architecture.
- **No Billable Cloud Services:** Every tier is independently verified as ₹0/month without hidden traps.
- **No Credit Card Required:** Neither Render, Cloudflare Pages, nor MongoDB Atlas require payment information.
- **Full Business Logic Preservation:** Attempts ceiling, override reasons, postponement tracking, audit histories, and refresh-token rotation are 100% supported.
