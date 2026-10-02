# NextAction — Google Auth Configuration Readiness Audit Report

**Audit Date**: 2026-10-02  
**Target Applications**: Flutter Web (`https://nextaction.pages.dev`), Android (`com.nextaction.nextaction`), FastAPI Backend (`https://nextaction-backend-jkrp.onrender.com`), MongoDB Database  
**Workflow Cycle**: Configuration Readiness Audit (No Deployment, No Release, No Git Push)

---

## 1. Audit Summary

| Audit Item | Rating | Summary Finding |
| :--- | :--- | :--- |
| **GOOGLE AUTH IMPLEMENTATION** | **PASS** | Complete backend verification, MongoDB schema/indexes, Flutter services, AuthProvider, and Login UI verified locally. |
| **GOOGLE CLOUD CONFIGURATION** | **REQUIRES USER ACTION** | Google Cloud Console project and OAuth credentials must be set up manually by administrator. |
| **WEB OAUTH** | **REQUIRES USER ACTION** | Client code is ready for `--dart-define=GOOGLE_WEB_CLIENT_ID`; Web Client ID must be created in Google Cloud Console. |
| **ANDROID OAUTH** | **REQUIRES USER ACTION** | Android package `com.nextaction.nextaction` and debug SHA-1 known; release SHA-1 and Android client creation required in Google Cloud Console. |
| **BACKEND CONFIGURATION** | **PASS** | `POST /api/v1/auth/google`, `verify_google_id_token`, audience checks, safe account linking, and error handlers fully tested. |
| **RENDER CONFIGURATION** | **REQUIRES USER ACTION** | `GOOGLE_CLIENT_ID` environment variable must be added in Render Dashboard once client ID is generated. |
| **CLOUDFLARE CONFIGURATION** | **PASS** | Canonical domain `https://nextaction.pages.dev` active and correctly whitelisted in backend CORS. |
| **ANDROID PACKAGE** | **PASS** | Stable package name `com.nextaction.nextaction` verified in Android Gradle configuration. |
| **ANDROID SIGNING** | **REQUIRES USER ACTION** | Local debug keystore fingerprints extracted; production release keystore SHA-1 requires user action. |
| **SECURITY** | **PASS** | Zero hardcoded secrets, cryptographic JWKS token verification, issuer & audience validation, untrusted email rejection, no Google token persistence. |
| **SOURCE CODE STATUS** | **PASS** | No configuration defects or code adjustments required; all components compatible. |
| **TEST STATUS** | **PASS** | 272 backend tests PASS, 145 Flutter unit tests PASS, 11 Flutter widget tests PASS, `flutter analyze` 0 issues. |
| **USER ACTION REQUIRED** | **REQUIRES USER ACTION** | External Google Cloud Console setup and Render environment variable entry pending user action. |
| **PRODUCTION READINESS** | **REQUIRES USER ACTION** | Codebase is 100% production-ready; awaiting external Google Cloud credentials. |
| **DEPLOYMENT** | **NOT VERIFIED** | Deliberately not deployed; current production deployment remains unmodified. |
| **SHOREBIRD** | **NOT VERIFIED** | Deliberately no release or patch created; release 1.0.0+1 remains unchanged. |
| **GIT STATUS** | **PASS** | Changes reside exclusively in local working tree; 0 commits, 0 pushes. |

---

## 2. Detailed Audit Findings

### 2.1. Backend Implementation & Security Verification
- **Verification Engine**: `verify_google_id_token` in `backend/app/core/google_auth.py` utilizes official `google-auth` library (`google.oauth2.id_token`).
- **Cryptographic Signature**: Verified using Google's public key JWKS endpoints (`https://www.googleapis.com/oauth2/v3/certs`).
- **Audience Protection**: The token's `aud` claim is validated against `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_IDS`. Tokens issued for unauthorized client IDs are rejected with HTTP 401 (`INVALID_CREDENTIALS`).
- **Issuer Validation**: Verified against `GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}`.
- **Untrusted Client Data**: The client request body consists exclusively of `{"id_token": "<jwt>"}`. No client-supplied email or user ID is accepted or trusted. The email is extracted from verified token claims and rejected if `email_verified` is not `True`.
- **Log Privacy**: Neither ID tokens, Google credentials, nor user passwords are logged in backend log outputs.

### 2.2. MongoDB Data Modeling & Account Linking
- **Schema**: `UserDocument` in `backend/app/documents/user.py` contains `google_id: Optional[str] = None` and `auth_provider: str = "local"`.
- **Indexing**: A sparse unique index `idx_users_google_id` exists on `users.google_id`.
- **Linking Policy**:
  - If a user exists with matching `google_id`, logs in directly.
  - If a user exists with matching verified `email`, the user's `google_id` is linked without duplicating records or partitioning workflows.
  - If no user exists, a new user is created.
  - Inactive accounts are rejected with HTTP 401 (`INACTIVE_USER`).

### 2.3. Frontend (Flutter Web & Android)
- **Dependency**: `google_sign_in: ^6.2.2` cleanly resolved with 0 analyzer warnings.
- **Architecture**: `AuthProvider` remains the single source of truth. Google Sign-In delegates to `AuthService.signInWithGoogle()`.
- **Session Continuity**: Returned NextAction JWT access token and refresh token are persisted using existing `TokenStorage` and `RefreshTokenStorage`. Google access tokens are discarded.
- **Error & Cancellation Handling**:
  - When the user cancels the Google Sign-In prompt or closes the popup, `AuthService` returns `null`, and `AuthProvider` resets loading state with `errorMessage = null`.
  - The UI does **not** display a false error banner on cancellation.
  - Genuine backend rejection (e.g. invalid signature, inactive user) displays standard `ErrorBanner`.
- **Production URL**:
  - `ApiConfig.baseUrl` in release mode resolves to `https://nextaction-backend-jkrp.onrender.com`.
  - The old URL (`https://nextaction-backend.onrender.com`) is not used.

### 2.4. Android Signing & Identifiers
- **Application ID / Namespace**: `com.nextaction.nextaction` (stable across `build.gradle` and manifest).
- **Debug Fingerprints**:
  - SHA-1: `CE:C1:FA:5D:BD:69:06:B1:CD:86:D6:6D:37:CC:6A:0D:69:CA:31:3D`
  - SHA-256: `49:47:9B:3C:8E:44:F5:55:88:53:CB:54:30:A7:12:6D:EB:D4:2B:CC:3A:FA:54:99:2A:B7:64:20:37:1C:B9:96`
- **Release Fingerprint**: Requires developer's release keystore or Google Play Console app signing certificate.

---

## 3. Exact Google Cloud Console Values Required

The administrator must input the following exact values into Google Cloud Console:

### A. OAuth Consent Screen
- **App Name**: `NextAction`
- **User Support Email**: `bhanuprasad.gundabathina@gmail.com` (or project admin email)
- **Developer Contact**: `bhanuprasad.gundabathina@gmail.com` (or project admin email)
- **Authorized Domain**: `nextaction.pages.dev`
- **Scopes**: `openid`, `email`, `profile`

### B. Web OAuth Client ID
- **Application Type**: `Web application`
- **Name**: `NextAction Web Client`
- **Authorized JavaScript Origins**:
  ```
  https://nextaction.pages.dev
  http://localhost:8000
  http://127.0.0.1:8000
  http://localhost
  http://127.0.0.1
  ```
- **Authorized Redirect URIs**:
  ```
  https://nextaction.pages.dev
  http://localhost:8000
  ```

### C. Android OAuth Client ID
- **Application Type**: `Android`
- **Name**: `NextAction Android App`
- **Package Name**: `com.nextaction.nextaction`
- **SHA-1 Certificate Fingerprint (Debug)**:
  ```
  CE:C1:FA:5D:BD:69:06:B1:CD:86:D6:6D:37:CC:6A:0D:69:CA:31:3D
  ```
- **SHA-1 Certificate Fingerprint (Release)**:
  *Obtain from your release keystore or Google Play App Signing*.

### D. Render Environment Variables
- **Variable**: `GOOGLE_CLIENT_ID`
- **Value**: Enter the generated Web OAuth Client ID (format: `<web-client-id>.apps.googleusercontent.com`).
- **No Client Secret Needed**: ID token verification uses public Google certs.
