"""Centralized structured logging and sensitive data redaction for NextAction."""

from contextvars import ContextVar
from datetime import datetime, timezone
import logging
import re
import sys
from typing import Any, Optional

# Context variable holding the correlation ID for the active async execution context
request_id_ctx: ContextVar[str] = ContextVar("request_id_ctx", default="")


def get_request_id() -> str:
    """Retrieve the current request correlation ID, or empty string if unset."""
    return request_id_ctx.get()


def set_request_id(request_id: str) -> None:
    """Set the request correlation ID for the current execution context."""
    request_id_ctx.set(request_id)


# Regex patterns matching sensitive information that must NEVER appear in server logs
SENSITIVE_PATTERNS = [
    (re.compile(r"(Bearer\s+)[A-Za-z0-9\-._~+/]+=*", re.IGNORECASE), r"\1[REDACTED]"),
    (re.compile(r'("?(?:password|password_hash|secret|jwt_secret|token)"?\s*[:=]\s*)"[^"]*"', re.IGNORECASE), r'\1"[REDACTED]"'),
    (re.compile(r'("?(?:password|password_hash|secret|jwt_secret|token)"?\s*[:=]\s*)[^\s,}\]]+', re.IGNORECASE), r'\1[REDACTED]'),
    (re.compile(r"://([^:]+):([^@]+)@", re.IGNORECASE), r"://\1:[REDACTED]@"),
]


def redact_sensitive_data(text: str) -> str:
    """Sanitize string messages by redacting credentials, tokens, and secrets."""
    if not isinstance(text, str):
        return text
    for pattern, replacement in SENSITIVE_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


class SensitiveDataFilter(logging.Filter):
    """Logging filter that attaches request_id and redacts sensitive parameters."""

    def filter(self, record: logging.LogRecord) -> bool:
        # Attach request_id attribute to the log record
        req_id = get_request_id()
        record.request_id = req_id if req_id else "-"

        # Redact sensitive content from the log message
        if isinstance(record.msg, str):
            record.msg = redact_sensitive_data(record.msg)

        # Redact arguments if provided
        if record.args:
            if isinstance(record.args, dict):
                record.args = {k: redact_sensitive_data(str(v)) for k, v in record.args.items()}
            elif isinstance(record.args, (list, tuple)):
                record.args = tuple(
                    redact_sensitive_data(str(a)) if isinstance(a, str) else a
                    for a in record.args
                )

        return True


class StructuredFormatter(logging.Formatter):
    """Formatter producing structured logs with UTC ISO8601 timestamps and correlation IDs."""

    def formatTime(self, record: logging.LogRecord, datefmt: Optional[str] = None) -> str:
        dt = datetime.fromtimestamp(record.created, tz=timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


_logging_initialized = False


def setup_logging(log_level: str = "INFO") -> None:
    """Initialize centralized structured logging across the application."""
    global _logging_initialized
    if _logging_initialized:
        return

    level = getattr(logging, log_level.upper(), logging.INFO)

    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    # Avoid duplicate handlers if reloaded
    root_logger.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)

    filter_ = SensitiveDataFilter()
    handler.addFilter(filter_)

    formatter = StructuredFormatter(
        fmt="%(asctime)s [%(levelname)s] [%(name)s] [req_id=%(request_id)s] %(message)s"
    )
    handler.setFormatter(formatter)

    root_logger.addHandler(handler)

    # Suppress verbose loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)

    _logging_initialized = True
