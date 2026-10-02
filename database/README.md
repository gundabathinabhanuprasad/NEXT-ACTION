# NextAction Database Documentation

## Database Overview
- **Engine**: PostgreSQL 16
- **Database Name**: `nextaction`
- **Default User**: `nextaction`
- **Default Port**: `5432`
- **ORM**: SQLAlchemy 2.0 (`backend/app/db/__init__.py`)
- **Migration Tool**: Alembic (`backend/alembic/`, `backend/alembic.ini`)
- **Driver**: `psycopg` (v3)

## Migration Workflow
All schema migrations are managed via Alembic in `backend/`.

### Generate a Migration (Autogenerate from ORM Models)
```bash
cd backend
.venv\Scripts\alembic.exe revision --autogenerate -m "describe_change"
```

### Apply Migrations
```bash
cd backend
.venv\Scripts\alembic.exe upgrade head
```

### Rollback Migration
```bash
cd backend
.venv\Scripts\alembic.exe downgrade -1
```

## Local Development
Local database development is configured via Docker Compose (`docker-compose.yml` in the project root).
When Docker is running:
```bash
docker compose up -d postgres
```
