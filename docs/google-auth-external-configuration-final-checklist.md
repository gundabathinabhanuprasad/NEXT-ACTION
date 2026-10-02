# NextAction — Google Auth External Configuration Final Execution Checklist

**Audit Date**: 2026-10-02  
**Target Environment**: Production Google Cloud Console & Render  
**Frontend URL**: `https://nextaction.pages.dev`  
**Backend API**: `https://nextaction-backend-jkrp.onrender.com`  
**Android Package Name**: `com.nextaction.nextaction`  
**Current Shorebird Baseline**: Release 1.0.0+1 (Release ID: 869502)

---

## 1. Executive Execution Readiness Status

| Category | Status | Details |
| :--- | :--- | :--- |
| **Source Code Readiness** | **ALREADY VERIFIED (PASS)** | 100% complete. No source code changes required. |
| **Local Automated Tests** | **ALREADY VERIFIED (PASS)** | 272 backend tests PASS, 145 Flutter unit tests PASS, 11 Flutter widget tests PASS, `flutter analyze` 0 issues. |
| **Google Cloud Project** | **USER MUST CONFIGURE** | Administrator must create/select project and configure OAuth Consent Screen. |
| **Web OAuth Client** | **USER MUST CONFIGURE** | Administrator must create Web OAuth Client in Google Cloud Console. |
| **Android OAuth Client** | **USER MUST CONFIGURE** | Administrator must create Android OAuth Client in Google Cloud Console. |
| **Render Environment** | **USER MUST CONFIGURE** | Administrator must add `GOOGLE_CLIENT_ID` in Render Dashboard. |
| **Android Release Type** | **FULL RELEASE REQUIRED** | `google_sign_in` adds native Android dependencies; Shorebird patch cannot inject native code. |

---

## 2. Status Classification Matrix

### A. ALREADY VERIFIED (Code & Architecture)
- [x] Backend endpoint `POST /api/v1/auth/google` operational and secured.
- [x] Server-side ID token verification using Google's public JWKS certificates (`google-auth`).
- [x] Audience validation logic accepting single or multiple client IDs.
- [x] Issuer validation (`accounts.google.com` or `https://accounts.google.com`).
- [x] Expiration validation.
- [x] Email verified claim enforcement (`email_verified == True`).
- [x] No client-reported identity trusted.
- [x] Safe account-linking algorithm (links existing email/password accounts; prevents duplicates).
- [x] NextAction JWT session generation (`access_token`, `refresh_token`); Google tokens never stored as application sessions.
- [x] Token storage integration in Flutter (`TokenStorage`, `RefreshTokenStorage`).
- [x] Single-source-of-truth `AuthProvider.signInWithGoogle()`.
- [x] `LoginScreen` [ Continue with Google ] button with 4-color Google logo painter, loading state, and duplicate prevention.
- [x] User cancellation cleanly handled without misleading error banners.
- [x] Production backend URL configured to `https://nextaction-backend-jkrp.onrender.com`.
- [x] Android package identifier configured to `com.nextaction.nextaction`.
- [x] Local debug keystore SHA-1 fingerprint extracted.
- [x] Google Cloud CLI (`gcloud`) verified as **NOT installed** (no changes made).
- [x] No client secrets or credentials committed to Git or present in Flutter code.

### B. USER MUST CONFIGURE (External Platforms)
- [ ] **Google Cloud Project**: Create or select project in Google Cloud Console.
- [ ] **OAuth Consent Screen**: Configure External consent screen with required scopes (`openid`, `email`, `profile`).
- [ ] **Web OAuth Client ID**: Create Web application credential with authorized origin `https://nextaction.pages.dev`.
- [ ] **Android OAuth Client ID**: Create Android credential with package `com.nextaction.nextaction` and SHA-1.
- [ ] **Production Release Keystore SHA-1**: Extract SHA-1 from release keystore or Google Play Console.
- [ ] **Render Environment Variable**: Add `GOOGLE_CLIENT_ID` with the generated Web Client ID in Render Dashboard.
- [ ] **Frontend Build Injection**: Build Flutter Web and Android passing the client IDs via compile-time `--dart-define`.

### C. NOT REQUIRED (Eliminated Redundancies)
- [x] **Google Client Secret on Backend**: NOT REQUIRED. ID token verification relies on Google public certificates.
- [x] **Google Client Secret in Flutter**: NOT REQUIRED. Client secrets must never be placed in client apps.
- [x] **Authorized Redirect URIs for Web**: NOT REQUIRED for the Google Identity Services popup/postMessage flow used by `google_sign_in_web`.
- [x] **Shorebird Patch for Initial Rollout**: NOT APPLICABLE / CANNOT BE USED. Native plugins cannot be patched over OTA.
- [x] **Database Schema Migration**: NOT REQUIRED. MongoDB user schema accommodates optional `google_id` with sparse index.

---

## 3. Exact Google Cloud Console Configuration

### 3.1. OAuth Consent Screen
1. Navigate to: [Google Cloud Console > APIs & Services > OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent)
2. **User Type**: `External`
3. Click **Create**
4. **App Information**:
   - **App name**: `NextAction`
   - **User support email**: Your administrator email (e.g. `bhanuprasad.gundabathina@gmail.com`)
   - **Developer contact information**: Your administrator email
5. **App Domain**:
   - **Application home page**: `https://nextaction.pages.dev`
   - **Authorized domains**: `nextaction.pages.dev`
6. **Scopes**:
   - Click **Add or Remove Scopes**
   - Select:
     - `.../auth/userinfo.email` (`email`)
     - `.../auth/userinfo.profile` (`profile`)
     - `openid`
7. Click **Save and Continue** until complete.
8. (Optional / Development): Under **Test users**, add your own Google email address if keeping the app in "Testing" mode.

---

### 3.2. Web OAuth Client ID
1. Navigate to: [Google Cloud Console > Credentials > Create Credentials > OAuth client ID](https://console.cloud.google.com/apis/credentials)
2. **Application type**: `Web application`
3. **Name**: `NextAction Web Client`
4. **Authorized JavaScript origins**:
   ```
   https://nextaction.pages.dev
   http://localhost:8000
   http://127.0.0.1:8000
   http://localhost
   http://127.0.0.1
   ```
5. **Authorized redirect URIs**:
   - Leave empty, or optionally add `https://nextaction.pages.dev` (not used by the client-side GIS popup flow).
6. Click **Create**.
7. **Record this value**:
   - **Web Client ID**: `<web-client-id>.apps.googleusercontent.com`
   - *(Ignore the Client Secret; it is not needed by NextAction)*.

---

### 3.3. Android OAuth Client ID
1. Navigate to: [Google Cloud Console > Credentials > Create Credentials > OAuth client ID](https://console.cloud.google.com/apis/credentials)
2. **Application type**: `Android`
3. **Name**: `NextAction Android App`
4. **Package name**: `com.nextaction.nextaction`
5. **SHA-1 certificate fingerprint**:
   - **For Local Debug Builds**:
     ```
     CE:C1:FA:5D:BD:69:06:B1:CD:86:D6:6D:37:CC:6A:0D:69:CA:31:3D
     ```
   - **For Production Release Builds**:
     - *If self-signed with a release keystore*:
       Run `keytool -list -v -keystore <path-to-release-keystore>` and enter the SHA-1 fingerprint.
     - *If distributed via Google Play*:
       Copy the **App signing key certificate SHA-1** from **Google Play Console** > **Setup** > **App integrity** > **App Signing**.
6. Click **Create**.

---

## 4. Exact Render Dashboard Configuration

1. Log in to [Render Dashboard](https://dashboard.render.com/).
2. Select your backend service: **`nextaction-backend`** (active URL: `https://nextaction-backend-jkrp.onrender.com`).
3. Click **Environment** in the left sidebar.
4. Add the following environment variable:
   - **Key**: `GOOGLE_CLIENT_ID`
   - **Value**: `<web-client-id>.apps.googleusercontent.com` *(from Step 3.2)*
5. Click **Save Changes**.
   - Render will automatically perform a zero-downtime rolling restart with the new variable.

> [!NOTE]
> Why the Web Client ID for Render?
> When the Android app signs in, it requests an ID token on behalf of the backend using the Web Client ID (`serverClientId`). Therefore, ID tokens generated by both Web and Android share the **Web Client ID** as their audience (`aud`). Setting `GOOGLE_CLIENT_ID=<web-client-id>.apps.googleusercontent.com` in Render satisfies token verification for both platforms.

---

## 5. Production Build & Deployment Commands

Once Google Cloud Console and Render are configured:

### A. Production Web Build (Cloudflare Pages)
Pass the Web Client ID at build time:
```bash
flutter build web --release --dart-define=API_BASE_URL=https://nextaction-backend-jkrp.onrender.com --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

### B. Production Android Build (Full APK / App Bundle)
Pass the Web Client ID as the `GOOGLE_SERVER_CLIENT_ID`:
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://nextaction-backend-jkrp.onrender.com --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```
Or for Google Play Bundle:
```bash
flutter build appbundle --release --dart-define=API_BASE_URL=https://nextaction-backend-jkrp.onrender.com --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

---

## 6. Shorebird vs Full Release Architectural Assessment

### Question: Can a Shorebird patch be used for this release?
**NO. A FULL BINARY RELEASE IS REQUIRED.**

### Technical Explanation:
1. **Native Dependency Introduction**:
   The `google_sign_in: ^6.2.2` package includes native Android dependencies (`google_sign_in_android`, Android Google Play Services Auth SDK libraries, and Java/Kotlin plugin registration code).
2. **Shorebird OTA Capabilities**:
   Shorebird patches can **only** replace the compiled Dart code artifact (`libapp.so`). Shorebird **cannot**:
   - Add new Android Gradle dependencies (`com.google.android.gms:play-services-auth`).
   - Add native Java/Kotlin classes to the Android APK DEX files.
   - Modify the `GeneratedPluginRegistrant.java` or Android binary manifest.
3. **Failure Mode if Patched**:
   If a Shorebird patch containing the new Dart Google Sign-In code were pushed to devices running baseline `1.0.0+1`, tapping "Continue with Google" would throw an unhandled `MissingPluginException: No implementation found for method init on channel plugins.flutter.io/google_sign_in`.
4. **Resolution**:
   A **full new Android release** (e.g. `1.1.0+2` or `1.0.1+2`) must be built and distributed to users. Subsequent Dart-only changes to the Google authentication flow can then use Shorebird patches normally.
