# Phase 12 — Notifications, Alerts & Smart Attention System Report

**Date**: 2026-09-29  
**Project**: NextAction (`C:\bhanu\NEXT ACTION`)  
**Status**: `PASS`  
**Baseline**: Phase 1–11 Verified  

---

## 1. Objective
Phase 12 builds a comprehensive, in-app notification and attention management system on top of NextAction's existing scheduling, assignment, client, workflow, and task tracking infrastructure. The objective is to actively surface high-priority operational items to users:
- *"What needs attention right now?"* (via the **Smart Attention Panel** on Dashboard)
- *"What became overdue?"* (Overdue task alerts and next action overdue alerts)
- *"Which reminders and follow-ups are due?"* (Reminder due alerts, follow-up due alerts)
- *"Which assigned tasks require action?"* (Task assignment and reassignment notifications)
- *"Are there attempt limits reached?"* (Max attempt limit alerts requiring authorized overrides)

All notifications are strictly scoped to the authenticated user with rigorous duplicate prevention (`dedup_key`), foreign key safety (`ondelete="SET NULL"` on task deletion), and full PostgreSQL persistence.

---

## 2. Existing Event/Notification Architecture
Prior to Phase 12:
- Tasks, Clients, Workflows, Users/Assignments, Reminders, Follow-ups, and Task History were fully operational.
- There was no persistent `Notification` table or user notification center.
- Events occurred in backend services (e.g. `assign_task`, `complete_task`) without generating persistent notification entities.
- Phase 12 introduced a persistent, user-isolated notification architecture without duplicating existing entities.

---

## 3. Notification Model
Implemented in [`backend/app/models/notification.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/models/notification.py):
- **Table**: `notifications`
- **Fields**:
  - `id`: `UUID` (Primary Key, auto-generated)
  - `user_id`: `UUID` (`ForeignKey("users.id", ondelete="CASCADE")`, indexed)
  - `task_id`: `Optional[UUID]` (`ForeignKey("tasks.id", ondelete="SET NULL")`, indexed, nullable)
  - `type`: `String(50)` (e.g., `task_assigned`, `task_reassigned`, `reminder_due`, `follow_up_due`, `next_action_due`, `task_overdue`, `attempt_limit_reached`, `task_completed`, `task_reopened`)
  - `title`: `String(255)`
  - `message`: `Text`
  - `dedup_key`: `Optional[String(255)]` (indexed for high-performance deduplication checks)
  - `is_read`: `Boolean` (default `False`, indexed)
  - `read_at`: `Optional[DateTime(timezone=True)]`
  - `created_at`: `DateTime(timezone=True)` (server default `func.now()`, indexed)
  - `updated_at`: `DateTime(timezone=True)` (server default `func.now()`)

### Foreign Key & Deletion Invariant:
When a task is deleted, `task_id` is set to `NULL` via `ondelete="SET NULL"`. The user's historical notification records are preserved without violating foreign key constraints or causing crash regressions.

---

## 4. Alembic Migration
- **Migration File**: [`backend/alembic/versions/c5e4a8b79f12_create_notifications_table.py`](file:///c:/bhanu/NEXT%20ACTION/backend/alembic/versions/c5e4a8b79f12_create_notifications_table.py)
- **Revision ID**: `c5e4a8b79f12`
- **Verification**:
  - Executed `alembic upgrade head` cleanly against PostgreSQL.
  - Indexes created on `user_id`, `task_id`, `is_read`, `dedup_key`, `type`, and `created_at`.

---

## 5. Notification API
Implemented in [`backend/app/api/routes/notifications.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/api/routes/notifications.py) with mandatory JWT authentication (`CurrentUserDep`):

| Endpoint | Method | Description | Security / Ownership Isolation |
|---|---|---|---|
| `/api/v1/notifications` | `GET` | List notifications (filters: `unread_only`, pagination `page`, `page_size`) | Scoped strictly to `current_user.id` |
| `/api/v1/notifications/unread-count` | `GET` | Get total count of unread notifications | Scoped strictly to `current_user.id` |
| `/api/v1/notifications/{id}/read` | `POST` | Mark specific notification as read | Returns 404 if notification belongs to another user (IDOR prevention) |
| `/api/v1/notifications/read-all` | `POST` | Mark all notifications read in bulk | Only updates records where `user_id == current_user.id` |
| `/api/v1/notifications/{id}` | `GET` | Get single notification detail | Returns 404 if notification belongs to another user |
| `/api/v1/notifications/evaluate` | `POST` | Background / lifecycle trigger to evaluate due alerts | Generates alerts with deduplication |

---

## 6. Notification Service
Implemented in [`backend/app/services/notification_service.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/services/notification_service.py):
- `create_notification()`: Creates and persists notification record.
- `get_notification()`: Retrieves notification ensuring `user_id == current_user.id` (raises `EntityNotFoundError` on mismatch).
- `get_user_notifications()`: Returns paginated notifications and accurate unread count.
- `get_unread_count()`: Returns active unread count for user badge.
- `mark_as_read()`: Sets `is_read = True` and `read_at = utcnow()`.
- `mark_all_as_read()`: Executes bulk update for user.
- `evaluate_due_notifications()`: Scans due reminders, due follow-ups, due next actions, overdue tasks, and attempt limits, generating notifications.

---

## 7. Event Generation & Triggers
Integrated across domain operations in [`backend/app/services/task_service.py`](file:///c:/bhanu/NEXT%20ACTION/backend/app/services/task_service.py):
1. **Task Assignment on Creation**: `create_task()` -> generates `task_assigned` notification for `assigned_user_id`.
2. **Task Reassignment**: `assign_task()` -> generates `task_reassigned` notification for the new assignee.
3. **Task Completion**: `complete_task()` -> generates `task_completed` notification for assignee if completed by another user.
4. **Task Reopen**: `reopen_task()` -> generates `task_reopened` notification for assignee if reopened by another user.
5. **Attempt Limit Exceeded**: `record_attempt()` -> generates `attempt_limit_reached` alert when `attempt_count >= max_attempts`.
6. **Due Reminders**: `evaluate_due_notifications()` -> generates `reminder_due` notification.
7. **Due Follow-ups**: `evaluate_due_notifications()` -> generates `follow_up_due` notification.
8. **Due Next Actions**: `evaluate_due_notifications()` -> generates `next_action_due` notification.
9. **Overdue Tasks**: `evaluate_due_notifications()` -> generates `task_overdue` notification.

---

## 8. Duplicate Prevention Strategy
To prevent duplicate alerts when users refresh screens or schedulers run repeatedly:
- **Deduplication Key Format**:
  - Reminders: `f"reminder:{reminder.id}:{reminder.remind_at.isoformat()}"`
  - Follow-ups: `f"follow_up:{follow_up.id}:{follow_up.scheduled_at.isoformat()}"`
  - Next Actions: `f"next_action:{task.id}:{task.next_action_date.isoformat()}"`
  - Overdue Tasks: `f"task_overdue:{task.id}:{task.due_date.isoformat()}"`
  - Attempt Limits: `f"attempt_limit:{task.id}:{task.attempt_count}"`
- **Mechanism**: Before creating an alert, the service queries `Notification` table for `(user_id, dedup_key)`. If found, creation is skipped.

---

## 9. Due / Overdue Processing
- Evaluated via `NotificationService.evaluate_due_notifications(db, as_of)`.
- Accessible via authenticated endpoint `POST /api/v1/notifications/evaluate`.
- In Flutter, invoked when the user opens `NotificationsScreen` or triggers manual refresh.
- Schedulable via background workers without duplicate alert storms.

---

## 10. Notification Center UI (`NotificationsScreen`)
Implemented in [`apps/mobile_web/lib/screens/notifications/notifications_screen.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/screens/notifications/notifications_screen.dart):
- **Filter Tabs**: `All` vs `Unread Only`.
- **Visual Distinction**:
  - Unread: Accent blue border, blue pill badge with pulse dot, bold typography, light blue background tint.
  - Read: Subtle card background, muted text, "Read" tag.
- **Actions**:
  - "Mark All Read" button in AppBar with real-time badge clearing.
  - "Mark as Read" individual swipe/tap button.
  - "Evaluate Due Alerts" quick trigger.
  - 1-tap navigation to associated `TaskDetailScreen`.
- **States Handled**: Loading spinner, Empty state illustration, Error state with retry button.

---

## 11. Notification Badge
- **AppBar Bell Icon**: `lib/screens/home/home_screen.dart` renders a bell icon with dynamic badge count.
- **Smart Badge Visibility**: When unread count is `0`, no distracting "0" badge is displayed. When `> 0`, red indicator displays count (or `99+`).
- **Drawer Integration**: Navigation drawer displays "Notification Center" with live unread badge chip.

---

## 12. Dashboard Integration & Smart Attention Panel
- **HomeScreen Integration**:
  - Added **"Attention & Recent Alerts"** card section to [`apps/mobile_web/lib/screens/home/home_screen.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/lib/screens/home/home_screen.dart).
  - Displays top 3 recent notifications with category icons, relative timestamps, and unread highlight dots.
  - "View all" action button navigates directly to `NotificationsScreen`.
  - Network-resilient: Notifications fallback cleanly if API is temporarily unreachable, preserving dashboard uptime.

---

## 13. Security Verification
1. **Unauthenticated Access**: All notification routes reject requests lacking a valid JWT Bearer token with HTTP 401.
2. **Actor Scoping**: Notifications are strictly filtered by `current_user.id`.
3. **IDOR Defense**: Attempting to fetch or mark read User B's notification using User A's token returns HTTP 404 (preventing user enumeration).
4. **Bulk Isolation**: Bulk `mark-all` only mutates records belonging to `current_user.id`.

---

## 14. Test Summary

### Backend Tests
- Command: `.\backend\.venv\Scripts\python.exe -m pytest backend/tests -v`
- Total Passed: **79 / 79** (`100%`)
- Phase 12 Specific Tests in `backend/tests/test_notifications.py`:
  - `test_unauthenticated_notification_endpoints_rejected` (PASS)
  - `test_user_can_list_own_notifications` (PASS)
  - `test_user_cannot_access_or_read_another_users_notification` (PASS)
  - `test_user_cannot_mark_another_users_notification_as_read` (PASS)
  - `test_bulk_mark_all_read_isolation` (PASS)
  - `test_unread_count_is_user_specific` (PASS)
  - `test_task_creation_assignment_generates_notification` (PASS)
  - `test_task_reassignment_generates_notification` (PASS)
  - `test_task_completion_and_reopen_notifications` (PASS)
  - `test_attempt_limit_reached_notification` (PASS)
  - `test_duplicate_prevention_with_dedup_key` (PASS)
  - `test_evaluation_generates_notifications_and_prevents_duplicates` (PASS)
  - `test_task_deletion_preserves_notifications` (PASS)

### Flutter Tests & Analysis
- Analysis: `flutter analyze --suppress-analytics` -> **0 issues found**
- Full Test Suite: `flutter test --suppress-analytics` -> **215 / 215 passed** (`100%`)
- Phase 12 Unit & Integration Tests:
  - `test/unit/notification_model_test.dart` (5 tests passed)
  - `test/unit/notification_service_test.dart` (6 tests passed)
  - `test/integration/phase12_notifications_screen_test.dart` (4 tests passed)
  - `test/integration/phase12_attention_dashboard_test.dart` (2 tests passed)

---

## 15. Live End-to-End Verification (21 Steps)
- File: [`apps/mobile_web/test/integration/phase12_live_e2e_test.dart`](file:///c:/bhanu/NEXT%20ACTION/apps/mobile_web/test/integration/phase12_live_e2e_test.dart)
- Environment: Live FastAPI (`http://127.0.0.1:8000`) connected to PostgreSQL (`localhost:5432`).
- Results: **21 / 21 Passed**:
  1. `Login User A`: Registered and authenticated User A against PostgreSQL. (PASS)
  2. `Create/identify User B`: Registered and authenticated User B against PostgreSQL. (PASS)
  3. `Assign a task to User B`: User A created and assigned task to User B. (PASS)
  4. `Verify User B receives in-app notification`: User B received `task_assigned` notification. (PASS)
  5. `Verify User A does not see User B's notification`: User A cannot see or fetch User B's alert (IDOR blocked). (PASS)
  6. `Open notification center`: User B retrieved notifications and verified pagination summary. (PASS)
  7. `Verify unread badge`: Unread count matched pending alerts (`>= 1`). (PASS)
  8. `Open notification`: User B read specific notification payload. (PASS)
  9. `Verify related task opens`: Associated task ID loaded successfully via TaskService. (PASS)
  10. `Verify notification becomes read`: Marked as read, unread count dropped to 0. (PASS)
  11. `Create reminder`: User A created past-due reminder for background evaluation. (PASS)
  12. `Trigger/check due notification`: Evaluated due items and generated `reminder_due` notification. (PASS)
  13. `Create follow-up`: User A created past-due follow-up. (PASS)
  14. `Trigger/check due notification`: Evaluated due items and generated `follow_up_due` notification. (PASS)
  15. `Create next action & overdue task`: User A created task with past due and next action dates. (PASS)
  16. `Trigger/check due notification`: Generated `next_action_due` and `task_overdue` alerts. (PASS)
  17. `Verify duplicate prevention`: Second evaluation run produced 0 new notifications. (PASS)
  18. `Mark all notifications read`: User A marked all alerts read in bulk. (PASS)
  19. `Verify unread count becomes zero`: Unread count verified as 0 and unread filter list empty. (PASS)
  20. `Refresh application`: Queried all notifications with pagination and confirmed read state. (PASS)
  21. `Verify notification state persists from PostgreSQL`: Fresh un-cached ApiClient confirmed persistence. (PASS)

---

## 16. Performance & Quality Guarantees
- **No Aggressive Polling**: Notifications are loaded on screen navigation, manual refresh, and after action mutations.
- **Index Coverage**: PostgreSQL indexes on `user_id`, `is_read`, `dedup_key`, and `created_at` ensure fast sub-millisecond lookups.
- **No Third-Party Push Provider**: Followed strict requirements to avoid external push vendors (FCM, OneSignal, APNs) in Phase 12.

---

## 17. Regression Check
- Baseline Phase 11: Backend 66, Flutter 180.
- Phase 12 Final: Backend **79 passed**, Flutter **215 passed**, Flutter analyze **0 issues**.
- Zero regressions across Auth, Tasks, Clients, Workflows, Users/Assignment, Reminders, Follow-ups, Next Actions, and Dashboard.

---

## 18. Exact Verification Commands
```powershell
# 1. Backend tests
.\backend\.venv\Scripts\python.exe -m pytest backend/tests -v

# 2. Flutter analyzer
cd apps/mobile_web
flutter analyze --suppress-analytics

# 3. Flutter test suite
flutter test --suppress-analytics

# 4. Live E2E test against running FastAPI & PostgreSQL
flutter test test/integration/phase12_live_e2e_test.dart --suppress-analytics
```

---

## 19. Final Status: `PASS`
Phase 12 is fully completed and verified against all criteria.
