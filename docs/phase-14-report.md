# Phase 14 Report — Task Templates, Recurring Tasks & Workflow Automation

**Project:** NextAction (`C:\bhanu\NEXT ACTION`)  
**Phase:** 14 — Task Templates, Recurring Tasks & Workflow Automation  
**Date:** September 29, 2026  
**Status:** **PASS**

---

## 1. Objective
NextAction supports comprehensive task lifecycle management, multi-entity associations (Clients, Workflows, Users), due dates, next action dates, reminders, follow-ups, notifications, full-text search, advanced filters, and audit history.

Phase 14 delivers a production-grade, extensible automation architecture designed to eliminate repetitive manual task creation while preserving domain invariants, security isolation, and data integrity:
1. **Task Templates**: Reusable blueprint definitions containing standard metadata (subject lines, descriptions, client/workflow/assignee defaults, priority, max attempts, and relative offset days for due/next-action dates).
2. **Recurring Task Definitions**: Controlled scheduling rules supporting `daily`, `weekly`, and `monthly` recurrence intervals with calendar-safe month-end clamping.
3. **Controlled Batch Generation**: Idempotent batch evaluation (`/api/v1/recurring-tasks/evaluate`) with database-enforced uniqueness constraints to prevent duplicate task generation across runs.
4. **Source Traceability & Audit History**: Direct foreign key linking (`template_id`, `recurring_task_id` on `Task`) and automated history logging (`created_from_template`, `generated_from_recurrence`).
5. **Seamless UI Integration**: Dedicated Flutter management screens (`TaskTemplatesScreen`, `TaskTemplateCreateScreen`, `RecurringTasksScreen`), template selection in `TaskCreateScreen`, source badges in `TaskDetailScreen`, and dashboard quick access.

---

## 2. Existing Architecture Inspected
Prior to implementation, the existing Phase 1–13 architecture was thoroughly inspected:
- **Backend Domain**:
  - `Task` model in `backend/app/models/task.py` with foreign keys to `Client`, `Workflow`, `User`, and relationships to `TaskHistory`, `Reminder`, `FollowUp`, `Notification`, and `Event`.
  - `TaskService` in `backend/app/services/task_service.py` maintaining attempt invariants, status transitions, and history logging.
  - Existing Alembic migration history (Phases 1–13 at head `d5e6f7a8b9c0`).
  - Auth dependency via JWT bearer token in `backend/app/api/dependencies.py`.
- **Flutter Client**:
  - `TaskCreateScreen`, `TaskDetailScreen`, `TaskListScreen`, `HomeScreen`.
  - `ApiClient` with automatic `/api/v1` base URL routing and token persistence.
  - Reusable selectors for clients, workflows, users, and priorities.

---

## 3. Task Template Model
Implemented in `backend/app/models/task_template.py`:
- `id` (UUID, Primary Key, default `uuid4`)
- `name` (String(255), non-null)
- `description` (Text, nullable)
- `subject_line` (String(500), nullable)
- `workflow_id` (UUID, FK -> `workflows.id`, nullable, ondelete SET NULL)
- `client_id` (UUID, FK -> `clients.id`, nullable, ondelete SET NULL)
- `assigned_user_id` (UUID, FK -> `users.id`, nullable, ondelete SET NULL)
- `priority` (Enum `TaskPriority`, default `medium`)
- `max_attempts` (Integer, default 2, check `>= 1`)
- `default_due_offset_days` (Integer, nullable, check `>= 0`)
- `default_next_action_offset_days` (Integer, nullable, check `>= 0`)
- `is_active` (Boolean, default `True`, indexed)
- `created_by_user_id` (UUID, FK -> `users.id`, non-null, ondelete CASCADE)
- `created_at` (DateTime with timezone, non-null)
- `updated_at` (DateTime with timezone, non-null)

*Key Invariant*: Templates are reusable blueprints, NOT tasks. They do not participate in attempt counting, cannot be completed/cancelled, and do not trigger task execution flows.

---

## 4. Template APIs
Registered under `/api/v1/task-templates`:
- `POST /api/v1/task-templates` — Create a template (creator extracted securely from JWT `current_user`).
- `GET /api/v1/task-templates` — List templates with search, active filtering, and pagination.
- `GET /api/v1/task-templates/{id}` — Retrieve template details.
- `PATCH /api/v1/task-templates/{id}` — Update template fields (creator-only).
- `DELETE /api/v1/task-templates/{id}` — Delete template (creator-only).
- `POST /api/v1/task-templates/{id}/create-task` — Instantiate a concrete `Task` from template with optional field overrides.

---

## 5. Template Authorization
- **Authentication**: JWT Bearer token required for all endpoints.
- **Creator Isolation**: `created_by_user_id` is automatically injected from the authenticated `current_user` in the JWT token.
- **Modification/Deletion Control**: Only the creator of a template can modify (`PATCH`) or delete (`DELETE`) it. Unauthorized attempts return HTTP 403 Forbidden.
- **Entity Validation**: Referenced `client_id`, `workflow_id`, and `assigned_user_id` are validated against database records. Inactive or nonexistent users are strictly rejected with HTTP 400 Bad Request.

---

## 6. Create-from-Template Workflow
The `POST /api/v1/task-templates/{id}/create-task` endpoint executes the following workflow:
1. Validates user authentication and template existence.
2. Loads template defaults (`name` -> `title`, `description`, `subject_line`, `client_id`, `workflow_id`, `assigned_user_id`, `priority`, `max_attempts`).
3. Computes `due_date = now + default_due_offset_days` (if offset defined and no explicit override provided).
4. Computes `next_action_date = now + default_next_action_offset_days` (if offset defined and no explicit override provided).
5. Applies explicit caller overrides (e.g. customized title, priority, assignee, due date).
6. Creates a full, concrete `Task` instance in `tasks` table with `template_id` persisted.
7. Generates audit history record (`action="created_from_template"`).
8. Fires assignee notification if `assigned_user_id` is populated.

---

## 7. Recurring Task Model
Implemented in `backend/app/models/recurring_task.py`:
- `RecurringTask`:
  - `id` (UUID, Primary Key)
  - `name` (String(255), non-null)
  - `template_id` (UUID, FK -> `task_templates.id`, nullable)
  - `description` (Text, nullable)
  - `subject_line` (String(500), nullable)
  - `workflow_id` (UUID, FK -> `workflows.id`, nullable)
  - `client_id` (UUID, FK -> `clients.id`, nullable)
  - `assigned_user_id` (UUID, FK -> `users.id`, nullable)
  - `priority` (Enum `TaskPriority`, default `medium`)
  - `max_attempts` (Integer, default 2)
  - `due_offset_days` (Integer, nullable)
  - `next_action_offset_days` (Integer, nullable)
  - `recurrence_type` (Enum: `daily`, `weekly`, `monthly`, `custom_interval`)
  - `interval` (Integer, default 1, check `>= 1`)
  - `day_of_week` (Integer 0-6, nullable)
  - `day_of_month` (Integer 1-31, nullable)
  - `start_date` (DateTime with timezone, non-null)
  - `end_date` (DateTime with timezone, nullable)
  - `next_run_at` (DateTime with timezone, non-null, indexed)
  - `last_run_at` (DateTime with timezone, nullable)
  - `is_active` (Boolean, default `True`, indexed)
  - `created_by_user_id` (UUID, FK -> `users.id`, non-null)

- `RecurringTaskExecution` (Audit & Idempotency Store):
  - `id` (UUID, Primary Key)
  - `recurring_task_id` (UUID, FK -> `recurring_tasks.id`, non-null, ondelete CASCADE)
  - `scheduled_for` (DateTime with timezone, non-null)
  - `task_id` (UUID, FK -> `tasks.id`, nullable, ondelete SET NULL)
  - `status` (String(50), default `success`)
  - `created_at` (DateTime with timezone, non-null)
  - **Unique Constraint**: `uq_recurring_execution (recurring_task_id, scheduled_for)`

---

## 8. Recurrence Rules & Types
- **DAILY**: Scheduled every `N` days (`current_run + timedelta(days=interval)`).
- **WEEKLY**: Scheduled every `N` weeks with optional alignment to specified day of week (`day_of_week` 0=Monday .. 6=Sunday).
- **MONTHLY**: Scheduled every `N` months with calendar month arithmetic. If the specified `day_of_month` exceeds the target month's maximum days (e.g. Jan 31 -> Feb), it automatically clamps to the last valid day of that month (e.g. Feb 28/29).
- **CUSTOM_INTERVAL**: Generic day interval increment (`current_run + timedelta(days=interval)`).
- Arbitrary unverified cron strings are excluded to prevent fragile scheduling errors.

---

## 9. Recurrence APIs
Registered under `/api/v1/recurring-tasks`:
- `POST /api/v1/recurring-tasks` — Create recurring task schedule definition.
- `GET /api/v1/recurring-tasks` — List recurring tasks with search, active filter, pagination.
- `GET /api/v1/recurring-tasks/{id}` — Get recurring task details.
- `PATCH /api/v1/recurring-tasks/{id}` — Update schedule parameters (creator-only).
- `DELETE /api/v1/recurring-tasks/{id}` — Delete schedule definition (creator-only).
- `POST /api/v1/recurring-tasks/evaluate` — Controlled batch execution endpoint evaluating due definitions and instantiating tasks.

---

## 10. Duplicate Prevention & Idempotency
- **Mechanism**: The `recurring_task_executions` table enforces a database-level unique constraint on `(recurring_task_id, scheduled_for)`.
- **Behavior**: When `/api/v1/recurring-tasks/evaluate` is called repeatedly for the same due occurrence:
  1. The first run detects no execution record, generates the `Task`, inserts the execution log, updates `last_run_at`, and advances `next_run_at` to the next occurrence.
  2. Subsequent calls for the same occurrence find `next_run_at` already advanced or find the existing execution record and generate **0 duplicate tasks**.
- **Verified Invariant**: If evaluate is called 100 times for the same due occurrence, **exactly 1 task instance is created**.

---

## 11. Recurrence Evaluation Architecture
- Follows the established controlled evaluation pattern from Phase 12 notifications.
- Bounded execution with configurable `max_evaluations` (default 50, maximum 100).
- Automatically deactivates recurring tasks (`is_active = False`) once `next_run_at` exceeds `end_date`.
- Transactional safety: Each definition evaluation is committed with its task generation, history record, and execution entry.

---

## 12. Date Semantics & Month-End Handling
- **Daily Math**: `current_run + timedelta(days=interval)`
- **Weekly Math**: `current_run + timedelta(weeks=interval)` with weekday offset alignment.
- **Monthly Month-End Policy**:
  - Computes `target_year` and `target_month` via integer division.
  - Queries `calendar.monthrange(target_year, target_month)[1]` for maximum days.
  - Uses `min(day_of_month, max_days)` to guarantee safe dates (e.g. Jan 31 -> Feb 28 in non-leap years, Feb 29 in leap years, Aug 31 -> Sep 30).
  - Preserves exact time component (hour, minute, second, microsecond).

---

## 13. Task Source Traceability
Tasks track their provenance via nullable foreign keys in the `tasks` table:
- `template_id` (UUID, nullable, FK -> `task_templates.id`, `ondelete=SET NULL`)
- `recurring_task_id` (UUID, nullable, FK -> `recurring_tasks.id`, `ondelete=SET NULL`)
- **Backward Compatibility**: Existing manual tasks retain `NULL` for both fields.
- **UI Exposure**: `TaskDetailScreen` displays explicit source badges (`Manual`, `Template: <Name>`, `Recurrence: <Name>`).

---

## 14. Task History & Auditing
Generated tasks fully participate in NextAction's audit history system (`task_history` table):
- Manual task: `action="created"`
- Template instantiation: `action="created_from_template"`, recording template ID and name.
- Recurrence generation: `action="generated_from_recurrence"`, recording recurrence schedule ID and scheduled timestamp.

---

## 15. Reminder, Follow-Up & Next Action Interaction
- Generated tasks inherit relative due dates and next action dates computed from template/recurrence offset settings.
- Independent lifecycle: Reminders and follow-ups can be added to generated tasks exactly like manually created tasks without duplication or conflicts.
- Verified in live E2E tests: Follow-ups and reminders created on template/recurring tasks persist and evaluate correctly.

---

## 16. Notification Integration
- When a task is generated from a template or recurrence and assigned to a user (`assigned_user_id`), the existing notification system automatically dispatches an `ASSIGNMENT` notification to the assignee.
- Prevents notification storms: Recurrence execution creates notifications solely for newly assigned tasks and respects deduplication keys.

---

## 17. Flutter UI
- **`TaskTemplatesScreen`**: Displays all templates with active status chips, search bar, filter toggle, pull-to-refresh, empty/error/loading states, and action buttons ("Create Task", "Edit", "Deactivate", "Delete").
- **`TaskTemplateCreateScreen`**: Clean form for template name, description, subject line, client/workflow/assignee selectors, priority dropdown, max attempts, and relative offset inputs.
- **`RecurringTasksScreen`**: Schedule definition list, active/paused badges, next run timestamp, interval indicators, "Run Evaluation" trigger button with instant feedback, and schedule creation.
- **`TaskCreateScreen`**: Added template picker dropdown that pre-populates form fields for immediate review and customization before task creation.
- **`TaskDetailScreen`**: Source badges ("Template: ...", "Recurrence: ...", "Manual") integrated into task summary cards.

---

## 18. Dashboard & Navigation Integration
- **`HomeScreen` Drawer**: Added navigation links for "Task Templates" and "Recurring Tasks" with icons.
- **`HomeScreen` Action Scheduling Hub**: Added filter/navigation chips for quick navigation to Task Templates and Recurring Tasks.

---

## 19. Search & Filter Integration
- Generated tasks are fully indexed by the backend search engine and appear in search results across title, description, and subject lines.
- Filterable by client, workflow, assignee, status, priority, and date ranges without any schema incompatibilities.

---

## 20. Security Verification
- [x] Unauthenticated template & recurrence API requests rejected with HTTP 401 Unauthorized.
- [x] Creator identity extracted securely from JWT `current_user` (never trusted from request body).
- [x] Cross-user template and recurring task modification (`PATCH`) rejected with HTTP 403 Forbidden.
- [x] Cross-user template and recurring task deletion (`DELETE`) rejected with HTTP 403 Forbidden.
- [x] Inactive assignee assignment rejected with HTTP 400 Bad Request.
- [x] Nonexistent client/workflow references rejected with HTTP 404 Not Found.

---

## 21. Performance & Scalability
- Bounded batch evaluation (`max_evaluations <= 100`) prevents runaway executions or unbounded memory consumption.
- Indexed columns on `next_run_at`, `is_active`, and foreign keys ensure fast query planning (`EXPLAIN` queries use index scans).
- Database unique constraints guarantee atomicity without expensive distributed locks.

---

## 22. Backend Tests
- **Test File**: `backend/tests/test_templates_and_recurring.py` (and existing test files).
- **Results**: **104 / 104 passed (100%)**.
- **Coverage**:
  - `test_unauthenticated_template_and_recurrence_apis_rejected`: PASS
  - `test_task_template_crud_and_creator_isolation`: PASS
  - `test_create_task_from_template_with_offsets_and_overrides`: PASS
  - `test_recurrence_date_math_calculations`: PASS (Daily, Weekly, Monthly month-end clamping Jan 31 -> Feb 28)
  - `test_recurring_task_lifecycle_and_idempotent_evaluation`: PASS (duplicate prevention, advancement)
  - `test_invalid_template_references_rejected`: PASS
  - `test_invalid_recurrence_rules_rejected`: PASS
  - `test_recurrence_with_assigned_user_generates_notification`: PASS

---

## 23. Flutter Tests
- **Test Files**:
  - `apps/mobile_web/test/integration/phase14_templates_and_recurring_test.dart` (7 UI tests)
  - `apps/mobile_web/test/integration/phase14_live_e2e_test.dart` (22 live E2E tests)
  - Existing widget and integration test suite across all modules.
- **Results**: **274 / 274 passed (100%)**.
- **Analyzer**: `flutter analyze --suppress-analytics` -> **0 issues found!**

---

## 24. Live E2E Verification
Executed against live PostgreSQL (`nextaction_db`) and live FastAPI (`http://127.0.0.1:8000`):
1. Register and authenticate primary user and secondary user: **PASS**
2. Create client/workflow/user data: **PASS**
3. Create task template with offset days and default associations: **PASS**
4. View template (single retrieval and list search): **PASS**
5. Edit template properties and verify changes: **PASS**
6. Create task from template with offsets and overrides: **PASS**
7. Verify generated task in repository with proper status & computed dates: **PASS**
8. Verify task history contains `created_from_template` audit log: **PASS**
9. Verify template source traceability on task: **PASS**
10. Create daily recurrence schedule: **PASS**
11. Evaluate recurrence in controlled batch: **PASS**
12. Verify exactly one task generated: **PASS**
13. Evaluate again immediately (idempotency verification): **PASS**
14. Verify no duplicate tasks created: **PASS**
15. Advance next run into past and evaluate: **PASS**
16. Verify next task generated (exactly 2 tasks exist): **PASS**
17. Verify source traceability and audit logs on both tasks: **PASS**
18. Verify assignment notifications dispatched: **PASS**
19. Verify existing reminders & follow-ups still work on generated tasks: **PASS**
20. Verify search/filter finds generated tasks by keyword: **PASS**
21. Verify unauthorized user cannot access/modify another user's template or recurrence: **PASS**
22. Verify existing task state machine, attempts, and completion work on generated tasks: **PASS**

---

## 25. Regression Results
- **Phase 13 Baseline**: Backend 96 passed | Flutter 245 passed | Analyzer 0 issues.
- **Phase 14 Final**:
  - **Backend**: **104 passed** (+8 new automated tests, 0 failures).
  - **Flutter**: **274 passed** (+29 new automated tests, 0 failures).
  - **Analyzer**: **0 issues** (clean).
  - **No regressions** across Tasks, Clients, Workflows, Users, Scheduling, Notifications, or Search.

---

## 26. Known Limitations
- Cron expression strings (e.g. `*/15 * * * *`) are deliberately not accepted in favor of explicit `daily`, `weekly`, `monthly`, and `custom_interval` recurrence types for maximum reliability.
- In this phase, recurring task evaluation is triggered via explicit API invocation (`/api/v1/recurring-tasks/evaluate`) and UI evaluation buttons, ready for background scheduler daemon integration in subsequent phases.

---

## 27. Warnings
- Deleting a task template sets `template_id` to `NULL` on generated tasks (`ondelete=SET NULL`) to preserve task integrity and history.
- When configuring monthly recurrence for the 31st of a month, shorter months (February, April, June, September, November) will evaluate on the final day of the respective month.

---

## 28. Exact Verification Commands
```powershell
# 1. Run Alembic database migrations
& ".\backend\.venv\Scripts\python.exe" -m alembic -c backend/alembic.ini upgrade head

# 2. Run backend test suite
& ".\backend\.venv\Scripts\python.exe" -m pytest backend/tests -v

# 3. Run Flutter static analysis
cd apps/mobile_web
flutter analyze --suppress-analytics

# 4. Run Flutter test suite
flutter test --suppress-analytics

# 5. Run Live End-to-End Test (with backend server running)
flutter test test/integration/phase14_live_e2e_test.dart --suppress-analytics
```

---

## 29. Final Status
- **Task Templates**: **PASS**
- **Template Authorization**: **PASS**
- **Create-from-Template Workflow**: **PASS**
- **Recurring Task Definitions**: **PASS**
- **Safe Recurrence Rules & Month-End Clamping**: **PASS**
- **Duplicate Prevention & Idempotency**: **PASS**
- **Controlled Recurrence Evaluation**: **PASS**
- **Source Traceability & Audit History**: **PASS**
- **Reminder & Follow-up Compatibility**: **PASS**
- **Notification Integration**: **PASS**
- **Flutter UI & Navigation**: **PASS**
- **Backend Tests (104/104)**: **PASS**
- **Flutter Tests (274/274)**: **PASS**
- **Flutter Analyzer (0 issues)**: **PASS**
- **Live E2E (22/22)**: **PASS**
- **Overall Phase 14 Status**: **PASS**
