# Phase 6 — Flutter ↔ FastAPI Integration & Authenticated App Foundation Documentation

## 1. Overview & Architecture

Phase 6 connects the Flutter frontend (`apps/mobile_web/`) to the real FastAPI backend and PostgreSQL database. It establishes the client networking layer, secure token storage, authentication state machine, and real task lifecycle interactions (attempts, max attempts enforcement, authorized override, postponement, completion, and reopening).

### High-Level Architecture

```
Flutter Client (apps/mobile_web/)
   │
   ├── UI Layer (Screens & Widgets)
   │     ├── LoginScreen & RegisterScreen
   │     ├── HomeScreen (Session profile & navigation)
   │     └── TaskListScreen, TaskDetailScreen, TaskCreateScreen
   │
   ├── State Management Layer (ChangeNotifier / AnimatedBuilder)
   │     └── AuthProvider (checking, unauthenticated, authenticated, error)
   │
   ├── Service Layer
   │     ├── AuthService (register, login, me, logout)
   │     └── TaskService (CRUD, attempts, overrides, postpone, reopen, history)
   │
   ├── Core Networking & Storage
   │     ├── ApiConfig (Dynamic base URL for Web, Android emulator, Desktop)
   │     ├── ApiClient (JSON serialization, Bearer token injection, error mapping)
   │     ├── SecureTokenStorage (flutter_secure_storage / platform keystores)
   │     └── ApiException (Centralized domain error parsing)
   │
   ▼ HTTP (REST / JSON)
FastAPI Backend (backend/app/)
   │
   ├── CORS Middleware (Development origins & localhost regex)
   ├── JWT Bearer Authentication Dependency (HTTPBearer)
   ├── Centralized Domain Exception Handlers (401, 404, 409, 422)
   └── Service & Repository Layer
         │
         ▼ SQLAlchemy 2.0 (psycopg3)
PostgreSQL 16 Database
```

---

## 2. Dependencies

The following dependencies were added to `apps/mobile_web/pubspec.yaml`:

- **`http: ^1.2.0`**: Standard, lightweight, official Dart HTTP package providing multi-platform network requests (Web, Android, Desktop, iOS) and direct compatibility with `MockClient` for fast unit tests.
- **`flutter_secure_storage: ^10.3.4`**: Hardware-backed local token persistence using Android Keystore/EncryptedSharedPreferences, Windows DPAPI, macOS Keychain, Linux libsecret, and Web Crypto storage.
- **`intl: ^0.20.2`**: Standard date and time formatting utilities for task due dates and audit history timestamps.

---

## 3. Centralized API Base URL Configuration

The API base URL is resolved dynamically in `lib/core/config/api_config.dart` rather than hardcoded:

- **Web Development**: `http://127.0.0.1:8000` (or `http://localhost:8000`)
- **Android Emulator**: `http://10.0.2.2:8000` (routes to host machine's `127.0.0.1`)
- **Desktop (Windows/macOS/Linux)**: `http://127.0.0.1:8000`
- **Environment Variable Override**: Supports `--dart-define=API_BASE_URL=http://<custom-host>:<port>` at build/run time.
- **Runtime Override**: `ApiConfig.setBaseUrl('http://...')` for programmatic test configuration.

---

## 4. API Client & HTTP Interception

The `ApiClient` (`lib/core/network/api_client.dart`) centralizes all outgoing HTTP communication:
- **Base URL resolution**: Appends endpoint paths to `ApiConfig.v1BaseUrl`.
- **Automatic Header Injection**: Automatically attaches `Content-Type: application/json`, `Accept: application/json`.
- **JWT Authorization**: Inspects `TokenStorage.getToken()`. If present, automatically attaches `Authorization: Bearer <access_token>`.
- **Error Normalization**: Maps non-2xx HTTP responses into typed `ApiException` instances with machine error codes (`MAX_ATTEMPTS_REACHED`, `INVALID_CREDENTIALS`, `TASK_ALREADY_COMPLETED`, `TASK_NOT_FOUND`, `USER_ALREADY_EXISTS`, etc.).
- **Session Expiry Hook**: Triggers `onUnauthorized` callback upon receiving HTTP 401.

---

## 5. Local Token Storage & Platform Security Considerations

Token persistence is implemented in `lib/core/storage/token_storage.dart` (`SecureTokenStorage`):
- **Stored Data**: Only the signed JWT `access_token`.
- **Forbidden Data**: Passwords, password hashes, and JWT secret keys are never stored locally.
- **Methods**: `saveToken(String)`, `getToken()`, `deleteToken()`, `hasToken()`.

### Platform Implementations & Limitations:
1. **Android**: Uses Android Keystore and AES-256 encrypted storage.
2. **Windows**: Uses Windows Data Protection API (DPAPI).
3. **macOS / iOS**: Uses Keychain Services.
4. **Linux**: Uses `libsecret`.
5. **Web Limitation**: On Flutter Web, `flutter_secure_storage` utilizes Web Cryptography API backed by `localStorage` / `IndexedDB`. Because browser JavaScript executed in the same origin has access to local storage, Web storage cannot offer the same hardware-level memory isolation as native mobile/desktop platforms and is vulnerable to Cross-Site Scripting (XSS) if client-side injection is present.

---

## 6. Authentication State Machine

The `AuthProvider` (`lib/providers/auth_provider.dart`) manages the authentication lifecycle through four distinct states:
1. **`checking`**: Initial state during app launch while validating existing local storage.
2. **`unauthenticated`**: No token exists or stored token failed backend verification (`/api/v1/auth/me`).
3. **`authenticated`**: Stored token was successfully validated against `/api/v1/auth/me` and the active `User` model is loaded.
4. **`error`**: Network or unexpected connection failure during authentication.

### Startup Verification Flow:
1. Check `TokenStorage.hasToken()`.
2. If `false`: transition immediately to `unauthenticated`.
3. If `true`: call `GET /api/v1/auth/me`.
4. If HTTP 200: populate `_currentUser` and transition to `authenticated`.
5. If HTTP 401 or invalid: invoke `TokenStorage.deleteToken()`, clear user, and transition to `unauthenticated`.

*Note: The backend `/auth/me` endpoint is always the authoritative source of truth. The frontend never trusts local token presence alone.*

---

## 7. Authentication Flow & Screens

### A. Login Flow (`lib/screens/auth/login_screen.dart`)
1. User enters email and password.
2. Form validates required fields and email regex format.
3. Client dispatches `POST /api/v1/auth/login`.
4. FastAPI validates credentials against PostgreSQL `password_hash` via bcrypt.
5. On success: JWT `access_token` returned, saved to `SecureTokenStorage`, `/auth/me` loaded, app renders `HomeScreen`.
6. On error: Backend error code (`INVALID_CREDENTIALS`, `INACTIVE_USER`) mapped to friendly UI banner.

### B. Registration Flow (`lib/screens/auth/register_screen.dart`)
1. User enters name, email, password (min 6 characters).
2. Client dispatches `POST /api/v1/auth/register`.
3. FastAPI creates user with bcrypt-hashed password in PostgreSQL.
4. On success: Returns to `LoginScreen` with green confirmation banner informing user to sign in.

### C. Logout Flow
1. User clicks Logout action in `HomeScreen` AppBar.
2. App prompts confirmation dialog.
3. On confirmation: `AuthProvider.logout()` deletes stored JWT and transitions state to `unauthenticated`.
4. `MaterialApp` immediately re-renders `LoginScreen`.

---

## 8. Task API Integration & Real Interactions

The `TaskService` (`lib/services/task/task_service.dart`) implements all task operations against FastAPI:

| Operation | HTTP Endpoint | Description |
|-----------|---------------|-------------|
| List Tasks | `GET /api/v1/tasks` | Loads paginated tasks from PostgreSQL |
| Get Task | `GET /api/v1/tasks/{id}` | Loads single task by UUID |
| Create Task | `POST /api/v1/tasks` | Creates real task in PostgreSQL |
| Update Task | `PATCH /api/v1/tasks/{id}` | Updates title, description, subject line |
| Normal Attempt | `POST /api/v1/tasks/{id}/attempt` | Increments `attempt_count`. Enforces max attempts (409 on overflow). |
| Authorized Override | `POST /api/v1/tasks/{id}/attempt/override` | Records attempt beyond limit with mandatory justification reason. |
| Postpone Task | `POST /api/v1/tasks/{id}/postpone` | Updates `due_date` with mandatory justification reason. |
| Update Next Action | `POST /api/v1/tasks/{id}/next-action` | Updates `next_action_date`. |
| Complete Task | `POST /api/v1/tasks/{id}/complete` | Sets status to `completed` and sets `completed_at`. |
| Reopen Task | `POST /api/v1/tasks/{id}/reopen` | Reopens completed task with mandatory justification reason. |
| Task History | `GET /api/v1/tasks/{id}/history` | Retrieves immutable chronological audit log. |
| Task Follow-ups | `GET /api/v1/tasks/{id}/follow-ups` | Retrieves follow-up records for task. |

---

## 9. Attempt & Authorized Override Behavior

1. **Normal Work Attempt**:
   - When `attempt_count < max_attempts`, user clicks "Record Attempt".
   - Client sends `POST /api/v1/tasks/{id}/attempt` with optional notes.
   - Backend increments `attempt_count` and logs `attempt` in `task_histories`.

2. **Max Attempts Enforced (409 Conflict)**:
   - When `attempt_count >= max_attempts`, backend rejects normal attempts with `409 MAX_ATTEMPTS_REACHED`.
   - Flutter UI catches this and presents a clear dialog: *"A standard attempt cannot be recorded. An authorized override with mandatory business justification is required."*

3. **Authorized Override Flow**:
   - User triggers "Authorized Override" dialog.
   - Requires non-empty justification string (e.g. *"Client requested escalation meeting"*).
   - Sends `authorized_override: true` and `reason` to `POST /api/v1/tasks/{id}/attempt/override`.
   - Backend records `attempt_override` in `task_histories` and increments attempt count.

---

## 10. CORS & Web Development Configuration

To allow Flutter Web development across local development server ports without opening insecure wildcards:
- Configured explicit development origins: `http://localhost`, `http://localhost:8000`, `http://localhost:8080`, `http://localhost:3000`, `http://localhost:5000`, `http://127.0.0.1`, `http://127.0.0.1:8000`, etc.
- Configured local development origin regex: `r"^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$"`
- `allow_credentials=True`
- Registered in `backend/app/main.py` via `CORSMiddleware`.

---

## 11. Testing & Verification

### Flutter Unit & Widget Tests:
Run:
```powershell
cd "apps/mobile_web"
flutter test --suppress-analytics
```
**Results**: 36/36 tests passed (0 failed).

### Backend Pytest Suite:
Run:
```powershell
& ".\backend\.venv\Scripts\python.exe" -m pytest backend/tests -v
```
**Results**: 47/47 tests passed (0 failed, 0 skipped).

### Live End-to-End Verification:
Run:
```powershell
flutter test test/integration/phase6_auth_flow_test.dart --suppress-analytics
```
**Results**: All 11 workflow steps verified against live FastAPI and PostgreSQL.
