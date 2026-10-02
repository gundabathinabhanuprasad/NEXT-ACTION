# NextAction — Google Authentication Setup & Integration Guide

This document specifies the technical architecture, configuration requirements, environment variables, and setup instructions for **Google Authentication** across the NextAction platform (FastAPI backend, MongoDB database, Flutter Web, and Android).

---

## 1. Authentication Architecture

NextAction implements a **hybrid server-side credential verification flow** that maintains NextAction's existing JWT session security model without using raw Google tokens as long-term application sessions.

```
                      +-----------------------------+
                      |       User Interface        |
                      |   [ Continue with Google ]  |
                      +--------------+--------------+
                                     |
                                     | 1. Google OAuth flow
                                     v
                      +-----------------------------+
                      |    Google Identity Server   |
                      +--------------+--------------+
                                     |
                                     | 2. Google Credential (ID Token)
                                     v
                      +-----------------------------+
                      |     Flutter Application     |
                      |  (Web / Android / Desktop)  |
                      +--------------+--------------+
                                     |
                                     | 3. POST /api/v1/auth/google
                                     |    {"id_token": "<google_jwt>"}
                                     v
                      +-----------------------------+
                      |       FastAPI Backend       |
                      | - Validates Google signature|
                      | - Checks audience/client_id |
                      | - Checks expiration & issuer|
                      | - Extracts verified identity|
                      +--------------+--------------+
                                     |
                                     | 4. Safe Account Linking / Create
                                     v
                      +-----------------------------+
                      |      MongoDB Database       |
                      | - Match by google_id        |
                      | - Else match verified email |
                      | - Else provision new user   |
                      +--------------+--------------+
                                     |
                                     | 5. Issue NextAction Tokens
                                     v
                      +-----------------------------+
                      |   Standard NextAction JWT   |
                      | - Access Token (15m - 2h)   |
                      | - Refresh Token (7 days)    |
                      +-----------------------------+
```

### Key Principles:
1. **Google Tokens are NOT Application Sessions**: Google ID tokens are strictly used for initial credential exchange during authentication. The backend validates the Google credential and issues standard NextAction access and refresh tokens.
2. **Never Trust Client-Reported Identity**: The backend never trusts client-supplied emails or user names. All identity information (`email`, `name`, `sub`) is extracted directly from the cryptographically verified Google ID token claims.
3. **Existing Session Architecture Preserved**: Token storage (`TokenStorage`, `RefreshTokenStorage`), request headers (`Authorization: Bearer <token>`), automatic refresh on 401, and profile retrieval (`/api/v1/auth/me`) remain 100% identical.

---

## 2. Safe Account Linking Policy

NextAction employs an explicit, deterministic account-linking policy:

1. **Existing Google User (`google_id` match)**:
   - If a user record already contains the verified `google_id` (Google `sub`), the user is authenticated directly.
2. **Existing Email/Password Account (Verified Email match)**:
   - If an existing user registered with the same verified email address (`email_verified == true`), NextAction safely links the account by updating `google_id` on the user record.
   - The user can subsequently log in using **either** Google Sign-In or their existing email/password credentials.
   - No duplicate user accounts or split workspaces are created.
3. **New User Provisioning**:
   - If no existing user matches `google_id` or `email`, a new user record is created with:
     - `email`: Verified email from Google credential.
     - `name`: Display name from Google credential.
     - `google_id`: Google subject identifier (`sub`).
     - `auth_provider`: `"google"`.
     - `is_active`: `true`.
4. **Inactive User Protection**:
   - If an account exists but has been marked inactive (`is_active == false`), authentication is rejected with `HTTP 401 Unauthorized` (`INACTIVE_USER`).

---

## 3. Google Cloud Console Configuration Requirements

> [!IMPORTANT]
> The following configuration steps must be performed in the **Google Cloud Console** by the project administrator. No real credentials or client secrets are committed to this repository.

### Step 1: Create or Select Google Cloud Project
1. Navigate to [Google Cloud Console](https://console.cloud.google.com/).
2. Select your organization/project (e.g. `NextAction`).

### Step 2: Configure OAuth Consent Screen
1. Go to **APIs & Services** > **OAuth consent screen**.
2. Select **External** (or Internal for workspace-only).
3. Fill in required application branding:
   - **App name**: `NextAction`
   - **User support email**: Administrator email
   - **Developer contact information**: Project contact email
4. Scopes: Add `openid`, `email`, `profile`.

---

## 4. Platform-Specific OAuth Client Setup

### A. Flutter Web Configuration

1. In Google Cloud Console, go to **Credentials** > **Create Credentials** > **OAuth client ID**.
2. Select **Application type**: **Web application**.
3. **Name**: `NextAction Web Client`.
4. **Authorized JavaScript origins**:
   - Development:
     - `http://localhost`
     - `http://localhost:8000`
     - `http://127.0.0.1`
     - `http://127.0.0.1:8000`
   - Production:
     - `https://nextaction.pages.dev`
5. **Authorized redirect URIs**:
   - `https://nextaction.pages.dev`
6. Click **Create** and record the generated **Client ID** (e.g., `1234567890-xxx.apps.googleusercontent.com`).

#### Web Compilation Flag:
When building or running Flutter Web, pass the Client ID via `--dart-define`:
```bash
flutter run -d chrome --dart-define=GOOGLE_WEB_CLIENT_ID=1234567890-xxx.apps.googleusercontent.com
flutter build web --release --dart-define=GOOGLE_WEB_CLIENT_ID=1234567890-xxx.apps.googleusercontent.com
```

### B. Android Configuration

1. In Google Cloud Console, go to **Credentials** > **Create Credentials** > **OAuth client ID**.
2. Select **Application type**: **Android**.
3. **Package name**: `com.nextaction.nextaction` (matches `apps/mobile_web/android/app/build.gradle`).
4. **SHA-1 certificate fingerprint**:
   - For **Debug builds** (local development):
     Run in terminal:
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     ```
     Copy the SHA-1 fingerprint.
   - For **Release builds**:
     Run against your release keystore:
     ```bash
     keytool -list -v -keystore <path-to-keystore> -alias <key-alias>
     ```
     Copy the SHA-1 and SHA-256 fingerprints.
5. Click **Create**.

> [!NOTE]
> Android Google Sign-In requires the **Web Application Client ID** as the `serverClientId` in order to obtain an OpenID Connect ID token for backend server verification:
```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=1234567890-xxx.apps.googleusercontent.com
```

---

## 5. Backend Environment Variables

Configure the following environment variables in your local `.env` and Render/production environment:

| Variable | Required | Description | Example |
| :--- | :--- | :--- | :--- |
| `GOOGLE_CLIENT_ID` | Optional / Recommended | Primary Google OAuth client ID verified by backend | `1234567890-xxx.apps.googleusercontent.com` |
| `GOOGLE_CLIENT_IDS` | Optional | Comma-separated list of multiple accepted Google client IDs (e.g. Web + Android clients) | `web-id.apps.googleusercontent.com,android-id.apps.googleusercontent.com` |

If no client ID is configured in development, the backend verifies token signature, issuer, and expiration, and logs a development warning. In production, `GOOGLE_CLIENT_ID` or `GOOGLE_CLIENT_IDS` MUST be configured to enforce audience restriction.

### Secrets Protection:
- **NEVER** commit client secrets, keystore credentials, or service account JSON files to the Git repository.
- Google OAuth Client IDs are public identifiers and safe to include in build parameters, but client secrets (if ever used) must remain strictly server-side.

---

## 6. Testing & Verification

### Automated Backend Tests
Run the Google authentication backend test suite:
```bash
backend\.venv\Scripts\python.exe -m pytest backend\tests\test_google_auth.py -v
```
Covers:
- Valid token verification and claim extraction
- Invalid signature, expired token, and wrong audience rejection
- Unverified email rejection (`email_verified == false`)
- New Google user provisioning
- Account linking to existing password account
- Duplicate-account prevention across repeat logins
- Standard NextAction JWT token issuance (`access_token`, `refresh_token`)

### Automated Flutter Tests
Run the Flutter unit and widget test suites:
```bash
flutter test test\unit\auth_service_test.dart test\unit\auth_provider_test.dart test\widget_test.dart
```
Covers:
- `AuthService.signInWithGoogle()` ID token exchange
- User cancellation handling (returns `null`, no false error banners)
- Missing ID token validation
- Backend 401 error propagation
- `AuthProvider` state management (`authenticated`, `unauthenticated`, loading toggling)
- `LoginScreen` [ Continue with Google ] button rendering, branding, and interaction
- Error banner presentation on genuine backend errors

### Static Analysis
Verify code standards and lints:
```bash
flutter analyze
```
Must report `No issues found!`.
