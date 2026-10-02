# NextAction — Fix Cycle 01 Report: Initial Web Timeout Banner (BUG-001)

**Date**: October 2, 2026  
**Auditor / Engineer**: Antigravity Automated Engineering Agent  
**Scope**: BUG-001 Remediation, Startup Authentication Error Tolerance, Unit & Widget Regression  
**Bug ID**: BUG-001 (P3 — UI / UX False-Alarm Red Error Banner on Initial Web Load)  
**Status**: **RESOLVED IN LOCAL WORKING TREE (READY FOR DEPLOYMENT / RELEASE)**  

---

## 1. BUG-001 Root Cause Analysis

### Trigger Mechanism
When a user opens the NextAction web application (`https://nextaction.pages.dev`), `main()` in [`apps/mobile_web/lib/main.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/main.dart#L31) invokes:
```dart
authProvider.checkAuthStatus();
```
In [`apps/mobile_web/lib/providers/auth_provider.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/providers/auth_provider.dart#L34-L72), `checkAuthStatus()` performs an opportunistic startup session check:
1. `final hasToken = await _authService.hasStoredToken();` checks local persistent storage (IndexedDB/localStorage on Web).
2. If a token is stored from a previous session, `_authService.getCurrentUser()` makes an authenticated request to `GET /api/v1/auth/me`.
3. Because the Render backend runs on a free tier that hibernates after inactivity, waking up from cold sleep typically takes 20 to 50 seconds.
4. The client HTTP request in [`apps/mobile_web/lib/core/network/api_client.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/core/network/api_client.dart#L245) exceeds the standard `ApiConfig.receiveTimeout` (15 seconds) and throws `TimeoutException`.
5. `ApiClient._sendWithRefresh` catches `TimeoutException` and throws:
   ```dart
   ApiException.network('Request timed out. Please verify your connection.'); // statusCode = 0
   ```
6. In `AuthProvider.checkAuthStatus()` (prior implementation):
   ```dart
   } on ApiException catch (e) {
     await _authService.logout();
     _currentUser = null;
     _status = AuthStatus.unauthenticated;
     if (e.statusCode != 401) {
       _errorMessage = e.message; // <-- Sets 'Request timed out. Please verify your connection.'
     }
   } catch (e) {
     _errorMessage = 'Unable to verify authentication session.';
   }
   ```
7. Because `e.statusCode == 0` (or 502/503/504 gateway response during backend boot), `e.statusCode != 401` evaluated to true, populating `_errorMessage`.
8. `AuthProvider` transitioned state to `AuthStatus.unauthenticated` and notified listeners.
9. `main.dart` rendered [`apps/mobile_web/lib/screens/auth/login_screen.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/screens/auth/login_screen.dart#L90-L97).
10. `LoginScreen` evaluated:
    ```dart
    if (_localError != null || widget.authProvider.errorMessage != null)
      ErrorBanner(
        message: _localError ?? widget.authProvider.errorMessage!,
        ...
      )
    ```
    This displayed the red error banner before the user had touched or interacted with the screen. Furthermore, calling `await _authService.logout()` unnecessarily purged valid stored credentials simply because the backend was in a cold-start state.

---

## 2. Exact Files and Functions Involved

| File | Function / Component | Role in Bug |
| :--- | :--- | :--- |
| [`apps/mobile_web/lib/providers/auth_provider.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/providers/auth_provider.dart#L34-L72) | `AuthProvider.checkAuthStatus()` | Populated `_errorMessage` on non-401 startup failures and purged valid tokens on timeout. |
| [`apps/mobile_web/lib/screens/auth/login_screen.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/screens/auth/login_screen.dart#L90-L97) | `LoginScreen.build()` | Rendered `ErrorBanner` when `widget.authProvider.errorMessage != null`. |
| [`apps/mobile_web/lib/core/network/api_client.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/core/network/api_client.dart#L308) | `ApiClient._sendWithRefresh()` | Formatted timeout as `ApiException.network('Request timed out. Please verify your connection.')` with `statusCode: 0`. |

---

## 3. Fix Implemented

The fix is minimal, precise, and contained strictly within `AuthProvider.checkAuthStatus()` in [`apps/mobile_web/lib/providers/auth_provider.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/providers/auth_provider.dart#L53-L70):

```dart
    } on ApiException catch (e) {
      debugPrint('[AuthProvider] Startup auth check failed: ${e.message} (${e.statusCode})');
      if (e.statusCode == 401) {
        // Token is definitively invalid, expired, or rejected by backend
        await _authService.logout();
      }
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      // Do not set _errorMessage on startup failure; keep Login/Register screen clean
      _errorMessage = null;
    } catch (e) {
      debugPrint('[AuthProvider] Startup auth check unexpected error: $e');
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
    } finally {
      notifyListeners();
    }
```

---

## 4. Why the Fix Prevents the Premature Banner

1. **Clean Unauthenticated Landing**: During initial app boot, `checkAuthStatus()` is a background convenience check to restore an existing session. When a timeout or cold-start condition occurs, `_errorMessage` remains `null`. The user transitions cleanly into `AuthStatus.unauthenticated` without any red error banner.
2. **Background Cold-Start Toleration**: The Login/Register screen is rendered immediately in its clean default state. While the user is looking at the screen or typing credentials, the Render free backend finishes booting in the background.
3. **Token Preservation**: Stored credentials are only purged if the backend explicitly returns HTTP 401 (token expired/invalid). A network timeout does not delete the stored token, allowing a subsequent page reload (or background reconnect) to restore the session automatically without re-entering credentials.
4. **No Global Timeout Distortions**: Avoided arbitrary increases in global timeout constants (`connectTimeout = 10s`, `receiveTimeout = 15s`), keeping user-facing latency fast and responsive across all regular API calls.
5. **No Infinite Loops**: No recurring retry loop was introduced; the check executes once on startup and cleanly settles state.

---

## 5. Error-Handling Behavior After the Fix

| Scenario | State Transition | `errorMessage` | UI Presentation |
| :--- | :--- | :--- | :--- |
| **Initial Boot (Backend Cold / Timeout)** | `checking` -> `unauthenticated` | `null` | **Clean Login screen** (No error banner). |
| **Initial Boot (No Stored Token)** | `checking` -> `unauthenticated` | `null` | **Clean Login screen** (No error banner). |
| **Initial Boot (Valid Token, Backend Live)** | `checking` -> `authenticated` | `null` | **Home screen** with user dashboard. |
| **Initial Boot (Token Expired / 401)** | `checking` -> `unauthenticated` | `null` | **Clean Login screen**; local token deleted. |
| **User-Triggered Login (Timeout / Cold)** | Remains `unauthenticated` | `'Request timed out. Please verify your connection.'` | **Red Error Banner** rendered for direct user feedback. |
| **User-Triggered Login (Invalid Credentials 401)** | Remains `unauthenticated` | `'Invalid email or password'` | **Red Error Banner** rendered with backend error message. |
| **User-Triggered Register (Network Timeout)** | Stays on Register | `'Request timed out. Please verify your connection.'` | **Red Error Banner** rendered on register form. |
| **Mid-Session Expiry (401 on authenticated API)** | `authenticated` -> `unauthenticated` | `'Your session has expired. Please sign in again.'` | **Session Expired Banner** rendered upon redirection to login. |
| **Task / Workflow CRUD API Errors** | Screen-specific state | API / Network message | Standard error banners within respective screens. |

Zero user-action errors are swallowed. Genuine failures caused by user actions continue to surface immediately and visibly.

---

## 6. Tests Added / Updated

### Unit Tests ([`apps/mobile_web/test/unit/auth_provider_test.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/test/unit/auth_provider_test.dart#L154-L242))
- `checkAuthStatus with network timeout transitions to unauthenticated without setting errorMessage and preserves token`: Verifies that a `TimeoutException` during startup moves to `AuthStatus.unauthenticated`, sets `errorMessage: null`, and retains the token in storage.
- `checkAuthStatus with 503 Service Unavailable (cold start waking) transitions to unauthenticated without setting errorMessage`: Verifies that a 503 response from a waking server keeps `errorMessage: null`.
- `login failure with timeout still sets errorMessage for user feedback`: Verifies that a user-triggered `login()` call timing out correctly populates `errorMessage` with the timeout banner message.
- `login failure with 401 still sets errorMessage for user feedback`: Verifies that invalid credentials during `login()` surface the backend message.
- `register failure with network timeout still sets errorMessage for user feedback`: Verifies that user registration timeouts properly populate `errorMessage`.

### Widget Tests ([`apps/mobile_web/test/widget_test.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/test/widget_test.dart#L62-L130))
- `initial load with network timeout renders clean LoginScreen without red error banner`: Simulates app boot with existing token and a network timeout. Verifies `find.byType(LoginScreen)` is present, while `find.byType(ErrorBanner)` and `find.text('Request timed out...')` are completely absent.
- `submitting login form with network timeout displays error banner for user feedback`: Verifies that entering email/password on the clean Login screen and tapping "Sign In" during a timeout correctly renders `ErrorBanner` with `'Request timed out. Please verify your connection.'`.

---

## 7. Verification and Test Results

### 1. Flutter Static Analysis
- **Command**: `flutter analyze`
- **Working Directory**: `apps/mobile_web`
- **Result**: **No issues found!** (ran in 16.3s)

### 2. Flutter Test Suite
- **Command**: `flutter test test/widget_test.dart test/unit`
- **Working Directory**: `apps/mobile_web`
- **Result**: **145 passed, 0 failed** (ran in ~7s)
  - 138 original tests: **PASS**
  - 7 newly added tests: **PASS**

### 3. Backend Test Suite
- **Command**: `backend\.venv\Scripts\python.exe -m pytest backend\tests`
- **Working Directory**: `c:\bhanu\NEXT ACTION`
- **Result**: **260 passed, 3 warnings in 327.33s (05:27)**
  - All 260 backend integration, domain, security, and repository tests passed with zero failures.

---

## 8. Regression Assessment

- **Risk Level**: Very Low.
- **Scope of Impact**: Strictly isolates the startup authentication check (`checkAuthStatus`).
- **No Side Effects**:
  - No changes to API routes, MongoDB models, database connections, or server configuration.
  - No changes to Cloudflare deployment settings or public URLs.
  - No changes to user-initiated authentication (`login`, `register`, `changePassword`, `logout`).
  - No changes to task, client, workflow, or reporting business logic.

---

## 9. Changed Files Summary

| File | Status | Description of Change |
| :--- | :--- | :--- |
| [`apps/mobile_web/lib/providers/auth_provider.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/providers/auth_provider.dart) | Modified | Updated `checkAuthStatus()` catch blocks to keep `_errorMessage = null` on startup timeouts/cold-starts and preserve valid tokens. |
| [`apps/mobile_web/test/unit/auth_provider_test.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/test/unit/auth_provider_test.dart) | Modified | Added 5 unit tests covering startup timeout tolerance, 503 cold-start handling, and user-initiated login/registration error preservation. |
| [`apps/mobile_web/test/widget_test.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/test/widget_test.dart) | Modified | Added 2 widget tests validating that startup timeouts render a clean `LoginScreen` and form submissions render `ErrorBanner`. |

---

## 10. Operational Status

- **Production Deployment**: **NOT DEPLOYED** (per instruction, no deployment performed)
- **Shorebird Status**: **NO PATCH CREATED** (per instruction, baseline release 1.0.0+1 active, no patch released)
- **Git Status**: Changes unstaged in working directory; zero commits or pushes created.
