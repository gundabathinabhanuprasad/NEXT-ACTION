# NextAction Production Architecture Specification

## 1. Overview & Architectural Principles

NextAction is engineered as a cloud-neutral, containerized 3-tier/4-tier application designed for high security, horizontal scalability, resilience, and operational observability. The architecture decouples the frontend client presentation layer from the API backend and persistence layers while enforcing defense-in-depth at every network boundary.

```
+-------------------------------------------------------------------------+
|                        Internet / Client Devices                        |
|   (Flutter Web, Flutter Android, Modern Desktop & Mobile Browsers)      |
+-------------------------------------------------------------------------+
                                     |
                                     | HTTPS (TLS 1.2 / 1.3, HSTS)
                                     v
+-------------------------------------------------------------------------+
|                    Public Edge / Reverse Proxy Layer                    |
|                        (Nginx / Caddy / Traefik)                        |
|   - TLS Termination & HTTP -> HTTPS 301 Redirect                        |
|   - Static Asset Hosting & SPA Routing (Flutter Web WASM/JS)            |
|   - Security Headers (HSTS, CSP, X-Frame-Options, X-Content-Type)       |
|   - Request ID Generation / Forwarding (X-Request-ID)                   |
|   - Upstream Reverse Proxying & Keepalive Pooling                       |
+-------------------------------------------------------------------------+
                                     |
                                     | HTTP (Private Internal Network)
                                     v
+-------------------------------------------------------------------------+
|                  Application Tier (FastAPI Backend)                     |
|   - Uvicorn Multi-Worker Process Model (Non-root 'appuser')             |
|   - Stateless REST API Engine                                           |
|   - JWT Claims & Expiration Enforcement                                |
|   - Server-Side Revocable Refresh Tokens & Replay-Attack Detection      |
|   - Role & Actor-Identity Authorization Boundaries                      |
|   - Sliding-Window Rate Limiting (Distributed Redis / In-Memory Fallback|
|   - Structured Correlation-ID Logging (JSON)                            |
+-------------------------------------------------------------------------+
                   |                                       |
                   | SQL (SQLAlchemy + asyncpg/psycopg2)    | Redis Protocol
                   | Connection Pool with SSL Mode         | RESP (tcp/6379)
                   v                                       v
+------------------------------------+   +--------------------------------+
|       Relational Database Tier     |   |     Distributed Cache Tier     |
|         (PostgreSQL 16+)           |   |           (Redis 7+)           |
|  - ACID Persistence                |   |  - Sliding-Window Rate Limits  |
|  - Alembic Schema Migrations       |   |  - Session / Replay Tracking   |
|  - Strict Foreign Key Integrity    |   |  - Ephemeral Token Blacklist   |
|  - Point-in-Time Recovery (WAL)    |   |  - Low-Latency In-Memory State |
+------------------------------------+   +--------------------------------+
                   |
                   v
+-------------------------------------------------------------------------+
|                  Storage Tier & Backup Orchestration                    |
|  - Automated WAL-E / pg_dump encrypted snapshots                        |
|  - Provider-neutral object storage (S3 / GCS / Azure Blob / MinIO)      |
+-------------------------------------------------------------------------+
```

---

## 2. Component Taxonomy: Mandatory vs. Optional

| Component | Role | Tier | Mandatory / Optional | Fail-Open / Fail-Closed |
| :--- | :--- | :--- | :--- | :--- |
| **Reverse Proxy (Nginx)** | TLS termination, SPA hosting, security headers, request ID injection | Edge | **Mandatory** | Fail-Closed (no unencrypted exposure) |
| **FastAPI Backend** | Application business logic, authentication, REST API | Application | **Mandatory** | Fail-Closed |
| **PostgreSQL 16+** | Persistent relational storage, task graphs, audit trails | Persistence | **Mandatory** | Fail-Closed |
| **Flutter Web Assets** | Compiled Single-Page Application (HTML5, JS, CanvasKit/Skwasm) | Frontend | **Mandatory** | Static file serving |
| **Redis 7+** | Distributed rate limiting, cache, future background tasks | In-Memory | **Optional (Production Recommended)** | **Graceful Fallback** to In-Memory rate limiting if unreachable |
| **Backup Runner** | Periodic database dumps, WAL archiving, integrity verification | Storage | **Mandatory (Production)** | Out-of-band operational alert |

---

## 3. End-to-End Request & Data Flows

### 3.1. Public Client Request Flow
1. **Client DNS & TLS Resolution**:
   - The browser resolves `app.nextaction.io` and connects via TCP port 443.
   - If port 80 (HTTP) is contacted, the Reverse Proxy immediately responds with `301 Moved Permanently` to `https://...`.
   - The TLS handshake establishes TLS 1.2 or 1.3 with high-strength cipher suites.
2. **Reverse Proxy Processing**:
   - Nginx assigns or preserves `X-Request-ID` (UUIDv4).
   - If requesting static SPA assets (`/`, `/index.html`, `/main.dart.js`, `/assets/*`), Nginx serves from disk with optimal `Cache-Control` headers.
   - If requesting `/api/*`, `/health`, or `/ready`, Nginx proxies the request to the upstream FastAPI container (`http://backend:8000`) over a private, non-routable internal Docker/VPC network.
   - Nginx injects standard proxy headers: `X-Forwarded-For`, `X-Forwarded-Proto: https`, `X-Forwarded-Host`, `X-Real-IP`.
3. **Application Layer Ingestion**:
   - FastAPI receives the request behind `TrustedHostMiddleware` and `CorrelationIdMiddleware`.
   - The correlation ID is attached to the request context and logged with every event.
   - Route rate limits are evaluated against Redis (falling back to memory if Redis is unavailable).
   - JWT tokens are validated against ECDSA/Ed25519/HMAC-SHA256 signature algorithms, rejecting expired tokens or inactive user claims.
4. **Database Querying**:
   - SQLAlchemy obtains a connection from the pre-warmed connection pool (`DB_POOL_SIZE=10`, `DB_MAX_OVERFLOW=20`).
   - Queries are executed using parameterized SQL. Connection timeouts and statement recycles prevent zombie connections.
5. **Response Pipeline**:
   - JSON response models serialize domain objects (stripping sensitive internal columns).
   - Nginx delivers the response with security headers (`Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`).

---

## 4. Authentication & Token Lifecycle Flow

NextAction implements a zero-trust, rotating dual-token authentication system:

```
[Flutter Client]              [Nginx Proxy]               [FastAPI API]              [PostgreSQL / Redis]
       |                            |                           |                              |
  1. POST /api/v1/auth/login ------>|-------------------------->|                              |
       |  (email, password)         |                           |-- Verify Argon2/bcrypt ----->|
       |                            |                           |-- Issue Access Token (1 hr)  |
       |                            |                           |-- Issue Refresh Token (7 d) -|
       |                            |                           |-- Store SHA-256 Hash ------->|
       |<---------------------------|<-- 200 OK + Tokens -------|                              |
       |                                                                                       |
  2. GET /api/v1/tasks (Bearer) --->|-------------------------->|                              |
       |<---------------------------|<-- 200 OK (Tasks) --------|-- Validate JWT Claim --------|
       |                                                                                       |
  3. [Access Token Expires]                                                                    |
       |                                                                                       |
  4. GET /api/v1/tasks (Expired) -->|-------------------------->|                              |
       |<---------------------------|<-- 401 Unauthorized ------|-- ExpiredSignatureError -----|
       |                                                                                       |
  5. POST /api/v1/auth/refresh ---->|-------------------------->|                              |
       |  (refresh_token)           |                           |-- Lookup Hash in DB -------->|
       |                            |                           |-- Verify Active & Unexpired -|
       |                            |                           |-- Issue NEW Access Token ----|
       |                            |                           |-- Rotate NEW Refresh Token ->|
       |                            |                           |-- Revoke Old Token --------->|
       |<---------------------------|<-- 200 OK (New Pair) -----|                              |
       |                                                                                       |
  6. Retry GET /api/v1/tasks ------>|-------------------------->|-- Success 200 OK ------------|
       |                                                                                       |
  7. [Replay Attack Scenario: Attacker uses revoked Refresh Token]                             |
       |-- POST /auth/refresh ----->|-------------------------->|-- Detect Token Already Used! |
       |   (re-used old token)      |                           |-- SECURITY EVENT: Replay! ---|
       |                            |                           |-- REVOKE ENTIRE FAMILY ----->|
       |<---------------------------|<-- 401 Unauthorized ------|   (Invalidates all sessions) |
```

---

## 5. Notification & Scheduler Flow

The NextAction scheduler executes state machine transitions, recurring task generators, and automated reminder broadcasts:
1. **In-Process vs. Worker Architecture**:
   - For single-container deployments, the scheduler runs as a managed FastAPI lifecycle background thread.
   - For multi-replica production clusters, the scheduler triggers tasks via Redis locks or scheduled triggers (e.g. pg_cron, Celery Beat, or an external periodic HTTP trigger) to prevent duplicate runs.
2. **Actor Scoping & Tenancy Isolation**:
   - All scheduled tasks and notifications execute within explicit user tenancy boundaries.
   - Notification delivery checks user preferences and skips inactive accounts.

---

## 6. Database & Backup Architecture Flow

1. **Transactional Integrity & Pooling**:
   - Production PostgreSQL runs with `wal_level = replica`, `max_connections = 100`, and `statement_timeout = 30000ms`.
   - FastAPI configures SQLAlchemy engine pooling with `pool_pre_ping=True` and `pool_recycle=1800` to transparently survive database restarts or firewall connection drops.
2. **Backup Pipeline**:
   - Automated continuous archiving captures write-ahead logs (WAL) to cold object storage.
   - Daily full backups run via `pg_dump` with custom compressed format, validated with automated checksums (`SHA-256`) and cataloged with metadata (`backup_metadata.json`).
   - Automated restore rehearsal verifies recovery time objectives (RTO < 30 mins) and recovery point objectives (RPO < 1 hour).

---

## 7. External Integration Boundaries & Network Security

1. **Private Subnets & Firewalls**:
   - Only Ports 80 and 443 are exposed to the public Internet on the Reverse Proxy.
   - The FastAPI backend port (8000), PostgreSQL port (5432), and Redis port (6379) MUST NOT be bound to public interfaces.
2. **Outbound Network Filtering**:
   - Outbound egress from application containers is restricted to verified external endpoints (e.g., mail relay, notification services, managed database endpoints).
3. **CORS & Origin Hardening**:
   - Wildcard CORS (`*`) is strictly rejected by application configuration when `ENVIRONMENT=production`.
   - The browser client connects only through approved origins declared in `CORS_ORIGINS`.
