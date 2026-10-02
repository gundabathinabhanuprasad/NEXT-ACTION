# NextAction Backend API

FastAPI backend service for NextAction task and follow-up management system.

## Features (Phase 1)
- FastAPI 0.111+ REST API framework
- Pydantic v2 data models and settings management
- SQLAlchemy 2.0 ORM base configuration
- Alembic database migration foundation
- Health check endpoint (`GET /health`)

## Development Setup

### 1. Create Virtual Environment
```bash
python -m venv .venv
```

### 2. Activate Virtual Environment
**Windows (PowerShell):**
```powershell
.venv\Scripts\Activate.ps1
```

**Windows (cmd):**
```cmd
.venv\Scripts\activate.bat
```

**Linux/macOS:**
```bash
source .venv/bin/activate
```

### 3. Install Dependencies
```bash
pip install -r requirements.txt
```

### 4. Run Tests
```bash
pytest tests -v
```

### 5. Run Development Server
```bash
uvicorn app.main:app --reload --port 8000
```
Open http://127.0.0.1:8000/docs for interactive OpenAPI documentation.
