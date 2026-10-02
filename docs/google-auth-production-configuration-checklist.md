# NextAction — Google Auth Production Configuration Checklist

**Audit Date**: 2026-10-02  
**Target Architecture**: Flutter Web (`https://nextaction.pages.dev`), Android (`com.nextaction.nextaction`), FastAPI Backend (`https://nextaction-backend-jkrp.onrender.com`), MongoDB Atlas  
**Status**: Implementation Complete Locally / External Google Cloud Console Configuration Pending User Action

---

## A. Current Implementation Status

| Component | Local Implementation Status | Automated Test Verification |
| :--- | :--- | :--- |
| **FastAPI Backend Route** | Implemented (`POST /api/v1/auth/google`) | 12/12 dedicated tests PASS |
| **Server-Side Token Verifier** | Implemented (`backend/app/core/google_auth.py`) | Validates signature, exp, iss, aud, email_verified |
| **MongoDB User Schema** | Implemented (`google_id`, `auth_provider`, sparse index) | 16/16 repository tests PASS |
| **Safe Account Linking** | Implemented (links existing accounts with verified email) | Account linking & duplicate prevention PASS |
| **Session Architecture** | NextAction JWT (`access_token`, `refresh_token`) preserved | Unchanged token storage & refresh |
| **Flutter Web Integration** | Implemented (`google_sign_in: ^6.2.2`, `googleWebClientId`) | 145 unit tests + 11 widget tests PASS |
| **Flutter Android Integration**| Implemented (`googleServerClientId` audience support) | 145 unit tests + 11 widget tests PASS |
| **LoginScreen UI** | Implemented (`[ Continue with Google ]` button + logo painter) | Loading state, cancellation & error handling PASS |
| **Static Code Quality** | `flutter analyze` completed with 0 issues | Clean codebase |

---

## B. Google Cloud Project Requirements

To enable live Google Sign-In for real end-users, an active Google Cloud Project is required:

1. **Google Cloud Project**:
   - Access: [Google Cloud Console](https://console.cloud.google.com/)
   - Project Name: `NextAction` (or existing organization project)
2. **OAuth Consent Screen**:
   - User Type: **External** (allows any Google account to sign in)
   - App Name: `NextAction`
   - User Support Email: Administrator email address
   - Developer Contact Email: Administrator email address
   - App Logo: Optional (recommended for verified branding)
   - Application Home Page: `https://nextaction.pages.dev`
   - Application Privacy Policy: `https://nextaction.pages.dev` (or privacy policy link)
   - Application Terms of Service: `https://nextaction.pages.dev`
   - Scopes:
     - `openid`
     - `https://www.googleapis.com/auth/userinfo.email` (`email`)
     - `https://www.googleapis.com/auth/userinfo.profile` (`profile`)

---

## C. Web OAuth Client Configuration

Create an OAuth 2.0 Client ID for Flutter Web in Google Cloud Console:

- **Application Type**: `Web application`
- **Client Name**: `NextAction Web Client`
- **Authorized JavaScript Origins**:
  - Production:
    - `https://nextaction.pages.dev`
  - Local Development:
    - `http://localhost`
    - `http://localhost:8000`
    - `http://127.0.0.1`
    - `http://127.0.0.1:8000`
- **Authorized Redirect URIs**:
  - `https://nextaction.pages.dev`
  - `http://localhost:8000`
- **Generated Client ID**:
  - Format: `<web-client-id>.apps.googleusercontent.com`
  - *Public Identifier — Safe to pass as build parameter*.
- **Client Secret**:
  - *Not required or used by NextAction*. The backend performs token verification using Google's public JWKS certificates. Never commit or embed client secrets in the frontend.

---

## D. Android OAuth Client Configuration

Create an OAuth 2.0 Client ID for Android in Google Cloud Console:

- **Application Type**: `Android`
- **Client Name**: `NextAction Android App`
- **Package Name**: `com.nextaction.nextaction`
- **SHA-1 Certificate Fingerprint**:
  - **Local Debug Keystore** (verified from developer workstation):
    - SHA-1: `CE:C1:FA:5D:BD:69:06:B1:CD:86:D6:6D:37:CC:6A:0D:69:CA:31:3D`
    - SHA-256: `49:47:9B:3C:8E:44:F5:55:88:53:CB:54:30:A7:12:6D:EB:D4:2B:CC:3A:FA:54:99:2A:B7:64:20:37:1C:B9:96`
  - **Production Release Keystore** (*Requires User Action*):
    - Must be extracted from your release keystore (`key.properties` or Google Play App Signing console).
- **Web / Server Client ID for Android ID Token Retrieval**:
  - To obtain an OpenID Connect ID token for backend verification, Android Google Sign-In requires the **Web Client ID** (`<web-client-id>.apps.googleusercontent.com`) passed via `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.

---

## E. Backend Accepted Client IDs

The backend validates that the `aud` claim in the Google ID token matches an authorized client:

- **Single Audience**: Set `GOOGLE_CLIENT_ID` to the Web Client ID (`<web-client-id>.apps.googleusercontent.com`).
- **Multiple Audiences**: If distinct client IDs are generated for Web and Android, set `GOOGLE_CLIENT_IDS`:
  ```env
  GOOGLE_CLIENT_IDS=<web-client-id>.apps.googleusercontent.com,<android-client-id>.apps.googleusercontent.com
  ```
- **Audience Enforcement**:
  - The backend token verifier (`backend/app/core/google_auth.py`) rejects any token whose audience does not match `GOOGLE_CLIENT_ID` or `GOOGLE_CLIENT_IDS` with HTTP 401 (`INVALID_CREDENTIALS`).

---

## F. Render Environment Variables

Configure the following environment variables on the Render Dashboard (`https://dashboard.render.com` > `nextaction-backend` > **Environment**):

| Variable Name | Required | Value / Format | Purpose |
| :--- | :--- | :--- | :--- |
| `GOOGLE_CLIENT_ID` | Recommended | `<web-client-id>.apps.googleusercontent.com` | Primary authorized Google OAuth client audience |
| `GOOGLE_CLIENT_IDS` | Optional | `<id1>,<id2>` | Comma-separated list if multiple client IDs are used |

> [!NOTE]
> Do NOT set any Google client secret in Render. Google token verification relies strictly on Google's public key certificates.

---

## G. Cloudflare Origin Requirements

The canonical production frontend domain is hosted on Cloudflare Pages:

- **Production URL**: `https://nextaction.pages.dev`
- **CORS Whitelist**: Already configured in `backend/app/core/config.py` and `render.yaml`:
  `CORS_ORIGINS=["https://nextaction.pages.dev","https://7b06c20e.nextaction.pages.dev"]`
- **Google Cloud Console Origin**: Must include `https://nextaction.pages.dev` as an authorized JavaScript origin under the Web OAuth Client.

---

## H. Android Package & Signing Requirements

- **Package Name / Namespace**: `com.nextaction.nextaction` (verified in `apps/mobile_web/android/app/build.gradle`).
- **Debug Signing Certificate**:
  - Fingerprint: `CE:C1:FA:5D:BD:69:06:B1:CD:86:D6:6D:37:CC:6A:0D:69:CA:31:3D`
- **Release Signing Certificate**:
  - If using Google Play: Copy the **SHA-1 certificate fingerprint** from **Play Console** > **Setup** > **App Signing**.
  - If self-signing release APK: Run `keytool -list -v -keystore <path-to-keystore>` and extract SHA-1.

---

## I. Required Google Cloud Console Steps

Please perform the following steps in the Google Cloud Console:

1. **Step 1 — Open Console**:
   Navigate to [https://console.cloud.google.com/](https://console.cloud.google.com/) and select your project.
2. **Step 2 — Configure OAuth Consent Screen**:
   - Go to **APIs & Services** > **OAuth consent screen**.
   - Select **External**, click **Create**.
   - Set App Name: `NextAction`, Support Email: your email, Developer Email: your email.
   - Add Scopes: `openid`, `email`, `profile`.
   - Save and complete.
3. **Step 3 — Create Web OAuth Client**:
   - Go to **APIs & Services** > **Credentials** > **Create Credentials** > **OAuth client ID**.
   - Application type: **Web application**.
   - Name: `NextAction Web Client`.
   - Authorized JavaScript origins:
     - `https://nextaction.pages.dev`
     - `http://localhost:8000`
     - `http://127.0.0.1:8000`
   - Authorized redirect URIs:
     - `https://nextaction.pages.dev`
   - Click **Create**.
   - Copy the generated **Client ID** (ends with `.apps.googleusercontent.com`).
4. **Step 4 — Create Android OAuth Client**:
   - Go to **Credentials** > **Create Credentials** > **OAuth client ID**.
   - Application type: **Android**.
   - Name: `NextAction Android App`.
   - Package name: `com.nextaction.nextaction`.
   - SHA-1 certificate fingerprint:
     - Enter debug SHA-1: `CE:C1:FA:5D:BD:69:06:B1:CD:86:D6:6D:37:CC:6A:0D:69:CA:31:3D`.
     - (Add release keystore SHA-1 if release signing key is available).
   - Click **Create**.
5. **Step 5 — Add Environment Variables to Render**:
   - Go to Render Dashboard > `nextaction-backend` > **Environment**.
   - Add `GOOGLE_CLIENT_ID` with the Web Client ID obtained in Step 3.
   - Save changes (Render will trigger a redeploy when deployed).

---

## J. Security Checklist

- [x] **Zero Hardcoded Secrets**: No Google client secrets or private keys in frontend or backend codebase.
- [x] **No Git Committed Secrets**: All secrets excluded from source control.
- [x] **Server-Side Cryptographic Verification**: Backend validates token signature against Google JWKS certificates.
- [x] **Issuer Validation**: Strict check for `accounts.google.com` or `https://accounts.google.com`.
- [x] **Expiration Validation**: Expired tokens rejected with HTTP 401.
- [x] **Audience Validation**: Tokens issued for unauthorized client IDs rejected.
- [x] **No Untrusted Client Email**: Identity extracted solely from verified JWT payload claims; unverified emails rejected.
- [x] **Session Isolation**: Google tokens discarded after login; standard NextAction JWT access/refresh tokens issued.
- [x] **Clean Logging**: No raw credentials, ID tokens, or passwords logged.
- [x] **Inactive User Protection**: Inactive users rejected with HTTP 401.

---

## K. Verification Checklist After External Configuration

Once Google Cloud Console credentials and Render environment variables are configured, verify:

1. **Flutter Web Build Test**:
   ```bash
   flutter build web --release --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
   ```
2. **Flutter Android Build Test**:
   ```bash
   flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
   ```
3. **Backend Health Check**:
   ```bash
   curl -s https://nextaction-backend-jkrp.onrender.com/health
   ```
4. **Live Sign-In Flow**:
   - Click `[ Continue with Google ]` on web or Android.
   - Complete Google login prompt.
   - Verify redirect to authenticated dashboard and profile in `/api/v1/auth/me`.

---

## L. Items Requiring User Action

1. **Google Cloud Console Project**: User must log into Google Cloud Console and create or select project.
2. **OAuth Consent Screen**: User must configure app branding and authorized domain.
3. **Web OAuth Client ID**: User must create Web client and obtain Client ID string.
4. **Android OAuth Client ID**: User must register `com.nextaction.nextaction` with keystore SHA-1.
5. **Production Android Release SHA-1**: User must retrieve SHA-1 from production keystore / Play Console.
6. **Render Environment Variable**: User must add `GOOGLE_CLIENT_ID` to Render Dashboard.

---

## M. Items Already Verified Locally

1. **Backend Token Verifier**: Tested with mocked tokens, invalid signatures, expired tokens, and wrong audiences (12/12 PASS).
2. **Account Linking & Duplicate Prevention**: Tested with existing accounts and fresh Google accounts (PASS).
3. **MongoDB Document Models & Indexes**: Verified with sparse index on `users.google_id` (16/16 PASS).
4. **Flutter UI & Cancellation**: Verified `[ Continue with Google ]` button, clean cancellation without error banner, and error handling (11/11 PASS).
5. **Full Regression Suite**: 272 backend tests + 145 Flutter unit tests + 11 widget tests all PASS.
6. **Static Analysis**: `flutter analyze` reports 0 issues.
