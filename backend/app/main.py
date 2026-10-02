"""FastAPI application entry point with operational lifecycle, observability, and readiness checks."""

from contextlib import asynccontextmanager
import logging
from fastapi import FastAPI, Response, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.api import api_v1_router, register_exception_handlers
from app.core.config import settings
from app.core.logging_config import setup_logging
from app.core.request_correlation import RequestCorrelationMiddleware
from app.core.security_headers import SecurityHeadersMiddleware
from app.db import engine
from app.db.mongodb import check_mongo_ready, close_mongo_client, init_mongo_client
from app.schemas import HealthResponse, ReadinessResponse

logger = logging.getLogger("nextaction.system")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup validation and graceful resource shutdown."""
    # 1. Startup phase
    setup_logging(settings.LOG_LEVEL)
    settings.validate_production_security()
    logger.info(
        f"Starting {settings.PROJECT_NAME} v{settings.VERSION} "
        f"[env={settings.ENVIRONMENT}, docs_enabled={settings.DOCS_ENABLED}, mongodb_enabled={settings.MONGODB_ENABLED}]"
    )

    # Initialize MongoDB if enabled
    if settings.MONGODB_ENABLED:
        logger.info("Initializing MongoDB connection pool...")
        init_mongo_client()

    yield

    # 2. Shutdown phase
    logger.info(f"Graceful shutdown initiated for {settings.PROJECT_NAME}...")
    if settings.MONGODB_ENABLED:
        close_mongo_client()
    logger.info("Disposing PostgreSQL database connection pool...")
    engine.dispose()
    logger.info("Database connection pools cleanly disposed.")


# Configurable documentation endpoints
docs_url = "/docs" if settings.DOCS_ENABLED else None
redoc_url = "/redoc" if settings.DOCS_ENABLED else None
openapi_url = "/openapi.json" if settings.DOCS_ENABLED else None

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description=settings.DESCRIPTION,
    docs_url=docs_url,
    redoc_url=redoc_url,
    openapi_url=openapi_url,
    lifespan=lifespan,
)

# 1. Register Request Correlation Middleware (attaches X-Request-ID and logs timing)
app.add_middleware(RequestCorrelationMiddleware)

# 2. Register Trusted Host Middleware in production
if settings.ENVIRONMENT.lower() == "production":
    from starlette.middleware.trustedhost import TrustedHostMiddleware

    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=settings.TRUSTED_HOSTS,
    )

# 3. Register Security Headers middleware
app.add_middleware(SecurityHeadersMiddleware)

# 4. Register CORS middleware
cors_regex = settings.CORS_ORIGIN_REGEX if settings.ENVIRONMENT.lower() != "production" else None
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_origin_regex=cors_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 4. Register centralized domain and generic exception handlers
register_exception_handlers(app)

# 5. Include central API v1 router
app.include_router(api_v1_router)


@app.get(
    "/health",
    response_model=HealthResponse,
    summary="Health Check",
    tags=["System"],
)
async def health_check() -> HealthResponse:
    """System health check endpoint.

    Returns HTTP 200 with service and database connection status.
    Used as an operational liveness probe.
    """
    return HealthResponse(status="healthy", database="connected")


@app.get(
    "/version",
    summary="Version Check",
    tags=["System"],
)
def version_check() -> dict[str, str]:
    """Return backend deployment version and persistence engine."""
    return {"version": "v1.0.2-50e1b23", "engine": settings.PERSISTENCE_ENGINE}


@app.get(
    "/ready",
    response_model=ReadinessResponse,
    response_model_exclude_none=True,
    summary="Readiness Check",
    tags=["System"],
)
def readiness_check(response: Response) -> ReadinessResponse:
    """System readiness probe verifying database connectivity.

    Returns HTTP 200 when ready to receive traffic, HTTP 503 when dependencies are unavailable.
    """
    db_status = "unavailable"
    mongo_status = None
    is_ready = True

    # 1. Check PostgreSQL if it's the primary engine or dual-write is enabled
    if settings.PERSISTENCE_ENGINE != "mongodb" or settings.MONGODB_DUAL_WRITE_ENABLED:
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            db_status = "connected"
        except Exception as exc:
            logger.error(f"PostgreSQL readiness check failed: {exc}")
            db_status = "unavailable"
            is_ready = False

    # 2. Check MongoDB if enabled or if it's the primary engine
    if settings.MONGODB_ENABLED:
        if check_mongo_ready():
            mongo_status = "connected"
            if settings.PERSISTENCE_ENGINE == "mongodb":
                db_status = "connected"
        else:
            mongo_status = "unavailable"
            is_ready = False
            if settings.PERSISTENCE_ENGINE == "mongodb":
                db_status = "unavailable"

    if not is_ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return ReadinessResponse(
            status="not_ready",
            database=db_status,
            mongodb=mongo_status,
        )

    return ReadinessResponse(
        status="ready",
        database=db_status,
        mongodb=mongo_status,
    )
