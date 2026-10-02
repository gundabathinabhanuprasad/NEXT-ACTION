"""Request correlation ID middleware for request tracing and observability."""

import logging
import re
import time
import uuid
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.core.logging_config import set_request_id, request_id_ctx

logger = logging.getLogger("nextaction.access")

# Allowed request ID format: safe ASCII alphanumeric, hyphen, underscore; 8 to 64 chars
REQUEST_ID_REGEX = re.compile(r"^[a-zA-Z0-9_\-]{8,64}$")


class RequestCorrelationMiddleware(BaseHTTPMiddleware):
    """Middleware that assigns or propagates a correlation ID and records HTTP access metrics."""

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        incoming_id = request.headers.get("X-Request-ID", "").strip()

        if incoming_id and REQUEST_ID_REGEX.match(incoming_id):
            request_id = incoming_id
        else:
            request_id = str(uuid.uuid4())

        # Set into context variable and request state
        token = request_id_ctx.set(request_id)
        request.state.request_id = request_id

        start_time = time.perf_counter()
        status_code = 500

        try:
            response = await call_next(request)
            status_code = response.status_code
            response.headers["X-Request-ID"] = request_id
            return response
        except Exception as exc:
            # Let exception propagate to FastAPI's exception handlers
            duration_ms = (time.perf_counter() - start_time) * 1000.0
            logger.error(
                f"HTTP {request.method} {request.url.path} failed after {duration_ms:.2f}ms: {exc}"
            )
            raise
        finally:
            duration_ms = (time.perf_counter() - start_time) * 1000.0
            # Log structured access line
            logger.info(
                f"HTTP {request.method} {request.url.path} completed with {status_code} in {duration_ms:.2f}ms"
            )
            request_id_ctx.reset(token)
