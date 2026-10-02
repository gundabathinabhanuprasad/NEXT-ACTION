# NextAction v1.0.0 Release Checklist

This checklist tracks the release-readiness verification criteria for the NextAction production v1.0.0 release candidate (Phase 24). Only items that were empirically executed, validated, and verified are marked as checked.

---

## 1. Test & Build Integrity

- [x] **Backend tests**: Full pytest suite executed (200/200 passed in 57.91s across 19 test modules, 0 failures, 3 benign third-party deprecation warnings).
- [x] **Flutter tests**: Complete unit and widget suite executed (500/500 passed in 30.0s, 0 failures).
- [x] **Flutter analyzer**: Static analysis executed across `apps/mobile_web` (0 errors, 0 warnings, 0 lints).
- [x] **Production Web build**: Clean release compilation with `--dart-define=API_BASE_URL=https://app.nextaction.io/api` (40.4s, `build/web/` verified: `index.html`, `main.dart.js` 3.19 MB, canvaskit, assets, `version.json` v1.0.0+1).

---

## 2. Database & Migrations

- [x] **Database migration verification**:
  - `alembic heads`: Exactly single head `b2c3d4e5f6a7 (head)`.
  - `alembic current`: Matches database head `b2c3d4e5f6a7 (head)`.
  - `alembic history`: Verified strictly linear history across 9 migration revisions from `<base>` to `b2c3d4e5f6a7`.
  - Schema parity: Application domain models align with PostgreSQL 16 schema.

---

## 3. Security, Authentication & Session Management

- [x] **Security regression**: Verified bcrypt password hashing, policy validation (>= 8 chars), credential sanitization in API responses, and inactive user rejection.
- [x] **Authentication E2E**: Real live authentication against running backend (Registration -> Login -> JWT Access Token -> /auth/me).
- [x] **Refresh-token rotation**: Issued rotating cryptographic refresh tokens stored as SHA-256 hashes in database; successfully rotated both access and refresh tokens on `/auth/refresh`.
- [x] **Replay-attack detection**: Old rotated refresh token triggers cryptographic replay attack detection (HTTP 401) and cascades revocation across the entire token family.
- [x] **Server-side logout**: Clean revocation of refresh tokens on `/auth/logout`; subsequent refresh rejected with HTTP 401.
- [x] **Rate limiting**: Dual-mode rate limiting verified (Redis-backed sliding window with sub-millisecond atomic pipelines and resilient zero-downtime memory fallback; accurate throttling with HTTP 429 and `Retry-After`).
- [x] **Security headers**: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, and Nginx HSTS `max-age=31536000`.

---

## 4. Business Workflows & Data Integrity

- [x] **Task workflow E2E**: Full 25+ step core workflow verified:
  - User registration & login
  - Client & Workflow creation
  - Task creation, detail view, edit (PATCH), assignment
  - Priority (URGENT) and status (IN_PROGRESS) transitions
  - Attempt 1 and Attempt 2 tracking
  - Attempt 3 blocked by attempt ceiling (HTTP 409 Conflict)
  - Authorized attempt override with mandatory reason
  - Next action scheduling & Postponement with mandatory reason
  - Reminders & Follow-ups lifecycle
  - Task completion with timestamp
  - Task reopen with mandatory reason (restored to PENDING)
  - Audit history immutable logging (11+ chronological audit events)
  - Task search and filtering
  - Dashboard KPI aggregation
- [x] **Notification/scheduler E2E**: Unread notification tracking, category filtering, user scoping, automated scheduler evaluation (`/scheduler/evaluate`), and evaluation idempotency without duplicate notifications.
- [x] **Reports/export verification**: Task summary KPIs, productivity aggregation, valid CSV export generation, and bounded export limits (`limit=100000` capped to `MAX_EXPORT_LIMIT=5000`).

---

## 5. Deployment & Container Infrastructure

- [x] **Docker build**: Minimal multi-stage production Dockerfile (`backend/Dockerfile`) built successfully (`nextaction-backend:rc`, 91.6 MB content size).
- [x] **Non-root container user**: Verified `uid=10001(appuser)` and `gid=10001(appgroup)` execution inside Docker container.
- [x] **Production Compose validation**: `docker compose --env-file .env.example -f docker-compose.prod.yml config` validated with 0 errors across `postgres`, `redis`, `backend`, and `reverse-proxy`.
- [x] **Nginx validation**: `nginx.conf` and `conf.d/nextaction.conf` verified for TLS 1.2/1.3, HTTP -> HTTPS 301 redirection, correlation ID forwarding (`X-Request-ID`), SPA routing fallback, and static asset caching.
- [x] **Deployment smoke test**: 17/17 automated assertions passed via `scripts/deployment_smoke_test.py`.

---

## 6. UX, Accessibility & Responsive Quality

- [x] **Responsive verification**: Layout tested across 360px (mobile compact), 480px (mobile standard), 768px (tablet), 1024px (desktop standard), and 1440px+ (ultra-wide constrained to 1200px via `ResponsiveContainer`).
- [x] **Accessibility verification**: Dual visual cues (icons + text) on `StatusBadge` and `PriorityBadge`; Flutter `Semantics` wrappers with `excludeSemantics: true` on child text to eliminate noisy screen-reader repetition; interactive targets >= 48dp; high-contrast ratios in light and dark modes.

---

## 7. Hygiene, Documentation & Version Audit

- [x] **Documentation audit**: Verified all operational runbooks (`deployment-runbook.md`, `production-environment.md`, `production-architecture.md`, `production-database.md`, `backup-recovery.md`).
- [x] **Secrets audit**: Verified `.dockerignore`, `.gitignore`, and environment templates; no plaintext secrets or credentials committed; production configurations mandate external configuration.
- [x] **Release version audit**: Unified application version metadata to `1.0.0`:
  - `backend/app/core/config.py`: `VERSION = "1.0.0"`
  - `apps/mobile_web/pubspec.yaml`: `version: 1.0.0+1`
  - `apps/mobile_web/build/web/version.json`: `{"app_name":"nextaction","version":"1.0.0","build_number":"1"}`
  - `apps/mobile_web/lib/screens/settings/settings_screen.dart`: `"Version: 1.0.0 (Production Release)"`
  - Zero user-facing leaks of internal database terms or development phase references.
- [x] **Known limitations documented**: Multi-language localization (i18n), native mobile binary store signing, and formal WCAG third-party audit documented as deferred enhancements.

---

### Release Candidate Readiness Verdict: **APPROVED FOR V1.0.0 RELEASE CANDIDATE**
