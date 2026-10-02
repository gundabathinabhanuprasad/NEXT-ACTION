# NextAction Phase 3: Business Logic & Service Layer Design

## 1. Executive Summary
Phase 3 implements the core business rules of NextAction in a clean, isolated backend service layer without coupling to HTTP controllers or frontend code. The services interface directly with SQLAlchemy 2.0 ORM models and PostgreSQL 16, guaranteeing transactional consistency, domain invariant validation, and comprehensive audit history logging.

---

## 2. Service Architecture

The business logic is partitioned into modular, single-responsibility service modules under `backend/app/services/`:

```
backend/app/services/
├── __init__.py           # Package exports for clean public API
├── exceptions.py         # Domain-level exceptions (uncoupled from HTTP/ORM)
├── history_service.py    # Audit logging helper for immutable TaskHistory records
├── task_service.py       # Core Task lifecycle, attempt tracking, and postponement rules
├── reminder_service.py   # Notification management & attempt-invariant preservation
└── follow_up_service.py  # Follow-up scheduling and completion
```

---

## 3. Domain Exceptions Hierarchy

All domain exceptions inherit from `NextActionDomainError` to avoid leaking low-level ORM or driver exceptions:

- `NextActionDomainError` (Base domain exception)
  - `TaskNotFoundError` — Task does not exist for the provided UUID.
  - `TaskCompletedError` — Operation attempted on a completed task (e.g. attempt, postponement).
  - `TaskAlreadyCompletedError` — Completion requested on an already completed task.
  - `TaskCancelledError` — Operation attempted on a cancelled task.
  - `TaskNotCompletedError` — Reopen requested on a task that is not completed.
  - `MaxAttemptsReachedError` — Attempt attempted after reaching `max_attempts` without authorized override.
  - `OverrideReasonRequiredError` — Authorized override attempted without a non-empty reason.
  - `PostponementReasonRequiredError` — Postponement attempted without a non-empty reason.
  - `ReopenReasonRequiredError` — Reopen attempted without a non-empty reason.
  - `InvalidTaskDateError` — Date parameter fails validation or timezone expectations.
  - `InvalidTaskStateError` — Task state is incompatible with the requested action.
  - `InvalidStatusTransitionError` — Status transition requested is not permitted.
  - `ReminderNotFoundError` — Reminder does not exist for the provided UUID.
  - `FollowUpNotFoundError` — Follow-up does not exist for the provided UUID.

---

## 4. Core Business Rules

### 4.1 Rule 1: Task Creation & Initial Defaults
- **Function**: `create_task(db, title, ...)`
- **Defaults**: `status=TaskStatus.PENDING`, `priority=TaskPriority.MEDIUM`, `attempt_count=0`, `max_attempts=2`.
- **History Action**: `"created"`. The initial state payload (title, status, priority, max_attempts, due_date, next_action_date) is serialized into `new_value`.

### 4.2 Rule 2 & 3: Attempt Tracking & Max Attempts Enforcement
- **Function**: `record_attempt(db, task_id, user_id=None, notes=None, authorized_override=False, override_reason=None)`
- **Invariants**:
  - Task must exist and must not be in `COMPLETED` or `CANCELLED` status.
  - If `attempt_count < max_attempts`: Increments `attempt_count` by exactly 1 and records `TaskHistory` with `action="attempt"`, `old_value=str(previous_count)`, `new_value=str(new_count)`, and `reason=notes`.
  - If `attempt_count >= max_attempts` and `authorized_override=False`: Raises `MaxAttemptsReachedError`. Counter is **not** incremented, and no attempt history record is created.

### 4.3 Rule 4: Authorized Override Mechanism
- **Invariants**:
  - Overrides must be explicitly authorized (`authorized_override=True`).
  - An override reason is **mandatory**; if missing or whitespace-only, raises `OverrideReasonRequiredError`.
  - Grants exactly one additional attempt (`attempt_count += 1`).
  - Records `TaskHistory` with `action="attempt_override"`, `old_value=str(previous_count)`, `new_value=str(new_count)`, and `reason=supplied_reason`.

### 4.4 Rule 5: Reminder Invariant
- **Functions**: `create_reminder(db, task_id, remind_at, message)`, `process_reminder(db, reminder_id)`
- **Critical Invariant**:
  - Creating a reminder creates a `Reminder` record and does **NOT** modify `Task.attempt_count`.
  - Processing/sending a reminder marks `Reminder.is_sent = True` and does **NOT** modify `Task.attempt_count` or create an `"attempt"` audit record.

### 4.5 Rule 6: Task Postponement
- **Function**: `postpone_task(db, task_id, new_due_date, reason, user_id=None)`
- **Invariants**:
  - Task must not be completed or cancelled.
  - Postponement reason is **mandatory**; missing reason raises `PostponementReasonRequiredError`.
  - The original due date is preserved in `TaskHistory`:
    - `action = "postponed"`
    - `old_value = original_due_date.isoformat()`
    - `new_value = new_due_date.isoformat()`
    - `reason = supplied_reason`
  - Updates `task.due_date = new_due_date`.

### 4.6 Rule 7: Next Action Date Management
- **Function**: `update_next_action_date(db, task_id, next_action_date, user_id=None)`
- **Invariants**:
  - Updates `task.next_action_date`.
  - Records `TaskHistory` with `action="next_action_date_changed"`, capturing old and new ISO timestamp strings.

### 4.7 Rule 8: Task Completion
- **Function**: `complete_task(db, task_id, user_id=None)`
- **Invariants**:
  - Sets `task.status = TaskStatus.COMPLETED` and `task.completed_at = datetime.now(timezone.utc)`.
  - Records `TaskHistory` with `action="completed"`.
  - Calling `complete_task` on an already completed task raises `TaskAlreadyCompletedError`.

### 4.8 Rule 9: Reopening Completed Tasks
- **Function**: `reopen_task(db, task_id, reason, user_id=None)`
- **Invariants**:
  - Requires task to currently be in `TaskStatus.COMPLETED` status (otherwise raises `TaskNotCompletedError`).
  - Reason is **mandatory**; missing reason raises `ReopenReasonRequiredError`.
  - Restores `task.status = TaskStatus.PENDING` and clears `task.completed_at = None`.
  - Records `TaskHistory` with `action="reopened"` and `reason=supplied_reason`.

### 4.9 Rule 10, 11, 12, 13: Attribute Transitions & History Logging
- **`change_status`**: Controlled status transitions with `action="status_changed"`.
- **`change_priority`**: Priority transitions (`low`, `medium`, `high`, `urgent`) with `action="priority_changed"`.
- **`assign_task`**: Reassignments with `action="reassigned"`, recording old and new user UUIDs.
- **`update_subject_line`**: Subject line edits with `action="subject_line_changed"`.

### 4.10 Rule 14: Date Validation
- `validate_task_dates` ensures dates are valid `datetime` instances. All services standardize on timezone-aware UTC timestamps (`datetime.now(timezone.utc)`).

### 4.11 Rule 15: History Preservation
- Every mutation logs an immutable `TaskHistory` record.
- As established in Phase 2, `TaskHistory` records survive `Task` deletion (`task_id` is set to `NULL`), preserving full historical auditability.

---

## 5. Transaction Safety
All multi-entity mutations (e.g. updating task fields while inserting audit history entries) are executed within atomic database transactions:
- Successful operations commit atomically via `db.commit()`.
- If an exception is raised or validation fails, uncommitted changes roll back cleanly, leaving no orphaned or partially updated state.

---

## 6. Verification Summary
- **Backend Test Suite**: 30 passing tests against real PostgreSQL 16 container (`backend/tests/`).
- **Python Compilation**: `compileall` passed cleanly on `backend/app`.
- **Flutter Health**: `flutter analyze` (0 issues) and `flutter test` (all passed).
