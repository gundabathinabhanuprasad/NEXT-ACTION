# NextAction

NextAction is a professional task and follow-up management application designed for managing:
- Tasks
- Follow-ups
- Reminders
- Clients
- Workflows
- Events
- Task history

Target platforms: **Android** and **Web**.

---

## Architecture & Tech Stack

- **Monorepo Approach**: Clean separation between frontend client and backend services.
- **Frontend**: Flutter + Dart (Material 3, Null Safety, Android & Web support) in `apps/mobile_web`.
- **Backend API**: Python FastAPI (REST API architecture, Pydantic v2 schemas and settings) in `backend/`.
- **ORM & Migrations**: SQLAlchemy 2.0 and Alembic in `backend/app/db/` and `backend/alembic/`.
- **Database**: PostgreSQL 16 via Docker Compose (`docker-compose.yml`) using `psycopg` (v3).
- **Server**: Uvicorn ASGI.

---

## Repository Structure

```text
.
├── .gitignore               # Comprehensive monorepo gitignore
├── README.md                # Project documentation
├── docker-compose.yml       # PostgreSQL 16 + Adminer local container setup
├── apps/
│   └── mobile_web/          # Flutter application for Mobile (Android) & Web
├── backend/
│   ├── alembic/             # Database migration configuration & scripts
│   ├── alembic.ini          # Alembic configuration
│   ├── app/                 # FastAPI application package
│   │   ├── api/             # API routes
│   │   ├── core/            # Settings and core config
│   │   ├── db/              # Database connection & base ORM model
│   │   ├── models/          # SQLAlchemy database models
│   │   ├── schemas/         # Pydantic validation schemas & DTOs
│   │   ├── services/        # Business logic services
│   │   └── main.py          # FastAPI application entrypoint
│   ├── tests/               # Backend automated tests (pytest)
│   ├── requirements.txt     # Python backend dependencies
│   └── README.md            # Backend specific instructions
├── database/
│   └── README.md            # Database architecture & migration guide
├── docs/
│   └── phase-1-foundation.md # Phase 1 environment audit & verification report
└── scripts/
    ├── README.md            # Scripts overview
    └── run_backend.ps1      # PowerShell helper to run backend
```

---

## Local Development Prerequisites

- **Python**: 3.11+ (Python 3.14.4 detected)
- **Git**: 2.x (Git 2.54.0 detected)
- **Flutter SDK**: 3.22+ (Flutter 3.22.2 / Dart 3.4.3 detected)
- **Docker Desktop**: Required for local PostgreSQL database container

---

## How to Start the Backend

### 1. Set Up Virtual Environment & Dependencies
```bash
cd backend
python -m venv .venv

# Activate on Windows PowerShell:
.\.venv\Scripts\Activate.ps1

# Install dependencies:
pip install -r requirements.txt
```

### 2. Start Backend Development Server
```bash
uvicorn app.main:app --reload --port 8000
```
- API Documentation: http://127.0.0.1:8000/docs
- Health Check: http://127.0.0.1:8000/health

---

## How to Run Backend Tests

```bash
cd backend
pytest tests -v
```

---

## Flutter Application Status

- **Location**: `apps/mobile_web`
- **Current State**: Initialized, verified, and passing tests.
- **Analysis**: `flutter analyze` passes with 0 issues.
- **Tests**: `flutter test` passes (100%).
- **Run Locally (Chrome/Web)**:
  ```bash
  cd apps/mobile_web
  flutter run -d chrome
  ```

---

## PostgreSQL & Docker Status

- **Docker Status**: Docker is not installed on this machine. PostgreSQL container validation is currently blocked until Docker Desktop is installed or a local PostgreSQL instance is provided.
- **Configuration**: Ready in `docker-compose.yml` (PostgreSQL 16, database: `nextaction`, user: `nextaction`, port: `5432`, named volume: `nextaction_postgres_data`).
