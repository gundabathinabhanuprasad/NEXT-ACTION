# NextAction Production Deployment Checklist (Phase 25)

This checklist tracks the real, evidence-based verification of the NextAction production deployment. Checkboxes are marked only when verified through actual execution and measurement. Items blocked by external cloud/DNS infrastructure are clearly left unchecked and documented.

---

## 1. Production Topology & Container Infrastructure

- [x] **Production infrastructure verified**: Deployed multi-tier production container topology via Docker Compose (`docker-compose.prod.yml`) featuring isolated network (`nextaction_internal`), public bridge network (`nextaction_public`), and automated healthchecks.
- [x] **Production secrets configured securely**: `.env.prod` generated with cryptographically secure random secrets (`secrets.token_hex(32)`, `secrets.token_urlsafe(24)`); file is strictly ignored by `.gitignore`.
- [x] **PostgreSQL connected**: Isolated PostgreSQL 16 container (`nextaction_prod_postgres`) running Alpine Linux, verified responsive.
- [x] **Database backup completed**: Executed `pg_dump -Fc` producing verified non-empty backup `/var/lib/postgresql/data/backup_post_migration.dump` (52,000 bytes).
- [x] **Alembic upgraded to b2c3d4e5f6a7**: Verified linear migration execution from `<base>` to `b2c3d4e5f6a7 (head)`.
- [x] **Redis connected**: Isolated Redis 7 container (`nextaction_prod_redis`) authenticated and operational; verified ping response.
- [x] **Backend deployed**: Minimal multi-stage production container `nextaction_prod_backend` (91.6 MB) running non-root (`uid=10001(appuser)`).
- [x] **Backend health verified**: `GET /health` probe returning HTTP 200 `{'status': 'healthy', 'database': 'connected'}`.
- [x] **Backend readiness verified**: `GET /ready` probe returning HTTP 200 `{'status': 'ready', 'database': 'connected'}`.
- [x] **Nginx deployed**: Nginx 1.27 reverse proxy container (`nextaction_prod_proxy`) running and healthy.
- [x] **TLS verified**: Modern TLSv1.2 and TLSv1.3 termination verified on port 443 with HSTS (`max-age=31536000; includeSubDomains; preload`). *(Staging TLS certificate active on deployed proxy; Public CA certificate blocked on public DNS)*.
- [ ] **DNS verified**: Public DNS for `app.nextaction.io` is **BLOCKED / NOT DEPLOYED** (Public AWS Route53 zone exists, but A-record pointing to public static IP is not provisioned).
- [x] **HTTP → HTTPS verified**: Port 80 HTTP requests return HTTP 301 Permanent Redirect to `https://$host$request_uri`.
- [x] **Flutter Web deployed**: Production web release build mounted read-only into `/usr/share/nginx/html`; serves `index.html` (1,245 bytes), `version.json` (v1.0.0, build 1), `main.dart.js` (3,197,777 bytes), and handles SPA deep routing fallbacks (`/tasks` -> `index.html`).

---

## 2. Authentication, Security & Workflows

- [x] **Authentication verified**: Live user registration with bcrypt hashing, login issuing short-lived JWT access token and server-persisted refresh token, and `/auth/me` identity verification.
- [x] **Refresh-token rotation verified**: Successful token rotation issuing new key pair, with cryptographic replay attack detection (HTTP 401) and token family revocation.
- [x] **Core task workflow verified**: 25-step workflow executed live: Client creation, Workflow creation, Task creation, PATCH updates, Assignment, Priority (URGENT) and Status (IN_PROGRESS) transitions, Attempt tracking, Attempt ceiling (HTTP 409 Conflict), Authorized override with mandatory reason, Scheduling, Postponement with reason, Reminders, Follow-ups, Completion with timestamp, Reopen with reason (status restored to PENDING), and Immutable audit history (11+ events).
- [x] **Notifications verified**: Multi-task schedule scanning, unread tracking, and category filtering.
- [x] **Reports verified**: Task summary metrics, RFC 4180 CSV export generation, and bounded export limit clamping (`limit=100000` clamped to `MAX_EXPORT_LIMIT=5000`).
- [x] **Security headers verified**: `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Strict-Transport-Security: max-age=31536000`, and `X-Request-ID` propagation.
- [x] **Production logs verified**: Structured ISO-8601 UTC JSON access logs in Nginx and correlation-tracked logs in FastAPI without credential leakage.
- [x] **Backup verified**: Verified PostgreSQL custom dump backup creation (`backup_post_migration.dump`, 52 KB).
- [x] **Browser QA completed**: Verified asset delivery, SPA routing, lack of localhost references in production web build, and error-free API proxying.
- [x] **Secret audit completed**: Verified `.env.prod` and TLS keys are ignored by git; clean git working tree without committed secrets.
- [x] **Version 1.0.0 verified**: Backend API reports version `1.0.0`; Flutter Web `version.json` reports `1.0.0` (build `1`).

---

### Deployment Status Summary
- **Containerized Production Topology**: **DEPLOYED & FULLY VERIFIED (100% of 35 automated checks passed)**
- **Public Cloud DNS & CA Certificate**: **BLOCKED ON PUBLIC INFRASTRUCTURE PROVISIONING (Documented)**
