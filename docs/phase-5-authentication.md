# NextAction Phase 5: Authentication & Authorization

## 1. Executive Summary & Architecture
Phase 5 implements a robust, secure authentication and authorization foundation for NextAction using **bcrypt** password hashing, **JWT (JSON Web Tokens)**, and FastAPI dependency injection.

```
Client (Web / Flutter / Postman)
             ↓  (POST /api/v1/auth/login)
      Auth Service & bcrypt
             ↓  (issues JWT Access Token)
Client receives { "access_token": "...", "token_type": "bearer", "expires_in": 3600 }
             ↓  (Authorization: Bearer <token>)
FastAPI Dependency (get_current_user)
             ↓  (Validates signature, exp, loads active User)
Protected Routes & Service Invocations (Actor derived strictly from JWT)
```

---

## 2. User Model Changes & Database Migration

### 2.1 Schema Updates on `users` Table
- `password_hash`: `VARCHAR(255)`, `NOT NULL` (with server default `''` to preserve existing development records).
- `is_active`: `BOOLEAN`, `NOT NULL` (with server default `TRUE`).
- Existing columns preserved: `id` (UUID PK), `name` (VARCHAR), `email` (VARCHAR UNIQUE INDEX), `created_at` (TIMESTAMPTZ), `updated_at` (TIMESTAMPTZ).

### 2.2 Alembic Migration
- **Revision ID**: `7efe29531b9e`
- **Migration File**: `backend/alembic/versions/7efe29531b9e_add_password_hash_and_is_active_to_users.py`
- **Current Head**: `7efe29531b9e`

---

## 3. Security Configuration & Environment Variables

Authentication parameters are managed via `pydantic-settings` in `backend/app/core/config.py` and configurable via `.env`:

| Environment Variable | Default | Purpose |
|---|---|---|
| `JWT_SECRET_KEY` | `dev_secret_key_...` | HMAC secret for signing and verifying JWTs (override in production) |
| `JWT_ALGORITHM` | `HS256` | Cryptographic algorithm for JWT encoding |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `60` | Token lifetime before expiration |

*(Note: Secrets are omitted from source control and documentation).*

---

## 4. Password Security & Cryptography
- **Library**: `bcrypt` (v5.0.0).
- **Hashing**: Plaintext passwords are salted and hashed using `bcrypt.gensalt()` and `bcrypt.hashpw()`.
- **Verification**: `bcrypt.checkpw()` provides secure constant-time password verification to prevent timing attacks.
- **Data Protection**: Plaintext passwords and `password_hash` strings are strictly excluded from API response schemas (`UserResponse`), logs, and database audit logs (`TaskHistory`).

---

## 5. Authentication Service Layer (`auth_service.py`)
- `register_user(db, name, email, password)`: Normalizes email (case-insensitive, whitespace-trimmed), checks email uniqueness (raises `UserAlreadyExistsError` / HTTP 409), hashes password, and persists user.
- `authenticate_user(db, email, password)`: Validates credentials, checks `is_active`, and issues JWT access token (raises `InvalidCredentialsError` / HTTP 401 on bad password or unknown user without disclosing existence; raises `InactiveUserError` on disabled accounts).
- `get_user_by_id(db, user_id)`: Retrieves active user or raises `UserNotFoundError` / `InactiveUserError`.
- `get_user_by_email(db, email)`: Case-insensitive email lookup.

---

## 6. Endpoints Reference

### 6.1 Authentication Routes (`/api/v1/auth`)
| Method | Path | Summary | Auth Required | Status Code |
|---|---|---|---|---|
| `POST` | `/api/v1/auth/register` | Register a new user account | No (Public) | `201 Created` |
| `POST` | `/api/v1/auth/login` | Authenticate and obtain JWT token | No (Public) | `200 OK` |
| `GET` | `/api/v1/auth/me` | Retrieve authenticated user profile | **Yes (Bearer)** | `200 OK` |

### 6.2 Protected Domain Routes
All domain routes under the following prefixes now strictly require a valid JWT token:
- `/api/v1/tasks/*` (16 endpoints)
- `/api/v1/reminders/*` (4 endpoints)
- `/api/v1/follow-ups/*` (3 endpoints)

### 6.3 Public Routes
- `GET /health` (System health check)
- `GET /docs`, `GET /redoc`, `GET /openapi.json` (OpenAPI documentation)

---

## 7. Actor Identity Security & Spoofing Prevention
A critical architectural principle is enforced across all operational endpoints:
- **Actor Identity**: The actor performing an action (`created_by_user_id`, `user_id` for history records, `assigned_by_user_id` for reassignments) is **always** extracted from the verified JWT via `current_user.id`.
- **Spoofing Prevention**: Any client-supplied `user_id` or `created_by_user_id` in request payloads is ignored for actor identity.
- **Target vs Actor**: In assignment endpoints (`POST /api/v1/tasks/{id}/assign`), the target assignee (`assigned_user_id`) comes from the payload, while the assigner (`assigned_by_user_id`) is strictly bound to `current_user.id`.

---

## 8. Testing & Swagger Usage

### 8.1 Running Test Suites
```powershell
& ".\backend\.venv\Scripts\python.exe" -m pytest backend/tests -v
```

### 8.2 Using Swagger UI (`/docs`) with Bearer Authentication
1. Navigate to `http://localhost:8000/docs`.
2. Execute `POST /api/v1/auth/login` with valid credentials.
3. Copy the returned `access_token`.
4. Click the green **Authorize** button at the top of Swagger UI.
5. Paste the token into the `Value` box and click **Authorize**.
6. All subsequent interactive requests will include the `Authorization: Bearer <token>` header.

---

## 9. Security Limitations & Roadmap for Future Phases
- **Refresh Tokens**: Not implemented in Phase 5; short-lived access tokens expire in 60 minutes.
- **Role-Based Access Control (RBAC)**: Basic active-user verification is implemented; granular roles and permissions will be designed in a dedicated phase.
- **Password Reset / MFA / OAuth**: Reserved for subsequent milestone phases.
