# NextAction — Live Development, Testing & Deployment Workflow

**Version**: 1.0.0  
**Effective Date**: October 2, 2026  
**Status**: ACTIVE PRODUCTION WORKFLOW  
**Architecture**: ₹0/month Stack (Render Web Service + MongoDB Atlas M0 + Cloudflare Pages + GitHub Releases + Shorebird OTA)

---

## 1. Production Architecture Overview

```
                                +-----------------------------+
                                |      NextAction Users       |
                                +--------------+--------------+
                                               |
                     +-------------------------+-------------------------+
                     |                                                   |
                     v (HTTPS)                                           v (HTTPS)
       +-----------------------------+                     +-----------------------------+
       |   Cloudflare Pages Edge     |                     |    Native Android Device    |
       |  https://nextaction.pages.dev|                    |    (GitHub Release APK /    |
       |  (Flutter 3.22 CanvasKit)   |                     |     Shorebird OTA Engine)   |
       +--------------+--------------+                     +--------------+--------------+
                      |                                                   |
                      +-------------------------+-------------------------+
                                                |
                                                v (JSON API / Bearer Auth)
                               +---------------------------------+
                               |       Render Web Service        |
                               | https://nextaction-backend-     |
                               |       jkrp.onrender.com         |
                               | (FastAPI + Pydantic v2 + Docker)|
                               +----------------+----------------+
                                                |
                                                v (Mongo Wire Protocol + TLS)
                               +---------------------------------+
                               |        MongoDB Atlas M0         |
                               |     (Production Database)       |
                               +---------------------------------+
```

### Exact Current Production Endpoints

| Component | Target URL / Reference | Hosting Platform |
| :--- | :--- | :--- |
| **Frontend Web Client** | [https://nextaction.pages.dev](https://nextaction.pages.dev) | Cloudflare Pages |
| **Preview Deployment** | [https://0c1b6c4a.nextaction.pages.dev](https://0c1b6c4a.nextaction.pages.dev) | Cloudflare Pages |
| **Backend API Service** | [https://nextaction-backend-jkrp.onrender.com](https://nextaction-backend-jkrp.onrender.com) | Render (Free Tier) |
| **Database Cluster** | MongoDB Atlas M0 Cluster (`cluster0.fgkgrsj.mongodb.net`) | MongoDB Atlas |
| **Web Download Portal** | [https://nextaction.pages.dev/download.html](https://nextaction.pages.dev/download.html) | Cloudflare Pages |
| **Public Source Repo** | [https://github.com/gundabathinabhanuprasad/NEXT-ACTION](https://github.com/gundabathinabhanuprasad/NEXT-ACTION) | GitHub |
| **Public Android Release** | [https://github.com/gundabathinabhanuprasad/NEXT-ACTION/releases/tag/v1.0.0](https://github.com/gundabathinabhanuprasad/NEXT-ACTION/releases/tag/v1.0.0) | GitHub Releases |
| **Public APK Asset** | [https://github.com/gundabathinabhanuprasad/NEXT-ACTION/releases/download/v1.0.0/app-release.apk](https://github.com/gundabathinabhanuprasad/NEXT-ACTION/releases/download/v1.0.0/app-release.apk) | GitHub Releases CDN |
| **Shorebird App ID** | `a51d0f56-4569-4352-878f-d83fb814f78d` | Shorebird Cloud |
| **Shorebird Baseline** | Release `1.0.0+1` (ID: `869502`, platform: `android`, status: `active`) | Shorebird Cloud |

---

## 2. Core Development Flow

Every future change follows this non-negotiable sequence:

```text
[Developer Change]
        │
        ▼
[Local Automated Tests]
├── Backend: pytest backend/tests (260 tests)
├── Flutter: flutter test test/widget_test.dart test/unit (138 tests)
└── Static Analysis: flutter analyze (0 errors)
        │
        ▼
[Local Verification / Pre-deployment Review]
├── Inspect API URL alignment (must point to nextaction-backend-jkrp.onrender.com)
├── Check secret hygiene (0 passwords, keys, or .env files tracked in Git)
└── Verify Git diff and uncommitted files
        │
        ▼
[Deployment by Change Scope]
├── Backend Only ──────────► Push to GitHub master ──► Render Auto/Manual Deploy
├── Web Only ──────────────► flutter build web ──► Wrangler Pages Deploy
├── Android Native ────────► Full APK Build ──► GitHub Release vX.Y.Z ──► Portal Update
└── Android OTA Compatible ─► Shorebird Patch ──► Shorebird Cloud Dispatch
        │
        ▼
[Live Production Verification]
├── Probe Live Endpoints (GET /health, GET /ready)
├── Live In-Browser E2E on https://nextaction.pages.dev
└── Verify Android App / OTA Receipt where applicable
```

---

## 3. Web Deployment Workflow

### Prerequisites
- Flutter SDK on system PATH (`Flutter 3.22+`).
- Wrangler CLI authenticated (`npx wrangler`).

### Repeatable Commands
```powershell
# 1. Navigate to mobile_web app
cd "C:\bhanu\NEXT ACTION\apps\mobile_web"

# 2. Build release web bundle with production backend compile-time definition
flutter build web --release --dart-define=API_BASE_URL=https://nextaction-backend-jkrp.onrender.com

# 3. Guardrail check: verify NO .apk files were placed in build/web/
Get-ChildItem -Path build/web -Filter "*.apk" -Recurse

# 4. Deploy directly to Cloudflare Pages production branch
npx wrangler pages deploy build/web --project-name=nextaction --branch=production --commit-dirty=true
```

### Web Verification
- Open [https://nextaction.pages.dev](https://nextaction.pages.dev) and confirm HTTP 200.
- Verify `build/web/main.dart.js` targets `https://nextaction-backend-jkrp.onrender.com` (0 occurrences of legacy or localhost URLs).

---

## 4. Backend Deployment Workflow

### Architecture & Engine
- **Engine**: FastAPI application served via Uvicorn inside Docker container.
- **Persistence**: MongoDB Atlas M0 cluster via async Motor/PyMongo drivers.
- **Config**: `render.yaml` infrastructure-as-code pointing to GitHub repository `master` branch.

### Deployment Process
1. Commit and push validated backend changes to GitHub `master`:
   ```bash
   git add backend/
   git commit -m "feat/fix(backend): <description>"
   git push origin master
   ```
2. Render detects the commit on branch `master` and executes Docker build.
3. If wake-from-sleep or cold start occurs, wait for container readiness.
4. Verify deployment health:
   ```bash
   curl -I https://nextaction-backend-jkrp.onrender.com/health
   curl -I https://nextaction-backend-jkrp.onrender.com/ready
   ```
   - `/health` must return `HTTP 200` with `{"status":"healthy","database":"connected"}`.
   - `/ready` must return `HTTP 200` with `{"status":"ready","database":"connected","mongodb":"connected"}`.
   - `/docs` must return `HTTP 404` (Swagger disabled in production).

---

## 5. Android Release Workflow (Two Distinct Paths)

### Path A — Full Android Release (Native Changes)
Use when changes include:
- Native Android code (`android/`), C++/NDK, or platform channels.
- `AndroidManifest.xml` permissions or intent filters.
- Gradle versions, dependencies, or Kotlin plugin upgrades.
- Major application architecture shifts.

**Flow**:
1. Run local tests: `flutter test test/widget_test.dart test/unit` & `flutter analyze`.
2. Compile release APK:
   ```powershell
   cd "C:\bhanu\NEXT ACTION\apps\mobile_web"
   flutter build apk --release --dart-define=API_BASE_URL=https://nextaction-backend-jkrp.onrender.com
   ```
3. Record file size and SHA-256:
   ```powershell
   Get-FileHash -Algorithm SHA256 build\app\outputs\flutter-apk\app-release.apk
   ```
4. Create new GitHub Release tag matching `pubspec.yaml` (e.g., `v1.1.0`):
   ```bash
   gh release create v1.1.0 build/app/outputs/flutter-apk/app-release.apk --title "NextAction v1.1.0 — Production Android Release"
   ```
5. Update download link in `apps/mobile_web/web/download.html` and redeploy Cloudflare Pages.
6. Verify public unauthenticated download.

---

### Path B — Shorebird OTA Patch (Over-The-Air)
Use when changes are strictly Dart/Flutter code:
- Bug fixes in UI widgets, styling, layout, or accessibility.
- Business logic, task calculations, or validation updates.
- API client handling or state provider adjustments.

**Flow**:
1. Verify baseline release exists in Shorebird Cloud:
   ```bash
   shorebird releases list
   # Confirmed: 869502  1.0.0+1  android: active  3.22.2
   ```
2. Run test verification locally:
   ```bash
   flutter test test/widget_test.dart test/unit
   flutter analyze
   ```
3. Publish Shorebird OTA patch against baseline release `1.0.0+1`:
   ```powershell
   cd "C:\bhanu\NEXT ACTION\apps\mobile_web"
   shorebird patch android --release-version=1.0.0+1 --flutter-version=3.22.2 --dart-define=API_BASE_URL=https://nextaction-backend-jkrp.onrender.com
   ```
4. Verify patch status in Shorebird Cloud:
   ```bash
   shorebird patches list
   ```
5. App Delivery: Installed Android devices receive the patch on background launch without requiring APK re-installation.

---

## 6. Versioning Rules

| Change Category | Action Required | Versioning Rule |
| :--- | :--- | :--- |
| **Bug Fix (Dart/Flutter only)** | Shorebird OTA Patch (Path B) | Keep `release-version: 1.0.0+1` (increments patch internal sequence in Shorebird) |
| **Feature Release (Flutter only)** | Shorebird OTA or Full Release | If OTA-compatible, publish patch; if major feature bundle, increment MINOR in `pubspec.yaml` (`1.1.0+2`) |
| **Native Android Change** | Full Android Release (Path A) | Increment version in `pubspec.yaml` (`1.1.0+2`), build new APK, publish GitHub Release |
| **Web Only Change** | Cloudflare Pages Deploy | Increment Web build metadata if desired; no Android build or Shorebird release required |
| **Backend Only Change** | Render Deploy | Version tracked in backend Git commits; no client rebuild required unless API contracts change |

---

## 7. Reusable Live Testing Checklist

Before marking any future task or feature complete, verify each relevant tier:

### A. Web Tier ([https://nextaction.pages.dev](https://nextaction.pages.dev))
- [ ] Root page loads with HTTP 200 and CanvasKit initialization.
- [ ] Login screen renders with email/password fields and Sign In button.
- [ ] User registration form renders and accepts input.
- [ ] User login succeeds with valid credentials.
- [ ] Task creation functions (Title, Description, Priority, Due Date).
- [ ] Task list renders existing tasks.
- [ ] Task detail screen opens and displays attributes.
- [ ] Task status updates (Pending -> In Progress -> Completed).
- [ ] Reminders / Scheduling / Follow-ups render accurately where implemented.
- [ ] Error banners render on network timeout or invalid inputs.

### B. Backend Tier ([https://nextaction-backend-jkrp.onrender.com](https://nextaction-backend-jkrp.onrender.com))
- [ ] `GET /health` returns `HTTP 200 OK` with `database: connected`.
- [ ] `GET /ready` returns `HTTP 200 OK` with `mongodb: connected`.
- [ ] `GET /docs` returns `HTTP 404 Not Found` (docs disabled in production).
- [ ] `OPTIONS /health` returns `HTTP 200 OK` with `Access-Control-Allow-Origin: https://nextaction.pages.dev`.
- [ ] `POST /api/v1/auth/login` validates credentials and returns JWT bearer token.
- [ ] `POST /api/v1/tasks` accepts valid task payload and returns `HTTP 201 Created`.
- [ ] `GET /api/v1/tasks` returns user's tasks with authorization check.
- [ ] Unauthenticated requests to protected endpoints return `HTTP 401 Unauthorized`.

### C. Database Tier (MongoDB Atlas)
- [ ] Connected via motor async driver on startup.
- [ ] Writes persist across container restarts.
- [ ] User documents stored with salted password hashes (no plaintext passwords).
- [ ] Task documents indexable by user ID and status.
- [ ] Soft deletion / archive states persist accurately.

### D. Android APK Tier
- [ ] Public APK downloadable from GitHub Releases without authentication.
- [ ] APK installs cleanly on physical device or Android emulator (API 23+).
- [ ] App launches and displays splash screen -> authentication UI.
- [ ] Network requests target `https://nextaction-backend-jkrp.onrender.com`.

### E. Shorebird OTA Tier
- [ ] Baseline release active in Shorebird Cloud.
- [ ] Patch compiles without native differences.
- [ ] Patch published to Shorebird Cloud.
- [ ] Installed baseline app downloads patch in background on launch.
- [ ] Next app launch boots with patched Dart snapshot.

---

## 8. Bug -> Fix -> Deploy Workflow

```text
1. BUG REPORTED
   └── Record exact reproduction steps, affected environment (Web/Android/API), and error logs.

2. ISOLATION
   └── Identify root cause layer: Backend Route / Domain Service / Flutter UI / API Client.

3. REPRODUCING TEST
   └── Write a failing unit or integration test locally:
       - Backend: pytest backend/tests/test_<feature>.py
       - Frontend: flutter test test/unit/<feature>_test.dart

4. IMPLEMENT FIX
   └── Apply minimal, targeted fix. Preserve architecture and comments.

5. LOCAL TEST VERIFICATION
   └── Run test suites:
       - pytest backend/tests
       - flutter test test/widget_test.dart test/unit
       - flutter analyze

6. TARGETED DEPLOYMENT
   └── Deploy only to the affected platform (Render, Cloudflare, or Shorebird).

7. LIVE VERIFICATION
   └── Test the exact bug scenario on the live production URL.

8. REGRESSION AUDIT
   └── Execute the Reusable Live Testing Checklist.
```

---

## 9. Production Safety Rules

1. **Zero Secret Leakage**: NEVER commit `.env`, keystores, private keys, database passwords, or JWT secrets to Git.
2. **Compile-Time Definition**: Production Flutter Web builds MUST compile with:
   `--dart-define=API_BASE_URL=https://nextaction-backend-jkrp.onrender.com`
3. **Legacy URL Protection**: NEVER use `nextaction-backend.onrender.com`, `localhost`, `127.0.0.1`, or `10.0.2.2` in production artifacts.
4. **Cloudflare File Limit**: NEVER place `.apk` files inside `apps/mobile_web/build/web/`. Cloudflare Pages has a strict 25 MiB single-file limit.
5. **No Speculative Deployments**: Always run automated tests locally before initiating deployment to Render, Cloudflare, or Shorebird.
6. **No Phantom Release Claims**: Never claim a deployment or OTA update succeeded unless verified by live HTTP probes, Shorebird CLI commands, or actual device execution.

---

## 10. Baseline Reference State

- **Git Master SHA**: `e68142f6a734e62ceadb168c24b66753d118839d`
- **Flutter Version**: `3.22.2` (Framework revision `761747bfc5`, Dart `3.4.3`)
- **Python / Backend**: Python 3.11+ / FastAPI 0.115+ / Motor 3.6+ / Pydantic v2
- **Public APK SHA-256**: `97C23DD1556B3D151CD3C75BE75E29797587EFF27E080365910C4BED2704F266`
- **Shorebird Release ID**: `869502` (Version `1.0.0+1`, Platform: `android`)
