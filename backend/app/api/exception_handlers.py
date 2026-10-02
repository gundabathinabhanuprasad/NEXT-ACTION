"""Centralized exception handling mapping domain errors to standard HTTP responses."""

import logging
from typing import Any, Type
from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging_config import get_request_id

from app.services.exceptions import (
    AuthenticationRequiredError,
    ClientNotFoundError,
    FollowUpNotFoundError,
    InactiveUserError,
    InvalidCredentialsError,
    InvalidStatusTransitionError,
    InvalidTaskDateError,
    InvalidTaskStateError,
    InvalidTokenError,
    RefreshTokenExpiredError,
    RefreshTokenNotFoundError,
    RefreshTokenRevokedError,
    MaxAttemptsReachedError,
    NextActionDomainError,
    NotificationNotFoundError,
    OverrideReasonRequiredError,
    PostponementReasonRequiredError,
    ReminderNotFoundError,
    ReopenReasonRequiredError,
    TaskAlreadyCompletedError,
    TaskCancelledError,
    TaskCompletedError,
    TaskNotCompletedError,
    TaskNotFoundError,
    TaskTemplateNotFoundError,
    RecurringTaskNotFoundError,
    UnauthorizedTemplateAccessError,
    UnauthorizedRecurringTaskAccessError,
    InvalidRecurrenceRuleError,
    UserAlreadyExistsError,
    UserNotFoundError,
    WorkflowNotFoundError,
)

logger = logging.getLogger("nextaction.exceptions")

EXCEPTION_MAPPING: dict[Type[NextActionDomainError], tuple[int, str]] = {
    TaskNotFoundError: (404, "TASK_NOT_FOUND"),
    TaskTemplateNotFoundError: (404, "TASK_TEMPLATE_NOT_FOUND"),
    RecurringTaskNotFoundError: (404, "RECURRING_TASK_NOT_FOUND"),
    UnauthorizedTemplateAccessError: (403, "UNAUTHORIZED_TEMPLATE_ACCESS"),
    UnauthorizedRecurringTaskAccessError: (403, "UNAUTHORIZED_RECURRING_TASK_ACCESS"),
    InvalidRecurrenceRuleError: (400, "INVALID_RECURRENCE_RULE"),
    ClientNotFoundError: (404, "CLIENT_NOT_FOUND"),
    WorkflowNotFoundError: (404, "WORKFLOW_NOT_FOUND"),
    NotificationNotFoundError: (404, "NOTIFICATION_NOT_FOUND"),
    ReminderNotFoundError: (404, "REMINDER_NOT_FOUND"),
    FollowUpNotFoundError: (404, "FOLLOW_UP_NOT_FOUND"),
    UserNotFoundError: (404, "USER_NOT_FOUND"),
    UserAlreadyExistsError: (409, "USER_ALREADY_EXISTS"),
    InvalidCredentialsError: (401, "INVALID_CREDENTIALS"),
    InactiveUserError: (401, "INACTIVE_USER"),
    AuthenticationRequiredError: (401, "AUTHENTICATION_REQUIRED"),
    InvalidTokenError: (401, "INVALID_TOKEN"),
    RefreshTokenExpiredError: (401, "REFRESH_TOKEN_EXPIRED"),
    RefreshTokenRevokedError: (401, "REFRESH_TOKEN_REVOKED"),
    RefreshTokenNotFoundError: (401, "INVALID_TOKEN"),
    TaskAlreadyCompletedError: (409, "TASK_ALREADY_COMPLETED"),
    TaskCompletedError: (409, "TASK_COMPLETED"),
    TaskCancelledError: (409, "TASK_CANCELLED"),
    TaskNotCompletedError: (409, "TASK_NOT_COMPLETED"),
    MaxAttemptsReachedError: (409, "MAX_ATTEMPTS_REACHED"),
    OverrideReasonRequiredError: (400, "OVERRIDE_REASON_REQUIRED"),
    PostponementReasonRequiredError: (400, "POSTPONEMENT_REASON_REQUIRED"),
    ReopenReasonRequiredError: (400, "REOPEN_REASON_REQUIRED"),
    InvalidTaskDateError: (400, "INVALID_TASK_DATE"),
    InvalidTaskStateError: (409, "INVALID_TASK_STATE"),
    InvalidStatusTransitionError: (409, "INVALID_STATUS_TRANSITION"),
}


def _http_status_to_error_code(status_code: int) -> str:

    """Map HTTP status codes to standardized error codes."""
    mapping = {
        400: "BAD_REQUEST",
        401: "AUTHENTICATION_REQUIRED",
        403: "FORBIDDEN",
        404: "NOT_FOUND",
        405: "METHOD_NOT_ALLOWED",
        409: "CONFLICT",
        422: "VALIDATION_ERROR",
        429: "RATE_LIMIT_EXCEEDED",
        500: "INTERNAL_SERVER_ERROR",
        503: "SERVICE_UNAVAILABLE",
    }
    return mapping.get(status_code, f"HTTP_{status_code}")


def register_exception_handlers(app: FastAPI) -> None:
    """Register domain and global exception handlers on the FastAPI application."""

    @app.exception_handler(NextActionDomainError)
    async def domain_exception_handler(request: Request, exc: NextActionDomainError) -> JSONResponse:
        status_code, error_code = EXCEPTION_MAPPING.get(type(exc), (400, "DOMAIN_ERROR"))
        req_id = getattr(request.state, "request_id", "") or get_request_id()
        headers = {"X-Request-ID": req_id} if req_id else {}
        return JSONResponse(
            status_code=status_code,
            content={
                "error": error_code,
                "message": exc.message,
                "request_id": req_id,
            },
            headers=headers,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
        req_id = getattr(request.state, "request_id", "") or get_request_id()
        headers = {"X-Request-ID": req_id} if req_id else {}
        return JSONResponse(
            status_code=422,
            content={
                "error": "VALIDATION_ERROR",
                "message": "Invalid request parameters.",
                "detail": jsonable_encoder(exc.errors()),
                "request_id": req_id,
            },
            headers=headers,
        )

    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        req_id = getattr(request.state, "request_id", "") or get_request_id()
        headers = {"X-Request-ID": req_id} if req_id else {}
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": _http_status_to_error_code(exc.status_code),
                "message": str(exc.detail),
                "detail": jsonable_encoder(exc.detail),
                "request_id": req_id,
            },
            headers=headers,
        )


    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        req_id = getattr(request.state, "request_id", "") or get_request_id()
        headers = {"X-Request-ID": req_id} if req_id else {}
        # Detailed traceback is logged to server logs; NEVER exposed to the client
        logger.exception(
            f"Unhandled server exception on {request.method} {request.url.path} [req_id={req_id}]: {exc}"
        )
        return JSONResponse(
            status_code=500,
            content={
                "error": "INTERNAL_SERVER_ERROR",
                "message": "An unexpected server error occurred. Please contact support.",
                "request_id": req_id,
            },
            headers=headers,
        )

