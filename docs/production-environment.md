# NextAction Production Environment & Secrets Management Specification

## 1. Secrets Management Philosophy & Principles

NextAction enforces rigorous separation of configuration from code (The Twelve-Factor App: Factor III). In all staging and production deployments:
1. **Zero Secret Persistence in Git**: No production passwords, private keys, database URLs with embedded credentials, or API tokens may ever be committed to source control or container layers.
2. **Runtime Injection**: Secrets are injected at container runtime via secure orchestrator mechanisms (Docker Secrets, Kubernetes Secrets, HashiCorp Vault, AWS Secrets Manager, or Google Secret Manager).
3. **Log Sanitization**: Application log formatters, traceback generators, and reverse proxies explicitly strip `Authorization`, `Cookie`, `Set-Cookie`, `refresh_token`, and database connection strings containing credentials.
4. **Environment Isolation**: Separate credentials, databases, and encryption keys MUST be provisioned for each deployment tier (`development`, `test`, `staging`, `production`).

---

## 2. Environment Taxonomy

| Tier | Purpose | Database | Rate Limiting | Docs / OpenAPI | Host / CORS Policy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`development`** | Local developer workstation | Local Docker Postgres | In-memory or local Redis | Enabled (`/docs`, `/redoc`) | Localhost & 127.0.0.1 origins |
| **`test`** | Automated CI / test runners | Ephemeral test DB | Rate limits bypassed | Disabled | Local mock hosts |
| **`staging`** | Pre-production validation | Isolated RDS / Cloud SQL | Redis cluster | Optional (behind auth) | Explicit staging domain |
| **`production`** | Live end-user traffic | Managed HA PostgreSQL | Distributed Redis | Strictly Disabled | Explicit production FQDN only |

---

## 3. Production Environment Variables Reference

Below is the definitive catalog of all environment variables supported and enforced by the NextAction backend.

### 3.1. Core Application & Server Runtime

| Variable Name | Purpose | Required / Optional | Production Example / Placeholder | Security Notes |
| :--- | :--- | :--- | :--- | :--- |
| `ENVIRONMENT` | Defines deployment environment profile | **Required** | `production` | Enables strict production guardrails (blocks wildcard CORS, disables interactive docs). |
| `LOG_LEVEL` | Logging threshold | Optional (default: `INFO`) | `INFO` or `WARNING` | Never set to `DEBUG` in production to prevent leaking payload data. |
| `DOCS_ENABLED` | Controls `/docs` and `/redoc` Swagger endpoints | Optional (default: `false` in prod) | `false` | MUST remain `false` in production to prevent API schema enumeration. |
| `REQUEST_TIMEOUT_SECONDS` | Server-side request execution timeout | Optional (default: `30`) | `30` | Prevents slowloris and hung query resource exhaustion. |

### 3.2. Cryptographic Security & Tokens

| Variable Name | Purpose | Required / Optional | Production Example / Placeholder | Security Notes |
| :--- | :--- | :--- | :--- | :--- |
| `SECRET_KEY` | Symmetric key for HMAC signing of access JWTs | **Required** | `<64-byte-hex-encoded-cryptographically-random-key>` | Generate with `openssl rand -hex 32`. Changing this key invalidates all active JWT sessions. |
| `ALGORITHM` | JWT signing algorithm | Optional (default: `HS256`) | `HS256` | Strictly enforced by pyjwt; algorithm confusion attacks are blocked. |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Access token time-to-live | Optional (default: `60`) | `60` | Kept short-lived to minimize impact if an access token is intercepted. |
| `REFRESH_TOKEN_EXPIRE_DAYS` | Server-persisted refresh token validity | Optional (default: `7`) | `7` | Rotating; stored as SHA-256 hashes server-side. |

### 3.3. Database Connectivity & Connection Pooling

| Variable Name | Purpose | Required / Optional | Production Example / Placeholder | Security Notes |
| :--- | :--- | :--- | :--- | :--- |
| `DATABASE_URL` | Complete SQLAlchemy database connection URI | **Required** | `postgresql+psycopg2://appuser:STRONG_PASSWORD@db.internal:5432/nextaction_prod` | Must use a dedicated unprivileged user (`appuser`), never `postgres` superuser. |
| `POSTGRES_USER` | DB username (if constructing URL) | Optional | `nextaction_user` | Used when `DATABASE_URL` is synthesized. |
| `POSTGRES_PASSWORD` | DB password (if constructing URL) | Optional | `<random-32-char-password>` | Keep isolated in secret manager. |
| `POSTGRES_DB` | Production database name | Optional | `nextaction_prod` | Dedicated production database catalog. |
| `POSTGRES_HOST` | Database hostname or internal service name | Optional | `db.production.internal` | Should resolve to private VPC IP only. |
| `POSTGRES_PORT` | Database listening port | Optional (default: `5432`) | `5432` | Standard PostgreSQL port. |
| `DB_SSLMODE` | SSL certificate verification mode | Optional (default: `require`) | `verify-full` or `require` | Enforce encryption in transit between app and managed database. |
| `DB_POOL_SIZE` | Persistent DB connection pool size | Optional (default: `10`) | `20` | Tune based on container count and DB `max_connections`. |
| `DB_MAX_OVERFLOW` | Burst connection count | Optional (default: `20`) | `10` | Caps total connections per worker process. |
| `DB_POOL_TIMEOUT` | Seconds to wait for available connection | Optional (default: `30`) | `15` | Fast-fails requests during database saturation. |
| `DB_POOL_RECYCLE` | Max connection lifetime in seconds | Optional (default: `1800`) | `1800` | Recycles connections to avoid stale state and proxy timeouts. |

### 3.4. Distributed Rate Limiting & Redis

| Variable Name | Purpose | Required / Optional | Production Example / Placeholder | Security Notes |
| :--- | :--- | :--- | :--- | :--- |
| `RATE_LIMIT_ENABLED` | Global rate limit toggle | Optional (default: `true`) | `true` | Must remain `true` to mitigate brute-force and DDoS vectors. |
| `RATE_LIMIT_BACKEND` | Rate limit storage backend (`memory` or `redis`) | Optional (default: `memory`) | `redis` | In multi-worker/multi-container deployments, `redis` provides unified limits. |
| `REDIS_URL` | Redis connection URL | Optional | `redis://:REDIS_AUTH_TOKEN@redis.production.internal:6379/0` | Preferred over host/port splitting. |
| `REDIS_HOST` | Redis service host | Optional (default: `localhost`) | `redis.internal` | Private non-routable hostname. |
| `REDIS_PORT` | Redis listening port | Optional (default: `6379`) | `6379` | Non-exposed port. |
| `REDIS_PASSWORD` | Redis AUTH token | Optional | `<random-32-char-password>` | Set if Redis requires authentication. |
| `REDIS_DB` | Redis database index | Optional (default: `0`) | `0` | Dedicated database index. |
| `REDIS_TIMEOUT_SECONDS` | Redis operation timeout | Optional (default: `2.0`) | `2.0` | Prevents rate limiting from blocking if Redis stalls. |
| `RATE_LIMIT_MAX_ATTEMPTS` | Maximum requests per sliding window | Optional (default: `300`) | `300` | Tuned for normal user concurrency. |
| `RATE_LIMIT_WINDOW_SECONDS` | Sliding window duration in seconds | Optional (default: `60`) | `60` | 1-minute sliding window. |

### 3.5. Host, Domain & CORS Hardening

| Variable Name | Purpose | Required / Optional | Production Example / Placeholder | Security Notes |
| :--- | :--- | :--- | :--- | :--- |
| `CORS_ORIGINS` | JSON list of permitted web browser origins | **Required** | `["https://app.nextaction.io"]` | Wildcard `*` is explicitly blocked in production. |
| `TRUSTED_HOSTS` | Allowed HTTP `Host` header values | **Required** | `["app.nextaction.io", "api.nextaction.io"]` | Mitigates HTTP Host Header Poisoning attacks. |
| `FRONTEND_URL` | Public URL where web frontend is hosted | **Required** | `https://app.nextaction.io` | Used in email links and password reset workflows. |
| `API_BASE_URL` | Public URL where API is exposed | **Required** | `https://app.nextaction.io/api` | Used in CORS preflight and documentation references. |

---

## 4. Key Generation & Secret Bootstrapping

To generate production secrets without risk of predictable randomness:

```bash
# Generate SECRET_KEY (HMAC-SHA256 256-bit entropy)
openssl rand -hex 32

# Generate Database Password
openssl rand -base64 24

# Generate Redis Password
openssl rand -base64 24
```

---

## 5. Audit Checklist for Release

Prior to starting production containers:
- [ ] Confirm no `.env` files are tracked in git (`git status --ignored` shows `.env` ignored).
- [ ] Verify `ENVIRONMENT=production`.
- [ ] Verify `CORS_ORIGINS` does not contain `*` or `http://localhost`.
- [ ] Verify `TRUSTED_HOSTS` contains only official production domains.
- [ ] Verify `SECRET_KEY` is not the default fallback from development.
- [ ] Verify database credentials are authenticated and SSL mode is configured (`DB_SSLMODE=require`).
