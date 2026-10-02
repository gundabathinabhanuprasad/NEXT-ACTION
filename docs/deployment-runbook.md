# NextAction Production Deployment Runbook

This runbook provides an executable, end-to-end operational guide for deploying the NextAction system into a production environment. Follow each step sequentially.

---

## 1. Prerequisites

Before beginning deployment, ensure the deployment host or target virtual machine satisfies the following minimum system requirements:

- **Operating System**: Linux (Ubuntu 22.04 LTS / Debian 12 / RHEL 9) or Windows Server with Docker Desktop
- **Compute**: Minimum 2 vCPUs, 4 GB RAM, 20 GB SSD storage
- **Installed Tooling**:
  - Docker Engine >= 24.0.0 and Docker Compose V2 (`docker compose version`)
  - Git >= 2.40
  - OpenSSL >= 3.0 (for secret key generation)
  - Curl and jq (for health probing and JSON inspection)
- **Domain & DNS**:
  - Fully Qualified Domain Name (FQDN), e.g. `app.example.com`
  - DNS `A` or `CNAME` records pointing to your public load balancer / reverse proxy IP address
  - Ports 80 and 443 open in host firewall / security groups

---

## 2. Environment Setup

Clone the repository and prepare the deployment directory:

```bash
# Clone the repository
git clone https://github.com/organization/nextaction.git /opt/nextaction
cd /opt/nextaction

# Ensure proper file permissions
chmod 700 .
```

---

## 3. Secrets Management & Environment Configuration

Create the production environment file from the template:

```bash
cp .env.example .env.prod
chmod 600 .env.prod
```

Edit `.env.prod` with production-grade values. Generate cryptographically strong random secrets:

```bash
# 1. Generate JWT SECRET_KEY (64-byte hex string)
JWT_SECRET=$(openssl rand -hex 32)

# 2. Generate Database Password
DB_PASS=$(openssl rand -base64 24)

# 3. Generate Redis Password
REDIS_PASS=$(openssl rand -base64 24)
```

Ensure `.env.prod` contains:
```ini
ENVIRONMENT=production
LOG_LEVEL=INFO
DOCS_ENABLED=false

SECRET_KEY=<PASTE_JWT_SECRET_HERE>
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=7

DATABASE_URL=postgresql+psycopg2://nextaction_app:<PASTE_DB_PASS_HERE>@postgres:5432/nextaction_prod
POSTGRES_USER=nextaction_app
POSTGRES_PASSWORD=<PASTE_DB_PASS_HERE>
POSTGRES_DB=nextaction_prod

RATE_LIMIT_ENABLED=true
RATE_LIMIT_BACKEND=redis
REDIS_URL=redis://:<PASTE_REDIS_PASS_HERE>@redis:6379/0
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=<PASTE_REDIS_PASS_HERE>

CORS_ORIGINS=["https://app.example.com"]
TRUSTED_HOSTS=["app.example.com"]
FRONTEND_URL=https://app.example.com
API_BASE_URL=https://app.example.com/api
```

---

## 4. Database Initialization

Start the PostgreSQL service in the background:

```bash
docker compose -f docker-compose.prod.yml up -d postgres
```

Wait for PostgreSQL to become ready:
```bash
docker compose -f docker-compose.prod.yml exec postgres pg_isready -U nextaction_app -d nextaction_prod
```

---

## 5. Schema Migrations

Apply Alembic migrations to update the database schema to the latest version:

```bash
# Run Alembic migrations in a one-off backend container
docker compose -f docker-compose.prod.yml run --rm backend alembic upgrade head
```

Verify that the current revision matches the migration head (`b2c3d4e5f6a7`):
```bash
docker compose -f docker-compose.prod.yml run --rm backend alembic current
```

---

## 6. Redis Distributed Rate Limiter Setup

Start the Redis container:

```bash
docker compose -f docker-compose.prod.yml up -d redis
```

Verify Redis connectivity:
```bash
docker compose -f docker-compose.prod.yml exec redis redis-cli ping
# Expected output: PONG
```

---

## 7. Backend Application Container Deployment

Start the FastAPI backend service:

```bash
docker compose -f docker-compose.prod.yml up -d backend
```

Verify the backend process is running without errors:
```bash
docker compose -f docker-compose.prod.yml logs --tail=50 backend
```

Check internal liveness and readiness:
```bash
# Liveness probe
docker compose -f docker-compose.prod.yml exec backend curl -f http://127.0.0.1:8000/health
# Readiness probe
docker compose -f docker-compose.prod.yml exec backend curl -f http://127.0.0.1:8000/ready
```

---

## 8. Reverse Proxy Configuration

Verify Nginx configuration syntax before reloading:

```bash
docker compose -f docker-compose.prod.yml run --rm reverse-proxy nginx -t
```

Ensure upstream resolution points to `backend:8000` on the private `nextaction-internal` network.

---

## 9. HTTPS & TLS Certificate Provisioning

### 9.1. Let's Encrypt / Certbot Setup
For automatic ACME HTTP-01 challenges, the Nginx configuration provides `location /.well-known/acme-challenge/`:

```bash
# Obtain certificate using certbot
certbot certonly --webroot -w /var/www/certbot -d app.example.com

# Copy or symlink certificates into nginx/ssl directory
cp /etc/letsencrypt/live/app.example.com/fullchain.pem nginx/ssl/nextaction.crt
cp /etc/letsencrypt/live/app.example.com/privkey.pem nginx/ssl/nextaction.key
chmod 600 nginx/ssl/nextaction.key
```

### 9.2. Starting Reverse Proxy
```bash
docker compose -f docker-compose.prod.yml up -d reverse-proxy
```

---

## 10. Flutter Web Release Build & Asset Serving

Build the production Flutter Web release bundle with the production API URL injected via `--dart-define`:

```bash
cd apps/mobile_web
flutter clean
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://app.example.com/api
```

The resulting artifacts in `apps/mobile_web/build/web/` (`index.html`, `main.dart.js`, `flutter.js`, `assets/`) are mounted read-only into `/usr/share/nginx/html` in the reverse proxy container.

---

## 11. Deployment Smoke Testing

Run the automated 17-point deployment smoke test:

```bash
python scripts/deployment_smoke_test.py
```

The test validates:
- [x] Liveness (`/health`) and Readiness (`/ready`)
- [x] Database connection pooling
- [x] Redis-backed rate limiting & fallback
- [x] Nginx TLS & HSTS configuration
- [x] Alembic migration head integrity
- [x] Registration & bcrypt password hashing
- [x] JWT access token verification
- [x] Server-side refresh token generation & storage
- [x] Refresh token rotation
- [x] Replay attack detection & token family revocation
- [x] Server-side revocation on logout
- [x] Task CRUD operations under active session
- [x] Rate limit throttling
- [x] Flutter Web release bundle integrity

---

## 12. Monitoring & Logging

NextAction outputs structured JSON logs to `stdout`/`stderr` adhering to 12-factor principles.

### 12.1. Inspecting Live Logs
```bash
# View backend application logs with correlation IDs
docker compose -f docker-compose.prod.yml logs -f --tail=100 backend

# View Nginx access & security logs
docker compose -f docker-compose.prod.yml logs -f --tail=100 reverse-proxy
```

### 12.2. Log Forwarding Recommendation
In production, forward container logs via Docker logging drivers (`syslog`, `fluentd`, `journald`, or cloud log agents like AWS CloudWatch / GCP Cloud Logging).
Ensure no sensitive data (passwords, Authorization headers) is logged (guaranteed by NextAction log formatters).

---

## 13. Backup Verification

Run the Phase 21 database backup script to establish a baseline snapshot immediately following deployment:

```bash
python scripts/database_backup.py --format custom --verify-checksum
```

Verify the generated `.dump` file and `.json` metadata manifest in `/backups`.

---

## 14. Rollback Procedure

If an unrecoverable defect is discovered post-deployment:

### 14.1. Application Container Rollback
```bash
# Revert to previous image tag or commit
git checkout <previous-release-tag>
docker compose -f docker-compose.prod.yml build backend
docker compose -f docker-compose.prod.yml up -d --no-deps backend
```

### 14.2. Database Schema Rollback
```bash
docker compose -f docker-compose.prod.yml run --rm backend alembic downgrade -1
```

### 14.3. Database State Restoration (Catastrophic Failure)
```bash
python scripts/database_restore.py --file /backups/<pre_deployment_snapshot>.dump --verify-before
```

---

## 15. Troubleshooting & Operational FAQs

### 15.1. 502 Bad Gateway from Nginx
- **Cause**: Backend container is not running or still booting.
- **Fix**: Check `docker compose logs backend`. Confirm backend health endpoint is responding on port 8000:
  `docker compose exec backend curl http://127.0.0.1:8000/health`.

### 15.2. 429 Too Many Requests on Login
- **Cause**: Exceeded `RATE_LIMIT_MAX_ATTEMPTS` within sliding window.
- **Fix**: Wait for the `Retry-After` window to expire or inspect Redis rate limit keys:
  `docker compose exec redis redis-cli keys "rate:*"`

### 15.3. 401 Unauthorized with Refresh Token
- **Cause**: Refresh token has expired, been revoked by logout, or reused in a replay attempt.
- **Fix**: The client should catch 401 and redirect to the login screen to establish a fresh session.
