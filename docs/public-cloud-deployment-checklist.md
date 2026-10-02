# Public Cloud Deployment Checklist (NextAction v1.0.0)

**Target Domain:** `app.nextaction.io`  
**Target Provider:** AWS (us-east-1)  
**Execution Status:** Planning & Pre-Deployment Phase Complete — Ready for Execution upon Infrastructure Provisioning

This checklist governs the step-by-step execution of transitioning NextAction v1.0.0 from verified containerized staging to public AWS cloud infrastructure. Checkboxes must only be marked when verified through direct technical observation.

---

## 1. Pre-Deployment Discovery & Tooling Status

- [x] **Local Multi-Tier Container Stack Verified**: 100% of 35 production verification checks passed in Phase 25.
- [x] **Terraform Availability Verified**: Terraform v1.15.3 detected on deployment workstation.
- [ ] **AWS CLI Installed**: `aws` CLI binary not currently installed in system PATH.
- [x] **AWS Configuration Profiles Inspected**: `~/.aws/config` (us-east-1) and `~/.aws/credentials` detected without credential exposure.
- [ ] **AWS Identity Verification**: Blocked until AWS CLI is installed or AWS IAM credentials are authenticated via SDK.
- [x] **Route 53 Hosted Zone Discovery**: Root domain `nextaction.io` confirmed delegated to AWS Route 53 nameservers (`ns-622.awsdns-13.net`, `ns-1080.awsdns-07.org`, etc.).
- [ ] **Subdomain DNS Record**: `app.nextaction.io` DNS record does **not exist** (Current blocker).

---

## 2. Infrastructure Provisioning Checklist (AWS EC2 & Networking)

- [ ] **Elastic IP Allocated**: Allocate static public IPv4 address in `us-east-1`.
- [ ] **Security Group Configured (`nextaction-prod-sg`)**:
  - [ ] Port `80/tcp` open to `0.0.0.0/0` and `::/0` (HTTP redirection and ACME challenge).
  - [ ] Port `443/tcp` open to `0.0.0.0/0` and `::/0` (HTTPS client traffic).
  - [ ] Port `22/tcp` strictly restricted to `<OPERATOR_IP>/32` (Administrative SSH).
  - [ ] Port `5432/tcp` (PostgreSQL) has **ZERO** public inbound access.
  - [ ] Port `6379/tcp` (Redis) has **ZERO** public inbound access.
- [ ] **EC2 Instance Launched**:
  - [ ] Sizing: `t3.medium` (2 vCPUs, 4 GiB RAM, x86_64 architecture).
  - [ ] AMI: Ubuntu Server 22.04 LTS (Jammy Jellyfish).
  - [ ] Storage: 30 GiB `gp3` root volume with EBS encryption enabled.
  - [ ] IAM Role: `NextActionEC2BackupRole` attached with least-privilege S3 backup write permissions.
- [ ] **Elastic IP Attached**: Public static IPv4 bound to the running EC2 instance.
- [ ] **Route 53 A-Record Created**:
  - [ ] Record name: `app.nextaction.io`
  - [ ] Record type: `A`
  - [ ] Target: `<ALLOCATED_ELASTIC_IP>`
  - [ ] TTL: `300` seconds
- [ ] **DNS Propagation Verified**: `Resolve-DnsName app.nextaction.io` successfully resolves to the Elastic IP.

---

## 3. Host Runtime & Secrets Configuration

- [ ] **SSH Connectivity Verified**: Secure administrative login using dedicated SSH key pair.
- [ ] **Host System Updated**: `apt update && apt upgrade -y`.
- [ ] **Docker Engine Installed**: Docker Engine >= 26.0 and Docker Compose V2 installed and verified (`docker compose version`).
- [ ] **Release Artifacts Transferred**: NextAction repository / deployment artifacts transferred to `/opt/nextaction`.
- [ ] **Production Secrets Configured (`.env.prod`)**:
  - [ ] High-entropy `SECRET_KEY` generated via `openssl rand -hex 32`.
  - [ ] High-entropy `POSTGRES_PASSWORD` generated via `openssl rand -base64 24`.
  - [ ] High-entropy `REDIS_PASSWORD` generated via `openssl rand -base64 24`.
  - [ ] `CORS_ORIGINS` strictly restricted to `["https://app.nextaction.io"]`.
  - [ ] `TRUSTED_HOSTS` strictly restricted to `["app.nextaction.io"]`.
  - [ ] File permissions locked: `chmod 600 /opt/nextaction/.env.prod`.
- [ ] **Docker Compose Syntax Validated**: `docker compose --env-file .env.prod -f docker-compose.prod.yml config` passes without warnings.

---

## 4. Persistence Tier Initialization & Migrations

- [ ] **PostgreSQL & Redis Started**: `docker compose -f docker-compose.prod.yml up -d postgres redis`.
- [ ] **PostgreSQL Health Verified**: `pg_isready -U nextaction_admin -d nextaction_prod` returns healthy.
- [ ] **Pre-Migration Database Snapshot Taken**: Initial clean snapshot generated using `pg_dump -Fc`.
- [ ] **Alembic Migrations Executed**:
  - [ ] `docker compose -f docker-compose.prod.yml run --rm backend alembic upgrade head`.
  - [ ] Verified current database revision matches head `b2c3d4e5f6a7`.
- [ ] **Redis Authentication & Connectivity Verified**: `redis-cli -a "$REDIS_PASSWORD" ping` returns `PONG`.

---

## 5. Application & Reverse Proxy Deployment

- [ ] **Backend Application Container Started**: `docker compose -f docker-compose.prod.yml up -d backend`.
- [ ] **Backend Probes Verified**:
  - [ ] `GET http://backend:8000/health` returns HTTP 200 `{"status": "healthy"}`.
  - [ ] `GET http://backend:8000/ready` returns HTTP 200 `{"status": "ready"}`.
- [ ] **Let's Encrypt TLS Certificate Issued**:
  - [ ] Certbot webroot ACME challenge completed successfully for `app.nextaction.io`.
  - [ ] `fullchain.pem` and `privkey.pem` placed into `nginx/ssl/` with permissions `600`.
- [ ] **Reverse Proxy Container Started**: `docker compose -f docker-compose.prod.yml up -d reverse-proxy`.
- [ ] **Flutter Web Release Bundle Verified**:
  - [ ] Mounted read-only into `/usr/share/nginx/html`.
  - [ ] Verified `--dart-define=API_BASE_URL=https://app.nextaction.io/api`.
  - [ ] SPA fallback routing verified for deep links (`/tasks`, `/dashboard`).
- [ ] **Port 80 HTTP -> HTTPS Redirection Verified**: `curl -I http://app.nextaction.io` returns `HTTP/1.1 301 Moved Permanently` to `https://app.nextaction.io/`.
- [ ] **Security Headers Verified**: HSTS, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `X-Request-ID` present on public responses.

---

## 6. Post-Deployment Verification & Handover

- [ ] **End-to-End Test Suite Executed**: Run `phase25_production_deployment_verification.py` against `https://app.nextaction.io`.
  - [ ] User registration and bcrypt hashing.
  - [ ] Dual-token login and `/auth/me`.
  - [ ] Refresh token rotation and replay-attack rejection (HTTP 401).
  - [ ] 25-step task workflow (Client, Workflow, Task, Attempts, Override, Scheduling, Completion, Reopen, History).
  - [ ] Dashboard summary metrics and Notification queries.
  - [ ] RFC 4180 CSV export and bounded limit clamping (`limit=100000` clamped to 5000).
- [ ] **Automated Off-site S3 Backup Configured**:
  - [ ] Nightly cron job installed for `backup_production.sh`.
  - [ ] Test backup upload verified in `s3://nextaction-production-backups-us-east-1/database/`.
  - [ ] 30-day lifecycle retention policy applied.
- [ ] **Certificate Auto-Renewal Configured**: Certbot renewal cron job installed with automated Nginx reload hook.
- [ ] **CloudWatch Monitoring / Uptime Checks Activated**: Health check alerts configured for `GET /health` probe.

---

### Final Readiness Declaration

- **Local Verification Status:** COMPLETE (v1.0.0 Release Candidate Ready)
- **Cloud Infrastructure Status:** SPECIFIED & READY TO PROVISION
- **Blockers Awaiting Authorization:**
  1. AWS CLI installation / credential activation
  2. Elastic IP allocation and Route 53 `A` record creation for `app.nextaction.io`
  3. EC2 instance creation approval (billable resource)
