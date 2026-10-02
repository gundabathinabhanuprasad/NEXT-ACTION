# Phase 19 Report: Advanced Notification Delivery, Reminder Engine & Automated Scheduling

## Executive Summary

Phase 19 delivers a production-grade automated Reminder, Notification Delivery, and Scheduling Engine for the NextAction platform. It seamlessly links Tasks, Reminders, Follow-ups, Next Actions, and Attempt Limits with Phase 18 User Notification Preferences, Day-Boundary IANA Timezones, and Persistent In-App Notifications.

The scheduling engine is designed to be:
- **Idempotent & Deterministic**: Guaranteed at the database level via a PostgreSQL partial unique index on `(user_id, dedup_key) WHERE dedup_key IS NOT NULL`. Repeated evaluation runs never generate duplicate notification alerts.
- **Bounded & User-Scoped**: Can be evaluated on-demand per authenticated user, preventing cross-user data leakage, or system-wide for automated background jobs.
- **Failure-Isolated**: Utilizes controlled SQLAlchemy transaction savepoints (`db.begin_nested()`) so that a single corrupted or malformed record cannot abort batch evaluation for valid records.
- **Audit-Preserving**: Disabling a notification preference strictly suppresses in-app notification generation without mutating, skipping, or suppressing immutable `TaskHistory` audit logs.
- **Timezone-Aware**: Uses Phase 18 IANA timezone preferences to accurately translate local calendar day boundaries ("Today", "Overdue", "Tomorrow") to UTC without altering timestamp storage.
- **Zero Heavy Infrastructure**: Implemented as an explicit, high-performance callable service (`SchedulingService`) that can be executed directly or scheduled via cron/workers without requiring Redis or Celery in this phase.

All 148 backend pytest tests, 426 Flutter tests, flutter analyze (0 issues), and all 6 live E2E suites (Phase 12, 15, 16, 17, 18, and 19) pass with 100% success against PostgreSQL 16 and FastAPI.

---

## Architecture Overview

```
+-----------------------------------------------------------------------------------+
|                            NextAction Application Layer                           |
+-----------------------------------------------------------------------------------+
|  Flutter Web & Mobile (Material 3)                                                |
|  - NotificationsScreen: Category Filters (Due, Reminders, Follow-ups, Attempts),  |
|    Unread Badge, Mark All Read, Task Navigation                                   |
|  - SchedulerService: REST client for automated/manual alerts evaluation           |
|  - NotificationService: in-app notification queries & read-state management       |
+-----------------------------------------+-----------------------------------------+
                                          | JSON over HTTPS (Bearer JWT)
                                          v
+-----------------------------------------------------------------------------------+
|                           FastAPI REST Services Layer                             |
|  - POST /api/v1/scheduler/evaluate      (Phase 19 rich diagnostic evaluation)     |
|  - POST /api/v1/notifications/evaluate  (Phase 12 backward-compatible endpoint)  |
|  - GET  /api/v1/notifications           (Filtered notification listing)           |
+-----------------------------------------+-----------------------------------------+
                                          | Delegates to
                                          v
+-----------------------------------------------------------------------------------+
|                       Scheduling Engine (SchedulingService)                       |
|  - evaluate_reminders()       : Unsent reminders due as of timestamp              |
|  - evaluate_follow_ups()      : Incomplete follow-ups scheduled as of timestamp   |
|  - evaluate_next_actions()    : Tasks with next_action_date due as of timestamp   |
|  - evaluate_overdue_tasks()   : Incomplete tasks past due_date                    |
|  - evaluate_attempt_limits()  : Tasks reaching near-max or max attempt limit      |
|  - Failure isolation          : Savepoints per item via db.begin_nested()         |
|  - Timezone calendar bounds   : get_user_calendar_bounds() via zoneinfo           |
|  - Preference suppression     : should_notify_user() check                        |
+-----------------------------------------+-----------------------------------------+
                                          | SQLAlchemy ORM
                                          v
+-----------------------------------------------------------------------------------+
|                        PostgreSQL 16 Database Layer                               |
|  - Table: notifications                                                           |
|  - Unique Index: uq_notifications_user_dedup (user_id, dedup_key)                 |
|    WHERE dedup_key IS NOT NULL                                                    |
|  - Alembic Migration: a1b2c3d4e5f6_add_unique_dedup_index_to_notifications.py     |
+-----------------------------------------------------------------------------------+
```

---

## Scheduler Lifecycle & Notification Flow

The complete flow from event generation to UI notification:

```
Task / Reminder / Follow-up / Attempt Limit
                   ↓
      Scheduling Engine Evaluation
                   ↓
      Target User & Ownership Check
                   ↓
     Timezone Calendar-Boundary Check
                   ↓
    Deduplication Key Lookup (DB Index)
      ├── Exists → Skip Duplicate & Record Metric
      └── New → Continue
                   ↓
   Phase 18 User Notification Preference
      ├── Disabled → Suppress Notification (Audit Preserved)
      └── Enabled → Create Persistent In-App Notification
                   ↓
       Controlled Savepoint Commit
                   ↓
     Notification Center & Unread Badge
```

---

## Deduplication Strategy & Database Uniqueness

To guarantee zero race conditions and total idempotency, a partial unique index was added in Alembic migration `a1b2c3d4e5f6`:

```sql
CREATE UNIQUE INDEX uq_notifications_user_dedup
ON notifications (user_id, dedup_key)
WHERE dedup_key IS NOT NULL;
```

### Deterministic Deduplication Identity Conventions
Every automated notification is assigned a deterministic deduplication key incorporating its entity ID and event timestamp:

| Category | Dedup Key Pattern | Example |
| :--- | :--- | :--- |
| **Reminder Due** | `reminder:{reminder_id}:{remind_at.isoformat()}` | `reminder:7a9...:2026-09-29T15:30:00+00:00` |
| **Follow-up Due** | `follow_up:{follow_up_id}:{scheduled_at.isoformat()}` | `follow_up:4b2...:2026-09-29T15:30:00+00:00` |
| **Next Action Due** | `next_action:{task_id}:{next_action_date.isoformat()}` | `next_action:1c3...:2026-09-29T15:30:00+00:00` |
| **Overdue Task** | `task_overdue:{task_id}:{due_date.isoformat()}` | `task_overdue:8d4...:2026-09-27T12:00:00+00:00` |
| **Max Attempts** | `attempt_limit:{task_id}:{attempt_count}` | `attempt_limit:2e5...:3` |
| **Near Max Attempts** | `near_max_attempts:{task_id}:{attempt_count}` | `near_max_attempts:3f6...:2` |

Because manual in-app notifications have `dedup_key IS NULL`, the PostgreSQL `WHERE dedup_key IS NOT NULL` partial clause permits multiple manual notifications without collision, while strictly enforcing single-alert delivery for scheduled automated items.

---

## Domain Evaluation Breakdown

### 1. Reminder Automation
- **Target Items**: Unsent reminders (`Reminder.is_sent == False`) where `remind_at <= as_of`.
- **Target User**: `task.assigned_user_id` (eager-loaded via `joinedload(Reminder.task)` to avoid N+1 queries).
- **Preference Check**: `UserSettings.notify_reminder_due`.
- **State Preservation**: Upon evaluation, `Reminder.is_sent` is set to `True`. Reminders never alter task attempts or task statuses.

### 2. Follow-up Automation
- **Target Items**: Incomplete follow-ups (`FollowUp.completed_at == None`) where `scheduled_at <= as_of`.
- **Target User**: `task.assigned_user_id`.
- **Preference Check**: `UserSettings.notify_follow_up_due`.
- **State Preservation**: Follow-up evaluation never increments attempt counts, completes tasks, or alters task statuses.

### 3. Next Action Automation
- **Target Items**: Active tasks (`status NOT IN (completed, cancelled)`) with `next_action_date <= as_of`.
- **Target User**: `task.assigned_user_id`.
- **Preference Check**: `UserSettings.notify_next_action_due`.
- **Deduplication**: Keyed to `task.id` and `next_action_date.isoformat()`.

### 4. Overdue Task Automation
- **Target Items**: Active tasks (`status NOT IN (completed, cancelled)`) with `due_date <= as_of`.
- **Target User**: `task.assigned_user_id`.
- **Preference Check**: `UserSettings.notify_task_overdue`.
- **Deduplication**: Keyed to `task.id` and `due_date.isoformat()`.

### 5. Attempt Limit Alerts
- **Max Attempts**: Tasks where `attempt_count >= max_attempts`. Notification type: `attempt_limit_reached`.
- **Near Max Attempts**: Tasks where `attempt_count > 0` and `attempt_count == max_attempts - 1`. Notification type: `near_max_attempts`.
- **Preference Check**: `UserSettings.notify_attempt_limit_reached`.
- **State Preservation**: Attempt counts and task statuses are never modified by the scheduler.

---

## User Timezone Integration

Phase 18 established user IANA timezones stored in `user_settings.timezone`. Phase 19 uses these preferences for date boundary calculations without altering UTC timestamp storage:

- `get_user_timezone(db, user_id)`: Resolves `ZoneInfo(settings.timezone)`, defaulting safely to `ZoneInfo("UTC")`.
- `get_user_calendar_bounds(db, user_id, as_of)`:
  - Takes reference UTC point `as_of`.
  - Converts to local time: `local_dt = as_of.astimezone(user_tz)`.
  - Determines local midnight start (`00:00:00`) and next-day midnight end (`00:00:00 + 1 day`).
  - Converts local bounds back to UTC for database comparisons.
  - Distinguishes items that are strictly overdue before today, due today, or due in the future from the user's localized perspective.

---

## Preference Suppression & Audit Preservation Guarantee

Phase 19 strictly adheres to the core requirement:
**Notification opt-out must NEVER suppress immutable TaskHistory audit records.**

When a user disables a notification preference (e.g. `notify_follow_up_due = false`):
1. The scheduler marks the candidate item as evaluated.
2. The in-app notification is suppressed and `preferences_suppressed` metric is incremented.
3. The underlying domain records (Task, Reminder, FollowUp) remain fully intact.
4. Any domain events logged to `TaskHistory` remain completely preserved and unmutated.

---

## API Endpoints

### 1. `POST /api/v1/scheduler/evaluate`
Primary Phase 19 scheduling evaluation endpoint.

- **Authentication**: Required (`Bearer <JWT>`).
- **Request Body (Optional)**:
  ```json
  {
    "as_of": "2026-09-29T15:30:00Z",
    "user_scoped": true
  }
  ```
- **Response (`200 OK`)**:
  ```json
  {
    "evaluated": 25,
    "notifications_created": 4,
    "duplicates_skipped": 6,
    "preferences_suppressed": 2,
    "errors_count": 0,
    "duration_ms": 12.4,
    "evaluated_at": "2026-09-29T15:30:00Z",
    "user_id": "d729f6a8-c9de-45a1-a5ff-b84d97b0ca4f",
    "details": {
      "reminders": {
        "evaluated": 5,
        "notifications_created": 1,
        "duplicates_skipped": 2,
        "preferences_suppressed": 0,
        "errors": 0
      },
      "follow_ups": {
        "evaluated": 5,
        "notifications_created": 0,
        "duplicates_skipped": 1,
        "preferences_suppressed": 2,
        "errors": 0
      },
      "next_actions": {
        "evaluated": 5,
        "notifications_created": 1,
        "duplicates_skipped": 1,
        "preferences_suppressed": 0,
        "errors": 0
      },
      "overdue_tasks": {
        "evaluated": 5,
        "notifications_created": 1,
        "duplicates_skipped": 1,
        "preferences_suppressed": 0,
        "errors": 0
      },
      "attempt_limits": {
        "evaluated": 5,
        "notifications_created": 1,
        "duplicates_skipped": 1,
        "preferences_suppressed": 0,
        "errors": 0
      }
    }
  }
  ```

### 2. `POST /api/v1/notifications/evaluate`
Preserved for backward compatibility with Phase 12 and Phase 16 callers. Internally delegates to `SchedulingService.evaluate_all(db, as_of=now, user_id=None)` and returns `{"created_count": count, "evaluated_at": timestamp}`.

---

## Notification Center Enhancements (Flutter)

The `NotificationsScreen` was enhanced without breaking existing layouts:
1. **Category Filter Chips**: Added horizontal choice chips for:
   - All
   - Overdue (`task_overdue`)
   - Reminders (`reminder_due`)
   - Follow-ups (`follow_up_due`)
   - Next Actions (`next_action_due`)
   - Attempt Limits (`attempt_limit_reached`, `near_max_attempts`)
   - Assignments (`task_assigned`, `task_reassigned`)
2. **Scheduler Diagnostic Feedback**: The "Check for Due Alerts" action button invokes `SchedulerService.evaluateScheduler()`, refreshing the list, unread badge count, and presenting feedback with notifications created and duplicates skipped.
3. **Task Navigation**: Tapping any notification linked to a task seamlessly navigates to `TaskDetailScreen`.

---

## Performance Strategy

- **Eager Loading**: `joinedload(Reminder.task)` and `joinedload(FollowUp.task)` eliminate N+1 queries during reminder and follow-up iterations.
- **Bulk Dedup Preloading**: `_preload_existing_dedup_keys` batches lookup of existing `(user_id, dedup_key)` pairs in one single query prior to record iteration.
- **Database-Side Filtering**: Unsent/incomplete and date-boundary checks are performed in SQL (`WHERE Reminder.is_sent IS FALSE AND Reminder.remind_at <= as_of`).
- **No Celery/Redis Dependency**: The scheduler operates as a lightweight callable service with bounded query sets and savepoint transactions.

---

## Verification & Test Results

### 1. Backend Pytest
- Total Tests: **148**
- Passed: **148** (100%)
- Failed: **0**
- Baseline was 137; added 11 Phase 19 scheduler tests in `backend/tests/test_scheduler.py`.

### 2. Flutter Test Suite
- Total Tests: **426**
- Passed: **426** (100%)
- Failed: **0**
- Baseline was 399; added 5 unit/widget tests (`phase19_scheduler_models_and_service_test.dart`, `phase19_notifications_filter_widget_test.dart`) and 22 live E2E steps in `phase19_live_e2e_test.dart`.

### 3. Flutter Analyze
- Issues: **0 issues found** across the entire mobile_web project.

### 4. Live E2E Verification Suites (against PostgreSQL 16 & FastAPI)

| Suite | Status | Passed Steps |
| :--- | :--- | :--- |
| **Phase 12 Live E2E** (Notifications & Attention) | **PASSED** | 21/21 |
| **Phase 15 Live E2E** (Task History & Audit Log) | **PASSED** | 25/25 |
| **Phase 16 Live E2E** (Dashboard & Workload) | **PASSED** | 32/32 |
| **Phase 17 Live E2E** (Reports & Exports) | **PASSED** | 20/20 |
| **Phase 18 Live E2E** (Settings & Preferences) | **PASSED** | 16/16 |
| **Phase 19 Live E2E** (Scheduler & Reminder Engine) | **PASSED** | 22/22 |

---

## Files Changed & Created

### Backend Files
- `backend/alembic/versions/a1b2c3d4e5f6_add_unique_dedup_index_to_notifications.py` (New Alembic migration adding `uq_notifications_user_dedup`)
- `backend/app/schemas/scheduler.py` (New Pydantic schemas: `SchedulerEvaluationRequest`, `SchedulerEvaluationResponse`, `CategoryEvaluationDetail`)
- `backend/app/schemas/__init__.py` (Export scheduler schemas)
- `backend/app/services/scheduling_service.py` (New dedicated SchedulingService implementation)
- `backend/app/services/notification_service.py` (Refactored `evaluate_due_notifications` to delegate to `SchedulingService`; added `near_max_attempts` mapping)
- `backend/app/api/routes/scheduler.py` (New scheduler API endpoints)
- `backend/app/api/router.py` (Registered `scheduler_router` in `api_v1_router`)
- `backend/tests/test_scheduler.py` (11 comprehensive backend unit & integration tests)
- `backend/tests/test_clients_workflows.py` (Updated workflow search assertion to maintain stability on large databases)

### Frontend Files
- `apps/mobile_web/lib/models/scheduler/scheduler_models.dart` (New Dart models for scheduler metrics and response)
- `apps/mobile_web/lib/models/notification/notification_models.dart` (Updated `isAttemptLimit` to recognize `near_max_attempts`)
- `apps/mobile_web/lib/services/scheduler/scheduler_service.dart` (New Flutter SchedulerService)
- `apps/mobile_web/lib/screens/notifications/notifications_screen.dart` (Enhanced with category choice chips, scheduler service integration, and diagnostic feedback)
- `apps/mobile_web/test/unit/phase19_scheduler_models_and_service_test.dart` (New unit tests for scheduler models and service)
- `apps/mobile_web/test/unit/phase19_notifications_filter_widget_test.dart` (New widget test for category filtering and scheduler evaluation action)
- `apps/mobile_web/test/integration/phase19_live_e2e_test.dart` (New 22-step Live E2E suite against live PostgreSQL 16 & FastAPI)
- `docs/phase-19-report.md` (Comprehensive Phase 19 architectural and verification report)

---

## Known Limitations & Boundaries

1. **In-App Persistent Notifications Only**: In accordance with the Phase 19 objective, external communication gateways (email SMTP, SMS Twilio, Firebase Cloud Messaging) are intentionally not implemented in this phase. The architecture is cleanly prepared with dedup keys and notification types ready for future external dispatcher hooks.
2. **Callable Service without Daemon Workers**: To prevent operational overhead, no Redis or Celery broker was introduced. The scheduling engine is exposed via a callable service (`SchedulingService.evaluate_all`) and authenticated REST API (`POST /api/v1/scheduler/evaluate`), ready to be triggered by future cron jobs, serverless schedulers, or background workers.
3. **Stop Condition Observed**: Work strictly concludes with Phase 19. Phase 20 has not been started.
