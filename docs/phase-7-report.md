# Phase 7 — Task Management UX + Complete Task Workflow Report

## 1. Phase 7 Objective

The objective of Phase 7 is to turn the Phase 6 Flutter application into a complete, production-grade task management system that consumes the existing real FastAPI backend and PostgreSQL database. 

All task lifecycle actions—task creation with rich metadata, task list browsing with real-time multi-field search/filtering/sorting, attempt recording, maximum attempt conflict handling, authorized overrides with mandatory justification, postponement, next-action scheduling, completion, reopening, status transitions, priority updates, assignment, subject-line modifications, reminder scheduling/sending, follow-up management, and chronological audit history—are driven strictly by the backend REST APIs and persisted in PostgreSQL 16.

---

## 2. Existing Architecture Reviewed

Prior to implementation, the codebase was inspected across backend and frontend directories:

- **Backend Architecture (`backend/app/`)**:
  - `models/`: SQLAlchemy 2.0 domain entities (`Task`, `TaskHistory`, `Reminder`, `FollowUp`, `User`, `Client`, `Workflow`).
  - `services/`: Encapsulated domain business rules in `TaskService`, `ReminderService`, `FollowUpService`, `UserService`.
  - `api/routes/`: FastAPI REST routers for `/tasks`, `/reminders`, `/follow-ups`, `/auth`.
  - `schemas/`: Pydantic V2 request and response contracts enforcing strict validation.
- **Frontend Architecture (`apps/mobile_web/`)**:
  - `core/config/`: `ApiConfig` with dynamic base URL resolution for Web, Android Emulator (`10.0.2.2`), and Desktop (`127.0.0.1`).
  - `core/network/`: `ApiClient` handling JSON serialization, automatic Bearer JWT injection, centralized `ApiException` parsing (401, 404, 409, 422, network errors).
  - `core/storage/`: `TokenStorage` backed by `flutter_secure_storage`.
  - `providers/`: `AuthProvider` managing user authentication states with `ChangeNotifier`.
  - `screens/tasks/`: `TaskListScreen`, `TaskCreateScreen`, `TaskDetailScreen`.
  - `models/`: Immutable Dart data transfer models.

---

## 3. Files Created

1. `apps/mobile_web/lib/models/reminder/reminder_models.dart`: Models for `Reminder`, `ReminderCreateRequest`, and `ReminderResponse`.
2. `apps/mobile_web/lib/models/follow_up/follow_up_models.dart`: Models for `FollowUp`, `FollowUpCreateRequest`, `FollowUpResponse`, and `FollowUpCompleteRequest`.
3. `apps/mobile_web/test/unit/task_service_test.dart`: Unit tests with `MockClient` for all `TaskService` API integration methods.
4. `apps/mobile_web/test/integration/phase7_workflow_test.dart`: 25-step live end-to-end integration test exercising the complete workflow against live FastAPI and PostgreSQL.
5. `apps/mobile_web/integration_test/phase7_workflow_test.dart`: Integration test bundle for Flutter driver runner.
6. `docs/phase-7-report.md`: This comprehensive Phase 7 report.

---

## 4. Files Modified

1. `backend/app/services/reminder_service.py`: Added `list_task_reminders(db, task_id)` helper function.
2. `backend/app/api/routes/tasks.py`: Added `GET /api/v1/tasks/{task_id}/reminders` endpoint to retrieve reminders associated with a task.
3. `backend/tests/test_api_endpoints.py`: Added test assertion for `GET /api/v1/tasks/{task_id}/reminders`.
4. `apps/mobile_web/lib/models/task/task_models.dart`: Added domain models (`PostponeRequest`, `NextActionRequest`, `StatusChangeRequest`, `PriorityChangeRequest`, `AssignmentChangeRequest`, `SubjectLineChangeRequest`, `ReopenRequest`, `TaskHistory`) and computed getters (`isOverdue`, `isDueToday`, `isApproachingMaxAttempts`, `priorityWeight`).
5. `apps/mobile_web/lib/services/task/task_service.dart`: Added client methods for reminders (`getTaskReminders`, `createReminder`, `sendReminder`) and follow-ups (`getTaskFollowUps`, `createFollowUp`, `completeFollowUp`).
6. `apps/mobile_web/lib/widgets/common_widgets.dart`: Added `DueDateBadge`, `AttemptBadge`, `SectionCard`, and `AppDateFormat.formatRelativeDate`.
7. `apps/mobile_web/lib/screens/tasks/task_create_screen.dart`: Enhanced task creation screen with form validation, trimming, date-time pickers, priority selector, max attempts, and optional domain associations (client_id, workflow_id, assigned_user_id).
8. `apps/mobile_web/lib/screens/tasks/task_list_screen.dart`: Enhanced task list screen with real-time multi-field search (title, subject line, description), status choice chips, smart filter chips (Overdue, Due Today, Upcoming, Urgent/High, Near/At Max), and multi-criteria sorting.
9. `apps/mobile_web/lib/screens/tasks/task_detail_screen.dart`: Complete 10-section Task Detail screen with real API integration for all actions, dialogs, and timeline rendering.
10. `apps/mobile_web/test/widget_test.dart`: Expanded widget tests covering task list rendering, task creation form validation, and task detail 10-section rendering.

---

## 5. Task Creation Implementation

- **Screen**: `TaskCreateScreen` (`apps/mobile_web/lib/screens/tasks/task_create_screen.dart`)
- **Fields**:
  - **Required**: `Title` (trimmed, mandatory non-empty check).
  - **Optional**: `Description`, `Subject Line`, `Priority` (`low`, `medium`, `high`, `urgent`), `Due Date` (Date/Time picker), `Next Action Date` (Date/Time picker), `Max Attempts` (integer >= 1, defaults to 2), `Client ID`, `Workflow ID`, `Assigned User ID` (with UUID validation format helper).
- **Validation**:
  - Empty title is flagged with inline validation message.
  - Invalid UUID strings are caught before submission.
  - Due date and next action dates are formatted as ISO 8601 strings.
- **Submission**:
  - Calls `POST /api/v1/tasks`.
  - Shows loading indicator on the submit button.
  - On success: Pops with `true` result, triggers task list refresh, and displays success snackbar.
  - On failure: Preserves all entered form values and presents the server error message cleanly.

---

## 6. Task List Implementation

- **Screen**: `TaskListScreen` (`apps/mobile_web/lib/screens/tasks/task_list_screen.dart`)
- **Visual Design & Data Presentation**:
  - Task cards display Title, Subject line badge, Priority tag, Status badge, Due Date with relative indicator (`DueDateBadge`), Next Action date, Attempt count vs Max attempts (`AttemptBadge`), and Client ID if present.
  - Uses both color and distinct iconography/text for full accessibility.
  - Overdue tasks, tasks due today, urgent tasks, and tasks at max attempts are highlighted with accessible warning badges.
- **Search**:
  - Real-time text search filtering across task `title`, `subject_line`, and `description`.
- **Filters**:
  - Status choice chips: All, Pending, In Progress, Blocked, Completed, Cancelled.
  - Smart filter chips:
    - `Overdue`: Tasks where `due_date < now` and status != completed/cancelled.
    - `Due Today`: Tasks where `due_date` falls on current calendar day.
    - `Upcoming`: Tasks due in the future.
    - `Urgent / High`: Tasks with `urgent` or `high` priority.
    - `Near / At Max`: Tasks where `attempt_count >= max_attempts - 1`.
- **Sorting**:
  - Due Date (Earliest / Latest)
  - Priority (Urgent → High → Medium → Low)
  - Created Date (Newest / Oldest)
  - Updated Date (Newest / Oldest)
- **Lifecycle & Refresh**:
  - Pull-to-refresh (`RefreshIndicator`) and manual refresh icon in app bar.
  - Loading skeleton, empty state illustration with "Create Task" call-to-action, and error state with retry button.

---

## 7. Task Detail Implementation

- **Screen**: `TaskDetailScreen` (`apps/mobile_web/lib/screens/tasks/task_detail_screen.dart`)
- **Structure**:
  Organized into 10 dedicated `SectionCard` components:
  1. **Task Information**: Title, Description, Subject Line (with inline quick edit button), Workflow ID, Client ID.
  2. **Status**: Current status badge, status change button.
  3. **Priority**: Priority badge, priority change button.
  4. **Assignment**: Assignee ID/unassigned badge, assign/reassign button.
  5. **Dates & Scheduling**: Due date, Next action date, Created at, Updated at, Completed at (if completed).
  6. **Attempt Information**: Attempts counter (`X / Y`), progress indicator, Record Attempt button, Authorized Override button (enabled when at max).
  7. **Task Actions Bar**: Postpone, Change Next Action Date, Complete Task, Reopen Task.
  8. **Reminders**: List of scheduled/sent reminders, Send reminder trigger, Create reminder button.
  9. **Follow-ups**: List of follow-up items with completion checkboxes and completion notes dialog, Create follow-up button.
  10. **Chronological Audit History**: Full event timeline showing timestamp, action type, actor ID, and reason/details.

---

## 8. Attempt Workflow

- **Display**: Clear attempt counter widget showing `Attempts: X / Y` with colored progress indicator.
- **Normal Attempt**:
  - Calls `POST /api/v1/tasks/{task_id}/attempt`.
  - On success: Increments `attempt_count` by exactly 1, updates task state, reloads history, shows success feedback.
  - On 409 Conflict (Maximum attempts reached):
    - Catches `TASK_MAX_ATTEMPTS_REACHED` error.
    - Prompts user with dialog explaining maximum attempts have been reached and offering the "Use Authorized Override" action.
    - Server remains the sole source of truth; no local counter increment occurs prior to server confirmation.

---

## 9. Override Workflow

- **Trigger**: "Authorized Override" action button or prompt when 409 is received.
- **Dialog**:
  - Requires non-empty `Override Reason` (mandatory justification).
  - Validates reason input before allowing submission.
- **API Call**:
  - Calls `POST /api/v1/tasks/{task_id}/attempt/override` with `{ "reason": "..." }`.
- **Result**:
  - Permits one extra attempt beyond `max_attempts`.
  - Increments `attempt_count` on the backend.
  - Records an `attempt_override` event with the reason in `TaskHistory`.
  - Refreshes task and timeline immediately.

---

## 10. Postponement Workflow

- **Dialog**:
  - Prompts for `New Due Date` via date/time picker.
  - Requires non-empty `Postponement Reason` (mandatory).
- **API Call**:
  - Calls `POST /api/v1/tasks/{task_id}/postpone`.
- **Result**:
  - Updates `due_date` to the new date.
  - Preserves original due date in historical audit record (`TaskHistory`).
  - Records `postponed` action with reason.
  - Updates UI immediately and displays confirmation snackbar.

---

## 11. Next-Action Workflow

- **Action**: "Change Next Action Date" button.
- **Picker**: Material Date & Time picker for selecting future timestamp.
- **API Call**:
  - Calls `POST /api/v1/tasks/{task_id}/next-action` with `{ "next_action_date": "..." }`.
- **Result**:
  - Updates `next_action_date` on the server.
  - Records `next_action_date_changed` event in `TaskHistory`.
  - Refreshes task display immediately.

---

## 12. Completion / Reopen Workflow

- **Completion**:
  - Prompts with confirmation dialog: *"Complete this task? This will mark the task as finished."*
  - Calls `POST /api/v1/tasks/{task_id}/complete`.
  - Updates status to `completed`, records `completed_at` timestamp.
  - Backend prevents duplicate completion (returns 409 `TASK_ALREADY_COMPLETED`).
- **Reopen**:
  - Prompts with dialog requiring a non-empty `Reopen Reason`.
  - Calls `POST /api/v1/tasks/{task_id}/reopen` with `{ "reason": "..." }`.
  - Sets status back to `pending`, clears `completed_at`, records `reopened` event in history.
  - Refreshes UI and history timeline immediately.

---

## 13. Status / Priority / Assignment Workflow

- **Status Transition**:
  - Bottom sheet selector with available statuses (`pending`, `in_progress`, `blocked`, `completed`, `cancelled`).
  - Optional transition reason field.
  - Calls `POST /api/v1/tasks/{task_id}/status`.
- **Priority Change**:
  - Bottom sheet selector for priority (`low`, `medium`, `high`, `urgent`).
  - Optional justification reason.
  - Calls `POST /api/v1/tasks/{task_id}/priority`.
- **Assignment**:
  - Dialog for entering new `Assigned User ID` (or clearing assignment).
  - Calls `POST /api/v1/tasks/{task_id}/assign`.

---

## 14. Reminder Integration

- **Display**: Reminders section lists all reminders for the task, showing scheduled `remind_at` time, message, and `is_sent` status badge.
- **Creation**: Dialog allowing selection of reminder date/time and optional message; calls `POST /api/v1/reminders`.
- **Sending**: "Send Now" button triggers `POST /api/v1/reminders/{reminder_id}/send`.
- **Crucial Invariant**:
  - Reminders **NEVER** alter `attempt_count`, `max_attempts`, or task status.
  - Verified across unit tests, backend tests, and live integration tests.

---

## 15. Follow-Up Integration

- **Display**: Follow-ups section lists scheduled follow-ups with notes, scheduled date, and completion status checkbox.
- **Creation**: Dialog allowing selection of follow-up date and notes; calls `POST /api/v1/follow-ups`.
- **Completion**: Tapping follow-up checkbox opens dialog for optional completion notes and calls `POST /api/v1/follow-ups/{follow_up_id}/complete`.
- **Refresh**: Refreshes follow-ups list immediately upon mutation.

---

## 16. History Integration

- **API**: Calls `GET /api/v1/tasks/{task_id}/history`.
- **Display**:
  - Chronological timeline with color-coded event icons.
  - Displays formatted timestamp, human-readable action label (`Created`, `Work Attempt`, `Authorized Override`, `Postponed`, `Completed`, `Reopened`, `Priority Changed`, `Status Changed`, etc.).
  - Shows acting user ID (`Actor`) and reason/justification notes.

---

## 17. Error Handling

- **Architecture**:
  - Centralized in `lib/core/network/api_client.dart` and `ApiException`.
  - Maps HTTP status codes to typed exceptions with extracted backend error codes and messages.
- **Handled Scenarios**:
  - **401 Unauthorized**: Redirects session to login or triggers session expiration handler.
  - **404 Not Found**: Shows informative message ("Task no longer exists").
  - **409 Conflict**: Shows specific business rule message (e.g., max attempts reached, already completed).
  - **422 Validation Error**: Formats field validation errors for inline or snackbar display.
  - **Network / Connection Error**: Presents connection failure message with retry button.

---

## 18. Responsive UI

- UI components adapt cleanly to desktop browser windows, mobile views, and Android emulator viewports.
- Uses `SingleChildScrollView`, responsive cards, flexible column layouts, and touch/mouse-friendly hit targets.
- Preserves Android emulator networking (`10.0.2.2:8000`), desktop/web (`127.0.0.1:8000`), and `--dart-define=API_BASE_URL` override support.

---

## 19. Backend Changes

Minimal, non-breaking additions to support the Phase 7 UI requirements:
1. `backend/app/services/reminder_service.py`: Added `list_task_reminders(db: Session, task_id: uuid.UUID) -> List[Reminder]`.
2. `backend/app/api/routes/tasks.py`: Added endpoint:
   ```python
   @router.get("/{task_id}/reminders", response_model=List[ReminderResponse])
   def get_task_reminders_endpoint(db: DatabaseDep, current_user: CurrentUserDep, task_id: uuid.UUID)
   ```
3. Preserved all Phase 1–5 backend business rules, authentication models, and invariants.

---

## 20. Database Changes

- **Schema Modifications**: None.
- **Alembic Revision**: Unchanged (`7efe29531b9e`).
- Existing PostgreSQL 16 schema with 9 domain tables supports all Phase 7 operations directly.

---

## 21. Flutter Tests

- **Command**: `flutter test --suppress-analytics`
- **Result**: **63/63 PASS** (Phase 6 baseline was 36 tests)
- **Coverage**:
  - `test/unit/auth_service_test.dart`: 8 tests (AuthService register, login, me, token handling).
  - `test/unit/task_service_test.dart`: 11 tests (Task CRUD, attempts, override, postpone, complete, reopen, status, priority, assign, reminders, follow-ups).
  - `test/unit/token_storage_test.dart`: 3 tests (TokenStorage save, get, delete).
  - `test/widget_test.dart`: 6 tests (LoginScreen, HomeScreen, RegisterScreen navigation, TaskListScreen search/filters, TaskCreateScreen validation & submit, TaskDetailScreen 10-section rendering).
  - `test/integration/phase6_auth_flow_test.dart`: 11 tests (Phase 6 E2E integration).
  - `test/integration/phase7_workflow_test.dart`: 24 test assertions (Phase 7 25-step live integration workflow).

---

## 22. Backend Tests

- **Command**: `& ".\backend\.venv\Scripts\python.exe" -m pytest backend/tests -v`
- **Result**: **47/47 PASS** (0 failed, 0 skipped, 1 deprecation warning from testclient httpx)
- **Coverage**:
  - `test_api_endpoints.py`: 10 tests
  - `test_auth.py`: 7 tests
  - `test_business_services.py`: 15 tests
  - `test_database_domain.py`: 14 tests
  - `test_health.py`: 1 test

---

## 23. Live End-to-End Verification (25 Steps)

The live 25-step end-to-end integration workflow was executed against live FastAPI and live PostgreSQL 16 (`apps/mobile_web/test/integration/phase7_workflow_test.dart`):

| Step # | Action / Verification | Status | Verification Detail |
|---|---|---|---|
| 1 | Register & Login user | **PASS** | JWT obtained and stored in client session |
| 2 | Load task list from real PostgreSQL | **PASS** | Initial task collection fetched |
| 3 | Create task in PostgreSQL | **PASS** | Task created with `max_attempts=2`, `status=pending` |
| 4 | Open task detail | **PASS** | Task retrieved by UUID |
| 5 | Record 1st normal attempt | **PASS** | `attempt_count` incremented: 0 → 1 |
| 6 | Record 2nd normal attempt | **PASS** | `attempt_count` incremented: 1 → 2 (reaches max) |
| 7 | Attempt 3rd normal attempt | **PASS** | Backend rejects with HTTP 409 `TASK_MAX_ATTEMPTS_REACHED` |
| 8 | Verify 409 error structure | **PASS** | Domain error code and message verified |
| 9 | Perform authorized override with reason | **PASS** | Called `/attempt/override` with justification |
| 10 | Verify attempt count increases | **PASS** | `attempt_count` incremented to 3 (> max_attempts 2) |
| 11 | Postpone task with reason | **PASS** | Called `/postpone` with new due date & reason |
| 12 | Verify due date changes | **PASS** | `due_date` updated to new timestamp |
| 13 | Verify history records postponement | **PASS** | History contains `postponed` action with reason |
| 14 | Change next action date | **PASS** | Next action date scheduled and saved |
| 15 | Create reminder | **PASS** | Reminder created for task |
| 16 | Verify reminder invariant | **PASS** | `attempt_count` remains exactly 3 before and after reminder sent |
| 17 | Create and complete follow-up | **PASS** | Follow-up created and marked complete with notes |
| 18 | Change priority | **PASS** | Priority transitioned to `urgent` |
| 19 | Change status | **PASS** | Status transitioned to `in_progress` |
| 20 | Complete task | **PASS** | Task marked `completed`, `completed_at` timestamp set |
| 21 | Verify duplicate completion rejection | **PASS** | Second completion attempt rejected with HTTP 409 |
| 22 | Reopen task with mandatory reason | **PASS** | Task status set to `pending`, `completed_at` cleared |
| 23 | Verify complete chronological history | **PASS** | History includes `created`, `attempt`, `attempt_override`, `postponed`, `completed`, `reopened`, `priority_changed` |
| 24 | Refresh application / re-fetch | **PASS** | Application state re-fetched from server |
| 25 | Verify state persists from PostgreSQL | **PASS** | All state, reminders, follow-ups, and history verified persisted |

---

## 24. Remaining Limitations

1. Offline caching / optimistic local updates: Mutations currently require online connectivity with the FastAPI server.
2. Push notifications: Reminder sending is recorded via REST API; device-level push notification delivery (e.g. FCM) is planned for future phases.

---

## 25. Known Warnings

1. `StarletteDeprecationWarning`: `Using httpx with starlette.testclient is deprecated` (upstream FastAPI/Starlette notice in test suite).
2. Flutter deprecation notices on older Material properties (`accentColor`, `withOpacity` vs `withValues`).

---

## 26. Exact Commands Used for Verification

```powershell
# 1. Backend static compilation check
& ".\backend\.venv\Scripts\python.exe" -m compileall backend/app

# 2. Run backend full pytest test suite (47 tests)
& ".\backend\.venv\Scripts\python.exe" -m pytest backend/tests -v

# 3. Flutter static code analysis
cd "C:\bhanu\NEXT ACTION\apps\mobile_web"
flutter analyze --suppress-analytics

# 4. Flutter full test suite (63 tests including unit, widget, and live E2E integration)
flutter test --suppress-analytics
```

---

## 27. Final Status

| Component | Status | Details |
|---|---|---|
| Real Task Creation UX | **PASS** | Complete validation, date pickers, priority, associations |
| Real Task List UX | **PASS** | Real-time search, status choice chips, smart filter chips, multi-sorting |
| Real Task Detail UX | **PASS** | Complete 10 sections rendered and fully interactive |
| Attempt Workflow | **PASS** | Normal attempts increment count; 409 on max attempts |
| Authorized Override | **PASS** | Extra attempt granted with mandatory justification |
| Postponement Workflow | **PASS** | Preserves original due date in history; updates due date |
| Next-Action Workflow | **PASS** | Schedules next-action date via date picker |
| Completion & Reopen | **PASS** | Idempotency enforced; duplicate completion rejected; reopen requires reason |
| Status / Priority / Assignment | **PASS** | Real-time transitions via dialogs/bottom sheets |
| Subject Line Editing | **PASS** | Quick edit with save and validation |
| Reminders Integration | **PASS** | Scheduled and sent without altering attempt count invariant |
| Follow-ups Integration | **PASS** | Creation, listing, and completion with notes |
| History Integration | **PASS** | Chronological timeline of all lifecycle events |
| Error Handling | **PASS** | Centralized 401, 404, 409, 422, and network error handling |
| Responsive UI | **PASS** | Adapts to Web, Desktop, and Android Emulator viewports |
| Backend & DB Integrity | **PASS** | 47 backend tests pass; PostgreSQL 16 schema preserved |
| Flutter Test Suite | **PASS** | 63 tests pass with 0 errors and 0 analyzer issues |
| Live 25-step E2E Verification | **PASS** | 100% verified against live backend and PostgreSQL |
