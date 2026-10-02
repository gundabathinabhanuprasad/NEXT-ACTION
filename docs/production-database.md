# NextAction Production Database Configuration & Runbook

## 1. Overview & Operational Principles

NextAction relies on PostgreSQL 16+ as its primary persistent, ACID-compliant relational data store. In production deployments:
1. **No Destructive Auto-Migrations at Boot**: The backend application containers do NOT automatically run destructive migrations on startup. Schema migrations are executed explicitly as a controlled pre-deployment pipeline step (`alembic upgrade head`).
2. **Credential Hardening**: Database credentials are strictly sourced from environment variables or secret stores. Default development passwords (e.g. `postgres`, `password`) are barred from production.
3. **Connection Pooling & Pre-Ping**: SQLAlchemy utilizes pre-warmed connection pools with health checks (`pool_pre_ping=True`) to gracefully handle connection drops from managed database failovers.
4. **Transport Encryption**: SSL/TLS encryption in transit is enforced using `DB_SSLMODE` (e.g., `require` or `verify-full`).
5. **Phase 21 Backup Integration**: Full database dumps, point-in-time recovery (PITR) write-ahead logging (WAL), and validation procedures established in Phase 21 remain 100% compatible.

---

## 2. Production Database Creation & Initialization

### 2.1. Initial Database & Role Provisioning
When provisioning a new PostgreSQL instance (either standalone or via a managed cloud database like Amazon RDS, Cloud SQL, Azure Database for PostgreSQL, or Supabase):

```sql
-- 1. Create a dedicated unprivileged application user
CREATE USER nextaction_app WITH PASSWORD '<STRONG_SECURE_PASSWORD>';

-- 2. Create the production database catalog
CREATE DATABASE nextaction_prod WITH OWNER nextaction_app ENCODING 'UTF8' LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';

-- 3. Connect to the database catalog
\c nextaction_prod

-- 4. Revoke public permissions and grant least privilege
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO nextaction_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nextaction_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO nextaction_app;

-- 5. Ensure UUID extension is available
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
```

---

## 3. Database Environment Variables

The backend application reads database configuration through the following environment variables:

| Variable | Description | Production Default / Recommended |
| :--- | :--- | :--- |
| `DATABASE_URL` | Complete connection string | `postgresql+psycopg2://nextaction_app:PASSWORD@db.internal:5432/nextaction_prod` |
| `DB_SSLMODE` | SSL Mode for PostgreSQL connection | `require` (or `verify-full` if CA cert provided) |
| `DB_POOL_SIZE` | Persistent connections per backend worker process | `10` to `20` |
| `DB_MAX_OVERFLOW` | Maximum burst connections beyond pool size | `10` to `20` |
| `DB_POOL_TIMEOUT` | Seconds to wait before timing out on pool exhaustion | `15` |
| `DB_POOL_RECYCLE` | Max seconds before connection is refreshed | `1800` (30 minutes) |

### Calculating Total Connection Load
```
Total Connections = (Number of Backend Containers) * (Workers per Container) * (DB_POOL_SIZE + DB_MAX_OVERFLOW)
```
Ensure that PostgreSQL `max_connections` (in `postgresql.conf` or cloud parameter groups) is configured at least 20% higher than the maximum calculated total connection load to leave headroom for administrative tasks, backups, and migrations.

---

## 4. Alembic Migration Procedures

NextAction uses Alembic for declarative schema versioning. All migration files reside in `backend/alembic/versions/`.

### 4.1. Inspecting Migration State
Before running any migrations or deploying code, verify current database revision:

```bash
# From within the backend directory or container:
alembic current
```

Verify that the schema has a single unambiguous head:
```bash
alembic heads
# Expected Output:
# b2c3d4e5f6a7 (head)
```

### 4.2. Applying Migrations (Pre-Deployment Step)
Execute the migration command against the target database:

```bash
# Apply all pending migrations up to the head
alembic upgrade head
```

If deploying via Docker Compose in a production environment:
```bash
docker compose -f docker-compose.prod.yml run --rm backend alembic upgrade head
```

### 4.3. Migration Rollback Procedure
If a deployment must be rolled back to a previous revision:

```bash
# Downgrade by 1 revision
alembic downgrade -1

# Or downgrade to a specific historical revision hash
alembic downgrade <revision_id>
```

> [!WARNING]
> Always verify that a downgrade does not cause irrecoverable data loss. Take an immediate database snapshot before applying schema changes.

---

## 5. SSL & Transport Security Configuration

For cloud-managed databases (AWS RDS, GCP Cloud SQL, Azure), encrypt all traffic:

1. **Require Mode (`DB_SSLMODE=require`)**:
   Ensures all traffic over the wire is encrypted via TLS.
2. **Verify Full (`DB_SSLMODE=verify-full`)**:
   Validates the database server's SSL certificate against the trusted certificate authority bundle.
   To configure:
   ```bash
   export DATABASE_URL="postgresql+psycopg2://user:pass@host:5432/dbname?sslmode=verify-full&sslrootcert=/etc/ssl/certs/rds-combined-ca-bundle.pem"
   ```

---

## 6. Backup & Recovery Operations (Phase 21 Integration)

NextAction's backup and recovery pipeline is fully documented in `docs/backup-recovery.md` and automated via `scripts/database_backup.py` and `scripts/database_restore.py`.

### 6.1. Executing a Manual Full Backup
```bash
python scripts/database_backup.py --format custom --verify-checksum
```
This produces:
- An encrypted compressed snapshot in `/backups/nextaction_backup_<timestamp>.dump`.
- A cryptographic integrity manifest in `/backups/nextaction_backup_<timestamp>.json` containing SHA-256 checksums, schema revision, table counts, and duration.

### 6.2. Executing a Restoration
```bash
python scripts/database_restore.py --file /backups/nextaction_backup_<timestamp>.dump --verify-before
```
Restoration executes in a transaction or clean database drop-and-recreate, verifies table row counts against the manifest, and checks Alembic head status.

### 6.3. Recovery Objectives
- **Recovery Point Objective (RPO)**: < 1 hour via automated periodic dumps; < 5 minutes if continuous WAL archiving is enabled.
- **Recovery Time Objective (RTO)**: < 15 minutes for restoring snapshots up to 10 GB.
