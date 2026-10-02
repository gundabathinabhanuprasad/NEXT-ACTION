# NextAction Phase 4: FastAPI REST API Layer

## 1. Executive Summary & Architecture
Phase 4 exposes the core domain services developed in Phase 3 through a thin, idiomatic **FastAPI REST API**. The architecture enforces separation of concerns:

```
Flutter / Web Client
       ↓
FastAPI Router (/api/v1/...)
       ↓
Pydantic Request / Response DTOs
       ↓
Service Layer (backend/app/services/)
       ↓
SQLAlchemy 2.0 ORM
       ↓
PostgreSQL 16 (Container)
```

No business rules exist within route handlers. All operations, validations, transaction boundaries, and audit logging are delegated to the underlying service layer.

---

## 2. API Endpoints Reference

### 2.1 System Endpoints
| Method | Path | Summary | Success Code |
|---|---|---|---|
| `GET` | `/health` | System health check and database connectivity | `200 OK` |
| `GET` | `/docs` | Interactive Swagger UI documentation | `200 OK` |
| `GET` | `/openapi.json` | OpenAPI v3 JSON specification | `200 OK` |

### 2.2 Tasks API (`/api/v1/tasks`)
| Method | Path | Summary | Success Code |
|---|---|---|---|
| `POST` | `/api/v1/tasks` | Create a new task | `201 Created` |
| `GET` | `/api/v1/tasks` | List & filter tasks (paginated) | `200 OK` |
| `GET` | `/api/v1/tasks/{task_id}` | Get task details by ID | `200 OK` |
| `PATCH` | `/api/v1/tasks/{task_id}` | Update basic task fields | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/attempt` | Record normal work attempt | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/attempt/override` | Record authorized override attempt | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/postpone` | Postpone task due date | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/next-action` | Update next action date | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/complete` | Mark task as completed | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/reopen` | Reopen completed task | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/status` | Change task status | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/priority` | Change task priority | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/assign` | Assign or reassign user | `200 OK` |
| `POST` | `/api/v1/tasks/{task_id}/subject-line` | Update subject line | `200 OK` |
| `GET` | `/api/v1/tasks/{task_id}/history` | Get task audit history logs | `200 OK` |
| `GET` | `/api/v1/tasks/{task_id}/follow-ups` | List follow-ups for task | `200 OK` |

### 2.3 Reminders API (`/api/v1/reminders`)
| Method | Path | Summary | Success Code |
|---|---|---|---|
| `POST` | `/api/v1/reminders` | Create a new reminder | `201 Created` |
| `GET` | `/api/v1/reminders/due` | List due/pending reminders | `200 OK` |
| `GET` | `/api/v1/reminders/{reminder_id}` | Get reminder by ID | `200 OK` |
| `POST` | `/api/v1/reminders/{reminder_id}/send` | Process & mark reminder as sent | `200 OK` |

### 2.4 Follow-Ups API (`/api/v1/follow-ups`)
| Method | Path | Summary | Success Code |
|---|---|---|---|
| `POST` | `/api/v1/follow-ups` | Create a new follow-up | `201 Created` |
| `GET` | `/api/v1/follow-ups/{follow_up_id}` | Get follow-up by ID | `200 OK` |
| `POST` | `/api/v1/follow-ups/{follow_up_id}/complete` | Complete follow-up action | `200 OK` |

---

## 3. Standardized Error Format & Domain Mappings

When a business rule or entity lookup fails, the API responds with a structured JSON payload:
```json
{
  "error": "ERROR_CODE",
  "message": "Human readable explanation"
}
```

### Exception Mapping Table
| Domain Exception | HTTP Status | Error Code |
|---|---|---|
| `TaskNotFoundError` | `404 Not Found` | `TASK_NOT_FOUND` |
| `ReminderNotFoundError` | `404 Not Found` | `REMINDER_NOT_FOUND` |
| `FollowUpNotFoundError` | `404 Not Found` | `FOLLOW_UP_NOT_FOUND` |
| `TaskAlreadyCompletedError` | `409 Conflict` | `TASK_ALREADY_COMPLETED` |
| `TaskCompletedError` | `409 Conflict` | `TASK_COMPLETED` |
| `TaskCancelledError` | `409 Conflict` | `TASK_CANCELLED` |
| `TaskNotCompletedError` | `409 Conflict` | `TASK_NOT_COMPLETED` |
| `MaxAttemptsReachedError` | `409 Conflict` | `MAX_ATTEMPTS_REACHED` |
| `InvalidTaskStateError` | `409 Conflict` | `INVALID_TASK_STATE` |
| `InvalidStatusTransitionError` | `409 Conflict` | `INVALID_STATUS_TRANSITION` |
| `OverrideReasonRequiredError` | `400 Bad Request` | `OVERRIDE_REASON_REQUIRED` |
| `PostponementReasonRequiredError` | `400 Bad Request` | `POSTPONEMENT_REASON_REQUIRED` |
| `ReopenReasonRequiredError` | `400 Bad Request` | `REOPEN_REASON_REQUIRED` |
| `InvalidTaskDateError` | `400 Bad Request` | `INVALID_TASK_DATE` |

---

## 4. Example Requests & Responses

### 4.1 Create Task
**Request (`POST /api/v1/tasks`)**:
```json
{
  "title": "Client Review Meeting",
  "description": "Quarterly audit feedback",
  "subject_line": "Q3 Feedback",
  "due_date": "2026-10-01T12:00:00Z",
  "max_attempts": 2
}
```
**Response (`201 Created`)**:
```json
{
  "id": "6e044d92-46d0-4a72-80c2-8318c0522b9c",
  "title": "Client Review Meeting",
  "description": "Quarterly audit feedback",
  "subject_line": "Q3 Feedback",
  "client_id": null,
  "workflow_id": null,
  "assigned_user_id": null,
  "status": "pending",
  "priority": "medium",
  "due_date": "2026-10-01T12:00:00Z",
  "next_action_date": null,
  "attempt_count": 0,
  "max_attempts": 2,
  "completed_at": null,
  "created_at": "2026-09-27T08:25:28.460829Z",
  "updated_at": "2026-09-27T08:25:28.460829Z"
}
```

### 4.2 Record Attempt Beyond Max (Rejection)
**Request (`POST /api/v1/tasks/{id}/attempt`)**:
```json
{
  "notes": "Attempt 3 after max reached"
}
```
**Response (`409 Conflict`)**:
```json
{
  "error": "MAX_ATTEMPTS_REACHED",
  "message": "Maximum attempts reached for task '6e044d92-46d0-4a72-80c2-8318c0522b9c' (2/2). Authorized override required."
}
```

### 4.3 Authorized Override
**Request (`POST /api/v1/tasks/{id}/attempt/override`)**:
```json
{
  "authorized_override": true,
  "reason": "Executive authorization granted for follow-up"
}
```
**Response (`200 OK`)**:
```json
{
  "id": "6e044d92-46d0-4a72-80c2-8318c0522b9c",
  "attempt_count": 3
}
```

---

## 5. Development & Testing Instructions

### 5.1 Starting the FastAPI Development Server
From the project root (`C:\bhanu\NEXT ACTION`):
```powershell
& ".\backend\.venv\Scripts\python.exe" -m uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port 8000 --reload
```

### 5.2 Running the Backend Test Suite
```powershell
& ".\backend\.venv\Scripts\python.exe" -m pytest backend/tests -v
```

### 5.3 OpenAPI Documentation
When the server is running, interactive API docs are available at:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`
- OpenAPI JSON: `http://localhost:8000/openapi.json`
