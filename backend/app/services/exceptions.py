"""Domain exceptions for NextAction business logic."""

from typing import Optional
import uuid


class NextActionDomainError(Exception):
    """Base exception for all NextAction domain errors."""

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(self.message)


class TaskNotFoundError(NextActionDomainError):
    """Raised when a task cannot be found."""

    def __init__(self, task_id: uuid.UUID) -> None:
        super().__init__(f"Task with id '{task_id}' was not found.")
        self.task_id = task_id


class TaskCompletedError(NextActionDomainError):
    """Raised when an operation cannot be performed because the task is completed."""

    def __init__(self, task_id: uuid.UUID, action: Optional[str] = None) -> None:
        msg = f"Cannot perform action '{action}' on completed task '{task_id}'." if action else f"Task '{task_id}' is already completed."
        super().__init__(msg)
        self.task_id = task_id
        self.action = action


class TaskAlreadyCompletedError(TaskCompletedError):
    """Raised when attempting to complete an already completed task."""

    def __init__(self, task_id: uuid.UUID) -> None:
        super().__init__(task_id=task_id, action="complete")


class TaskCancelledError(NextActionDomainError):
    """Raised when an operation cannot be performed because the task is cancelled."""

    def __init__(self, task_id: uuid.UUID, action: Optional[str] = None) -> None:
        msg = f"Cannot perform action '{action}' on cancelled task '{task_id}'." if action else f"Task '{task_id}' is cancelled."
        super().__init__(msg)
        self.task_id = task_id
        self.action = action


class TaskNotCompletedError(NextActionDomainError):
    """Raised when an operation requires the task to be completed (e.g., reopen)."""

    def __init__(self, task_id: uuid.UUID) -> None:
        super().__init__(f"Task '{task_id}' is not completed and cannot be reopened.")
        self.task_id = task_id


class MaxAttemptsReachedError(NextActionDomainError):
    """Raised when task attempt count reaches or exceeds max_attempts without authorized override."""

    def __init__(self, task_id: uuid.UUID, attempt_count: int, max_attempts: int) -> None:
        super().__init__(
            f"Maximum attempts reached for task '{task_id}' ({attempt_count}/{max_attempts}). Authorized override required."
        )
        self.task_id = task_id
        self.attempt_count = attempt_count
        self.max_attempts = max_attempts


class OverrideReasonRequiredError(NextActionDomainError):
    """Raised when an authorized override is requested without a valid reason."""

    def __init__(self) -> None:
        super().__init__("An override reason is mandatory when performing an authorized attempt override.")


class PostponementReasonRequiredError(NextActionDomainError):
    """Raised when postponing a task without providing a reason."""

    def __init__(self) -> None:
        super().__init__("A reason is mandatory when postponing a task.")


class ReopenReasonRequiredError(NextActionDomainError):
    """Raised when reopening a task without providing a reason."""

    def __init__(self) -> None:
        super().__init__("A reason is mandatory when reopening a completed task.")


class InvalidTaskDateError(NextActionDomainError):
    """Raised when a task date violates scheduling invariants."""

    def __init__(self, message: str) -> None:
        super().__init__(message)


class InvalidTaskStateError(NextActionDomainError):
    """Raised when a task is in an invalid state for the requested operation."""

    def __init__(self, message: str) -> None:
        super().__init__(message)


class InvalidStatusTransitionError(NextActionDomainError):
    """Raised when a requested status transition is not allowed."""

    def __init__(self, from_status: str, to_status: str) -> None:
        super().__init__(f"Invalid status transition from '{from_status}' to '{to_status}'.")
        self.from_status = from_status
        self.to_status = to_status


class ReminderNotFoundError(NextActionDomainError):
    """Raised when a reminder cannot be found."""

    def __init__(self, reminder_id: uuid.UUID) -> None:
        super().__init__(f"Reminder with id '{reminder_id}' was not found.")
        self.reminder_id = reminder_id


class FollowUpNotFoundError(NextActionDomainError):
    """Raised when a follow-up cannot be found."""

    def __init__(self, follow_up_id: uuid.UUID) -> None:
        super().__init__(f"FollowUp with id '{follow_up_id}' was not found.")
        self.follow_up_id = follow_up_id


class UserNotFoundError(NextActionDomainError):
    """Raised when a user cannot be found."""

    def __init__(self, user_id: uuid.UUID) -> None:
        super().__init__(f"User with id '{user_id}' was not found.")
        self.user_id = user_id


class UserAlreadyExistsError(NextActionDomainError):
    """Raised when registering an email that is already in use."""

    def __init__(self, email: str) -> None:
        super().__init__(f"A user with email '{email}' already exists.")
        self.email = email


class InvalidCredentialsError(NextActionDomainError):
    """Raised on invalid email or password without revealing which was incorrect."""

    def __init__(self, message: str = "Invalid email or password.") -> None:
        super().__init__(message)


class InactiveUserError(NextActionDomainError):
    """Raised when an inactive user attempts authentication or access."""

    def __init__(self, message: str = "User account is inactive.") -> None:
        super().__init__(message)


class AuthenticationRequiredError(NextActionDomainError):
    """Raised when a protected endpoint is called without valid authentication."""

    def __init__(self) -> None:
        super().__init__("Authentication token is required.")


class InvalidTokenError(NextActionDomainError):
    """Raised when a JWT token is invalid, expired, or malformed."""

    def __init__(self, detail: str = "Invalid or expired authentication token.") -> None:
        super().__init__(detail)


class RefreshTokenExpiredError(InvalidTokenError):
    """Raised when a refresh token has expired."""

    def __init__(self) -> None:
        super().__init__("Refresh token has expired.")


class RefreshTokenRevokedError(InvalidTokenError):
    """Raised when a refresh token has already been revoked or reused (replay attack)."""

    def __init__(self, detail: str = "Refresh token has been revoked or replayed.") -> None:
        super().__init__(detail)


class RefreshTokenNotFoundError(InvalidTokenError):
    """Raised when a refresh token cannot be found in database."""

    def __init__(self) -> None:
        super().__init__("Invalid refresh token.")


class ClientNotFoundError(NextActionDomainError):
    """Raised when a client cannot be found."""

    def __init__(self, client_id: uuid.UUID) -> None:
        super().__init__(f"Client with id '{client_id}' was not found.")
        self.client_id = client_id


class WorkflowNotFoundError(NextActionDomainError):
    """Raised when a workflow cannot be found."""

    def __init__(self, workflow_id: uuid.UUID) -> None:
        super().__init__(f"Workflow with id '{workflow_id}' was not found.")
        self.workflow_id = workflow_id


class NotificationNotFoundError(NextActionDomainError):
    """Raised when a notification cannot be found or does not belong to the user."""

    def __init__(self, notification_id: uuid.UUID) -> None:
        super().__init__(f"Notification with id '{notification_id}' was not found.")
        self.notification_id = notification_id


class TaskTemplateNotFoundError(NextActionDomainError):
    """Raised when a task template cannot be found."""

    def __init__(self, template_id: uuid.UUID) -> None:
        super().__init__(f"TaskTemplate with id '{template_id}' was not found.")
        self.template_id = template_id


class RecurringTaskNotFoundError(NextActionDomainError):
    """Raised when a recurring task cannot be found."""

    def __init__(self, recurring_task_id: uuid.UUID) -> None:
        super().__init__(f"RecurringTask with id '{recurring_task_id}' was not found.")
        self.recurring_task_id = recurring_task_id


class UnauthorizedTemplateAccessError(NextActionDomainError):
    """Raised when a user attempts to modify or delete a template created by another user."""

    def __init__(self, template_id: uuid.UUID) -> None:
        super().__init__(f"You are not authorized to modify template '{template_id}'.")
        self.template_id = template_id


class UnauthorizedRecurringTaskAccessError(NextActionDomainError):
    """Raised when a user attempts to modify or delete a recurring task created by another user."""

    def __init__(self, recurring_task_id: uuid.UUID) -> None:
        super().__init__(f"You are not authorized to modify recurring task '{recurring_task_id}'.")
        self.recurring_task_id = recurring_task_id


class InvalidRecurrenceRuleError(NextActionDomainError):
    """Raised when recurrence rule configuration is invalid."""

    def __init__(self, message: str) -> None:
        super().__init__(message)



