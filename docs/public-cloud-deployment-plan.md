# Phase 26 — Public Cloud Infrastructure Provisioning Plan

**Project:** NextAction Production Deployment  
**Version:** 1.0.0 (Build 1)  
**Status:** Planning & Specification Only (No Cloud Resources Created / Zero Spend)  
**Target Domain:** `app.nextaction.io`  
**Reference Deployment:** `docker-compose.prod.yml` (Verified in Phase 25)

---

## 1. Executive Summary

Phase 25 successfully deployed and verified the NextAction v1.0.0 release candidate in an isolated, multi-tier containerized production topology (`docker-compose.prod.yml`), passing 100% of 35 automated end-to-end HTTPS verification tests (including registration, dual-token authentication, refresh-token rotation, replay attack rejection, 25-step task workflow, audit logging, rate limiting, and RFC 4180 CSV export).

The remaining blockers preventing public internet access are:
1. `app.nextaction.io` has no public DNS `A` or `CNAME` record mapped to a public static IP address.
2. No public CA (Let's Encrypt) TLS certificate can be issued until public DNS resolves and port 80 is reachable.
3. No public cloud virtual machine (e.g., AWS EC2) is currently provisioned.
4. The deployment is currently executing on the local Docker engine.

This document defines the **exact, production-grade infrastructure provisioning and deployment plan** to transition the verified NextAction v1.0.0 container topology to a public cloud virtual machine on AWS (or any equivalent cloud provider) with zero architecture redesign, zero application code modifications, and strict adherence to defense-in-depth security principles.

> [!IMPORTANT]
> **Zero Cloud Resource Execution Policy**: This phase is strictly limited to architectural inspection, technical discovery, and provisioning specification. No EC2 instances, Route 53 records, Elastic IPs, or Let's Encrypt certificates have been created or modified, and zero cloud spend has occurred.

---

## 2. Environment Inspection & Discovery Findings

Prior to drafting this plan, the local environment was systematically inspected for existing cloud tooling, account configurations, and DNS state.

### 2.1. Cloud Provider CLIs

Command executed:
```powershell
foreach ($cmd in @('aws', 'gcloud', 'az', 'terraform', 'doctl', 'flyctl')) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) { Write-Output "$cmd : Found at $($found.Source)" }
    else { Write-Output "$cmd : Not found" }
}
```

**Results:**
- `aws`: **Not found** (AWS CLI is not installed in system PATH)
- `gcloud`: **Not found**
- `az`: **Not found**
- `terraform`: **Found** (Terraform v1.15.3 on windows_amd64 at `C:\Users\Viyu\AppData\Local\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe\terraform.exe`)
- `doctl`: **Not found**
- `flyctl`: **Not found**

### 2.2. AWS Configuration & Credentials Inspection

Standard configuration paths were inspected without exposing sensitive values:
- `~/.aws/config`: Present. Profile `[default]` configured with `region = us-east-1` and `output = json`.
- `~/.aws/credentials`: Present. Profile `[default]` contains `aws_access_key_id` and `aws_secret_access_key`.
- `boto3`: Not installed in the Python backend virtual environment.
- Identity check (`aws sts get-caller-identity`): Cannot be executed directly because the AWS CLI binary is not installed on the host.

### 2.3. Git Remote Configuration

Command executed:
```powershell
git remote -v
```
**Result:** Empty (No remote git repository configured on this workstation).

### 2.4. Current DNS Analysis for `app.nextaction.io`

Commands executed:
```powershell
Resolve-DnsName app.nextaction.io -ErrorAction Continue
Resolve-DnsName nextaction.io -Type NS -ErrorAction Continue
Resolve-DnsName app.nextaction.io -Server ns-110.awsdns-13.com -ErrorAction Continue
```

**Results:**
1. **Target Subdomain (`app.nextaction.io`)**: **DNS name does not exist**.
2. **Root Domain (`nextaction.io`)**: Actively delegated to AWS Route 53 authoritative nameservers:
   - `ns-622.awsdns-13.net`
   - `ns-1080.awsdns-07.org`
   - `ns-110.awsdns-13.com`
   - `ns-1765.awsdns-28.co.uk`
3. **Authoritative Query**: Directly querying `ns-110.awsdns-13.com` confirms that no `A` or `CNAME` record exists for `app.nextaction.io` in the Route 53 hosted zone.

**Conclusion:** The Route 53 hosted zone for `nextaction.io` is already established in AWS, making AWS EC2 in region `us-east-1` the natural and lowest-friction target for public cloud deployment.

---

## 3. Production Cloud Architecture

The target cloud deployment preserves 100% of the verified NextAction architecture. No architectural redesign is permitted or required.

```
 Internet (Browser / Mobile / Web Clients)
                     │
                     │ HTTPS (Port 443) / HTTP (Port 80 - Redirect only)
                     ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ AWS VPC (us-east-1) - Security Group (nextaction-prod-sg)   │
  │                                                             │
  │   Elastic IP (Static IPv4) -> Attached to EC2 VM            │
  │                                                             │
  │   ┌─────────────────────────────────────────────────────┐   │
  │   │ EC2 Instance (t3.medium, Ubuntu 22.04 LTS, gp3 EBS) │   │
  │   │                                                     │   │
  │   │  [Docker Engine & Docker Compose V2]                │   │
  │   │                                                     │   │
  │   │  ┌───────────────────────────────────────────────┐  │   │
  │   │  │ nextaction_prod_proxy (Nginx 1.27)            │  │   │
  │   │  │   ├── Ports 80 & 443 Published                │  │   │
  │   │  │   ├── Let's Encrypt TLS (Certbot webroot)     │  │   │
  │   │  │   ├── Flutter Web SPA (/usr/share/nginx/html) │  │   │
  │   │  │   └── Reverse Proxy /api/ -> backend:8000     │  │   │
  │   │  └───────────────────────┬───────────────────────┘  │   │
  │   │                          │                          │   │
  │   │     ═════════════════════╪═════════════════════     │   │
  │   │     Internal Bridge: nextaction_internal (Private)  │   │
  │   │     ═════════════════════╪═════════════════════     │   │
  │   │                          │                          │   │
  │   │  ┌───────────────────────┴───────────────────────┐  │   │
  │   │  │ nextaction_prod_backend (FastAPI / Python 3.11)│  │   │
  │   │  │   ├── Non-root appuser (UID 10001)            │  │   │
  │   │  │   ├── Port 8000 (Internal Only - Unexposed)   │  │   │
  │   │  │   └── Redis-backed Rate Limiter               │  │   │
  │   │  └───────────┬───────────────────────┬───────────┘  │   │
  │   │              │                       │              │   │
  │   │              ▼                       ▼              │   │
  │   │  ┌────────────────────────┐ ┌────────────────────┐  │   │
  │   │  │nextaction_prod_postgres│ │nextaction_prod_redis│ │   │
  │   │  │  PostgreSQL 16.15      │ │  Redis 7.0 (AOF)   │  │   │
  │   │  │  Port 5432 (Internal)  │ │  Port 6379 (Int.)  │  │   │
  │   │  │  Persistent EBS Volume │ │  Persistent Volume │  │   │
  │   │  └────────────────────────┘ └────────────────────┘  │   │
  │   └─────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────┘
                     │
                     ▼ Nightly Encrypted Dumps (pg_dump -Fc)
          [ AWS S3 Private Backup Bucket ]
```

---

## 4. EC2 Virtual Machine Specification

Based on application profiling during Phase 24 and Phase 25 testing, the recommended EC2 specification is:

| Parameter | Recommended Specification | Rationale |
|---|---|---|
| **Instance Type** | `t3.medium` (or `t3a.medium`) | 2 vCPUs, 4.0 GiB RAM. Provides balanced compute and memory for Uvicorn multi-workers, PostgreSQL 16 buffer cache, Redis in-memory store, and Nginx. |
| **Processor Architecture** | `x86_64` (AMD64) | Matches the verified container builds (`PostgreSQL 16.15 on x86_64-pc-linux-musl`, `python:3.11-slim amd64`, and Nginx amd64). |
| **Operating System** | Ubuntu Server 22.04 LTS (Jammy Jellyfish) or Debian 12 | Enterprise-grade stability, long-term support, standard systemd service management, kernel support for modern Docker overlay2 storage driver. |
| **Storage (Root EBS)** | 30 GiB General Purpose SSD (`gp3`) | Baseline 3,000 IOPS and 125 MB/s throughput; provides sufficient capacity for OS, Docker runtime layers, Flutter static build, and initial database growth. |
| **EBS Encryption** | Enabled (AWS KMS default key or custom CMK) | Enforces encryption-at-rest for database files and container volumes. |
| **Public IPv4** | 1x AWS Elastic IP (EIP) | Static public IP address required for Route 53 `A` record and stable Let's Encrypt renewal. |
| **IAM Instance Role** | `NextActionEC2BackupRole` | Grants least-privilege `s3:PutObject` access to the dedicated S3 backup bucket without storing hardcoded AWS credentials on the instance. |

---

## 5. Security Group & Firewall Specification

The AWS Security Group (`nextaction-prod-sg`) must strictly enforce least-privilege network exposure.

### 5.1. Inbound Rules

| Protocol | Port Range | Source | Purpose | Justification |
|---|---|---|---|---|
| **TCP** | `80` | `0.0.0.0/0` (IPv4)<br>`::/0` (IPv6) | HTTP Web Traffic | Required for Let's Encrypt ACME HTTP-01 challenges and HTTP -> HTTPS 301 redirection. |
| **TCP** | `443` | `0.0.0.0/0` (IPv4)<br>`::/0` (IPv6) | HTTPS Web Traffic | Primary production traffic for Flutter Web SPA and REST API reverse proxy. |
| **TCP** | `22` | `<OPERATOR_IP>/32` (or Bastion CIDR) | Administrative SSH | **Strictly restricted** to authorized operator IP or corporate VPN. Never open to `0.0.0.0/0`. |

> [!CAUTION]
> **Zero Exposure Rule for Databases**:
> - Port `5432` (PostgreSQL) must **NEVER** be open in the AWS Security Group.
> - Port `6379` (Redis) must **NEVER** be open in the AWS Security Group.
> - Both services are reachable **only** across the private Docker bridge network (`nextaction_internal`) by the backend container.

### 5.2. Outbound Rules

| Protocol | Port Range | Destination | Purpose |
|---|---|---|---|
| **TCP** | `443` | `0.0.0.0/0` | Package updates (APT), Docker Hub image pulls, Let's Encrypt ACME verification, S3 backup upload. |
| **TCP** | `80` | `0.0.0.0/0` | Ubuntu package repository mirrors, OCSP certificate revocation checks. |
| **UDP** | `53` | AWS VPC DNS (`172.31.0.2` or subnet default) | Domain name resolution. |
| **UDP** | `123` | `0.0.0.0/0` | NTP time synchronization (critical for JWT expiration verification). |

---

## 6. DNS & Domain Configuration

### 6.1. Route 53 Record Configuration

Since the hosted zone for `nextaction.io` already exists on Route 53, the following DNS record must be created:

| Record Field | Configured Value | Notes |
|---|---|---|
| **Record Name** | `app.nextaction.io` | Fully Qualified Domain Name for application entry |
| **Record Type** | `A` (IPv4 Address) | Direct address record |
| **Alias** | No | Standard A-record pointing to Elastic IP |
| **Value / Route Traffic To** | `<ALLOCATED_ELASTIC_IP>` | The static public IPv4 assigned to the EC2 instance |
| **TTL** | `300` seconds (5 minutes) | Low initial TTL allows rapid updates during migration |
| **Routing Policy** | Simple | Standard unweighted routing |

### 6.2. DNS Propagation Verification Command

```powershell
Resolve-DnsName -Name app.nextaction.io -Type A
```
Must return `<ALLOCATED_ELASTIC_IP>` before initiating Let's Encrypt certificate issuance.

---

## 7. Secrets Management & Environment Configuration

Production secrets must never be committed to git, baked into Docker images, or stored in unencrypted repository files.

### 7.1. Mandatory Production Environment Variables

| Variable | Generation / Source Method | Example Format / Constraint |
|---|---|---|
| `ENVIRONMENT` | Static | `production` |
| `LOG_LEVEL` | Static | `INFO` |
| `DOCS_ENABLED` | Static | `false` |
| `SECRET_KEY` | `openssl rand -hex 32` | 64-character cryptographic hex string |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Static | `60` |
| `REFRESH_TOKEN_EXPIRE_DAYS` | Static | `7` |
| `POSTGRES_USER` | Configuration | `nextaction_admin` |
| `POSTGRES_PASSWORD` | `openssl rand -base64 24` | 32-character high-entropy alphanumeric string |
| `POSTGRES_DB` | Configuration | `nextaction_prod` |
| `DATABASE_URL` | Derived | `postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}` |
| `REDIS_PASSWORD` | `openssl rand -base64 24` | High-entropy string |
| `REDIS_URL` | Derived | `redis://:${REDIS_PASSWORD}@redis:6379/0` |
| `CORS_ORIGINS` | Domain constraint | `["https://app.nextaction.io"]` |
| `TRUSTED_HOSTS` | Domain constraint | `["app.nextaction.io"]` |
| `FRONTEND_URL` | Domain constraint | `https://app.nextaction.io` |
| `API_BASE_URL` | Domain constraint | `https://app.nextaction.io/api` |

### 7.2. Secure Provisioning Procedure

1. Generate `.env.prod` on the target EC2 instance directly or transmit via encrypted channel (AWS SSM Parameter Store / Ansible Vault / SCP over restricted SSH).
2. Set strict file permissions on the target host:
   ```bash
   chmod 600 /opt/nextaction/.env.prod
   chown ubuntu:ubuntu /opt/nextaction/.env.prod
   ```
3. Verify `.gitignore` contains `.env.prod` (already verified in repository).

---

## 8. TLS & Let's Encrypt Provisioning Strategy

The production Nginx reverse proxy configuration in [`nginx/nginx.conf`](file:///c:/bhanu/NEXT%20ACTION/nginx/nginx.conf) is already pre-configured with:
- Port 80 HTTP -> HTTPS 301 redirection.
- ACME challenge webroot location: `location /.well-known/acme-challenge/ { root /var/www/certbot; }`.
- Modern TLSv1.2 and TLSv1.3 ciphers.
- HSTS header: `Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;`.

### 8.1. Certificate Issuance Sequence

```bash
# 1. Ensure certbot and python3-certbot-nginx are installed on the host (or run certbot via container)
sudo apt update && sudo apt install -y certbot

# 2. Issue the production certificate using webroot challenge
sudo certbot certonly --webroot \
  -w /var/www/certbot \
  -d app.nextaction.io \
  --email admin@nextaction.io \
  --agree-tos \
  --no-eff-email

# 3. Mount or copy certificates to nginx/ssl/
sudo cp /etc/letsencrypt/live/app.nextaction.io/fullchain.pem /opt/nextaction/nginx/ssl/server.crt
sudo cp /etc/letsencrypt/live/app.nextaction.io/privkey.pem /opt/nextaction/nginx/ssl/server.key
sudo chmod 600 /opt/nextaction/nginx/ssl/server.key

# 4. Reload Nginx to activate public TLS
docker compose -f docker-compose.prod.yml exec reverse-proxy nginx -s reload
```

### 8.2. Automated Renewal Setup

Let's Encrypt certificates expire every 90 days. An automated cron job or systemd timer must be configured:

```bash
# /etc/cron.d/certbot-renew
0 3 * * * root certbot renew --quiet --post-hook "cp /etc/letsencrypt/live/app.nextaction.io/fullchain.pem /opt/nextaction/nginx/ssl/server.crt && cp /etc/letsencrypt/live/app.nextaction.io/privkey.pem /opt/nextaction/nginx/ssl/server.key && docker compose -f /opt/nextaction/docker-compose.prod.yml exec -T reverse-proxy nginx -s reload"
```

---

## 9. Backup & Disaster Recovery Strategy

### 9.1. PostgreSQL Production Backup Workflow

1. **Backup Type**: Compressed custom-format dump (`pg_dump -Fc`) containing all schemas, constraints, indexes, and table data.
2. **Frequency**: Daily at 02:00 UTC (automated via cron).
3. **Off-site Destination**: Dedicated private S3 bucket (`s3://nextaction-production-backups-us-east-1/database/`).
4. **Encryption**: AWS S3 Server-Side Encryption with KMS (`aws:kms`).
5. **Retention Policy**:
   - Daily backups retained for 30 days.
   - Weekly backups transitioned to S3 Standard-Infrequent Access (Standard-IA) for 90 days.
   - Monthly backups transitioned to S3 Glacier Flexible Retrieval for 365 days.

### 9.2. Automated Backup Script (`/opt/nextaction/scripts/backup_production.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

TIMESTAMP=$(date -u +"%Y%m%d_%H%M%SZ")
BACKUP_DIR="/var/backups/nextaction"
BACKUP_FILE="${BACKUP_DIR}/nextaction_prod_${TIMESTAMP}.dump"
S3_BUCKET="s3://nextaction-production-backups-us-east-1/database"

mkdir -p "${BACKUP_DIR}"

# 1. Execute compressed database dump via running container
docker exec nextaction_prod_postgres pg_dump \
  -U nextaction_admin \
  -d nextaction_prod \
  -Fc \
  -f "/var/lib/postgresql/data/backup_temp.dump"

# 2. Move out of container
docker cp nextaction_prod_postgres:/var/lib/postgresql/data/backup_temp.dump "${BACKUP_FILE}"
docker exec nextaction_prod_postgres rm -f "/var/lib/postgresql/data/backup_temp.dump"

# 3. Verify backup is non-empty
BACKUP_SIZE=$(stat -c%s "${BACKUP_FILE}")
if [ "${BACKUP_SIZE}" -lt 5000 ]; then
  echo "ERROR: Backup file is suspiciously small (${BACKUP_SIZE} bytes)." >&2
  exit 1
fi

# 4. Upload to encrypted S3 bucket using EC2 IAM Role
aws s3 cp "${BACKUP_FILE}" "${S3_BUCKET}/nextaction_prod_${TIMESTAMP}.dump" \
  --sse aws:kms

# 5. Clean up local backups older than 7 days
find "${BACKUP_DIR}" -type f -name "nextaction_prod_*.dump" -mtime +7 -delete

echo "Backup completed and uploaded successfully: ${BACKUP_FILE} (${BACKUP_SIZE} bytes)"
```

### 9.3. Non-Destructive Restore Drill Procedure

To verify recovery capability without impacting production data:
1. Start a transient PostgreSQL container on a test port (`5433`).
2. Download the latest backup from S3.
3. Run `pg_restore -d nextaction_test <dump_file>`.
4. Run validation queries checking table row counts across `users`, `tasks`, and `audit_history`.
5. Destroy the transient test container.

---

## 10. Step-by-Step Production Deployment Runbook

When authorized cloud credentials and infrastructure become available, execute this exact 21-step deployment sequence:

```
[Phase A: Cloud Provisioning]
  Step 01: Allocate Elastic IP in us-east-1
  Step 02: Create Security Group (ports 80, 443, restricted 22)
  Step 03: Launch EC2 Instance (t3.medium, Ubuntu 22.04, 30 GB gp3)
  Step 04: Attach Elastic IP to EC2 Instance
  Step 05: Create Route 53 A-Record: app.nextaction.io -> Elastic IP

[Phase B: Host Configuration]
  Step 06: Connect via SSH using authorized key pair
  Step 07: Install Docker Engine >= 26.0 and Docker Compose V2
  Step 08: Clone / Transfer NextAction v1.0.0 release artifacts to /opt/nextaction
  Step 09: Generate secure .env.prod with high-entropy cryptographic keys (chmod 600)
  Step 10: Validate docker-compose.prod.yml configuration syntax

[Phase C: Database & In-Memory Stack]
  Step 11: Launch PostgreSQL and Redis containers (docker compose up -d postgres redis)
  Step 12: Verify database connectivity and create pre-migration backup snapshot
  Step 13: Execute Alembic database migration (alembic upgrade head)
  Step 14: Verify database head revision equals b2c3d4e5f6a7

[Phase D: Application & Edge Stack]
  Step 15: Launch FastAPI backend container (docker compose up -d backend)
  Step 16: Verify internal liveness (/health) and readiness (/ready) probes
  Step 17: Obtain Let's Encrypt production TLS certificate via Certbot webroot challenge
  Step 18: Launch Nginx reverse proxy with TLS certificates & Flutter Web SPA bundle
  Step 19: Verify Port 80 HTTP -> HTTPS 301 redirection and HSTS headers

[Phase E: Verification & Handover]
  Step 20: Execute automated 35-point verification suite against https://app.nextaction.io
  Step 21: Configure daily S3 backup cron job and setup CloudWatch memory/disk monitoring
```

---

## 11. Rollback & Contingency Procedures

| Failure Scenario | Immediate Action | Recovery Procedure |
|---|---|---|
| **Database Migration Failure** | Stop backend deployment immediately. | Run pre-migration backup restore: `docker exec -i nextaction_prod_postgres pg_restore -U nextaction_admin -d nextaction_prod --clean < backup_pre_migration.dump`. Revert to previous schema version. |
| **Backend Container Crash Loop** | Inspect logs: `docker compose logs backend`. | Revert to previous Docker image tag (`nextaction-backend:rc-previous`). Verify `.env.prod` syntax and database connection string. |
| **TLS Certificate Issuance Failure** | Nginx continues serving via fallback staging certificate. | Verify Route 53 DNS propagation: `dig app.nextaction.io`. Verify Security Group port 80 is reachable from the public internet. Re-run Certbot in verbose mode (`--dry-run`). |
| **Corrupted Data / Fatal Error** | Isolate container traffic by stopping Nginx (`docker stop nextaction_prod_proxy`). | Fetch latest valid snapshot from S3. Restore database via `pg_restore`. Re-verify data integrity before restarting proxy. |

---

## 12. Estimated Infrastructure Costs (AWS us-east-1)

| AWS Resource | Specification | Estimated Monthly Cost |
|---|---|---|
| **EC2 Instance (`t3.medium`)** | On-Demand (2 vCPU, 4 GiB RAM) | ~$30.37 / month |
| **EBS Storage (`gp3`)** | 30 GiB root volume, 3000 IOPS, 125 MB/s | ~$2.40 / month |
| **Elastic IP** | In-use attached to running EC2 instance | $0.00 / month |
| **Route 53 Hosted Zone** | 1 Hosted Zone (`nextaction.io`) | $0.50 / month |
| **AWS S3 Backup Storage** | ~5 GB standard backup snapshots + lifecycle | ~$0.15 / month |
| **Let's Encrypt TLS** | ACME Automated Certificate | $0.00 (Free) |
| **Total Estimated Cloud Cost** | | **~$33.42 / month** |

---

## 13. Current Blockers & Next Immediate Actions

To execute this plan in a subsequent operational deployment:
1. **AWS CLI & Authentication**: Install the AWS CLI on the deployment workstation or run deployment directly from an authorized jump host.
2. **IAM Authorization**: Ensure AWS credentials possess permissions for `ec2:RunInstances`, `ec2:AllocateAddress`, `route53:ChangeResourceRecordSets`, and `s3:CreateBucket`.
3. **Public IP Allocation & DNS Mapping**: Allocate the Elastic IP and execute the Route 53 `ChangeResourceRecordSets` call for `app.nextaction.io`.
4. **Execution Authorization**: Await explicit user authorization before launching billable cloud infrastructure.
