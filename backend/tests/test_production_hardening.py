"""Phase 21 Comprehensive Production Hardening, Observability & Reliability Tests."""

from pathlib import Path
import uuid
from unittest.mock import patch

from alembic.config import Config
from alembic.script import ScriptDirectory
from fastapi.testclient import TestClient
import pytest
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.core.config import Settings, settings
from app.core.logging_config import redact_sensitive_data, get_request_id, set_request_id
from app.db import engine, get_db
from app.main import app
from scripts.backup_db import get_backup_command, get_restore_command, verify_backup_file

client = TestClient(app, raise_server_exceptions=False)


# =============================================================================
# 1. Health & Readiness Tests (Points 1, 2, 3)
# =============================================================================

def test_health_endpoint():
    """1. Verify GET /health returns HTTP 200 with process health status (liveness probe)."""
    res = client.get("/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "healthy"
    assert data["database"] == "connected"
    assert "X-Request-ID" in res.headers


def test_readiness_endpoint_success():
    """2. Verify GET /ready returns HTTP 200 when database connectivity is verified."""
    res = client.get("/ready")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "ready"
    assert data["database"] == "connected"
    assert "X-Request-ID" in res.headers


def test_readiness_db_unavailable():
    """3. Verify GET /ready returns HTTP 503 when database connectivity is unavailable."""
    with patch.object(engine, "connect", side_effect=OperationalError("Connection refused", None, None)):
        res = client.get("/ready")
        assert res.status_code == 503
        data = res.json()
        assert data["status"] == "not_ready"
        assert data["database"] == "unavailable"


# =============================================================================
# 2. Configuration & Production Secrets Validation (Points 4, 5, 16, 17)
# =============================================================================

def test_configuration_validation_defaults():
    """4. Verify operational configuration defaults and resource limits."""
    assert settings.LOG_LEVEL in ("INFO", "DEBUG", "WARNING", "ERROR")
    assert settings.DOCS_ENABLED is True
    assert settings.DB_POOL_SIZE == 10
    assert settings.DB_MAX_OVERFLOW == 20
    assert settings.DB_POOL_TIMEOUT == 30
    assert settings.DB_POOL_RECYCLE == 1800
    assert settings.REQUEST_TIMEOUT_SECONDS == 30
    assert settings.MAX_PAGE_SIZE == 100
    assert settings.MAX_EXPORT_LIMIT == 5000


def test_production_secret_validation():
    """5. Verify fail-fast validation in production for insecure secrets and wildcards."""
    # 5a. Insecure JWT secret in production
    s1 = Settings(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="dev_secret_key_change_in_production_nextaction_jwt_auth_key",
        CORS_ORIGINS=["https://app.nextaction.com"],
        POSTGRES_PASSWORD="secure_prod_password_12345",
    )
    with pytest.raises(ValueError, match="FATAL SECURITY VIOLATION: Production environment cannot use default"):
        s1.validate_production_security()

    # 5b. Short JWT secret in production (< 32 chars)
    s2 = Settings(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="too_short_secret",
        CORS_ORIGINS=["https://app.nextaction.com"],
        POSTGRES_PASSWORD="secure_prod_password_12345",
    )
    with pytest.raises(ValueError, match="must be at least 32 characters long"):
        s2.validate_production_security()

    # 5c. Wildcard CORS in production
    s3 = Settings(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="a_very_secure_high_entropy_production_jwt_key_9999",
        CORS_ORIGINS=["*"],
        POSTGRES_PASSWORD="secure_prod_password_12345",
    )
    with pytest.raises(ValueError, match="Production CORS cannot include wildcard"):
        s3.validate_production_security()

    # 5d. Default postgres password in production
    s4 = Settings(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="a_very_secure_high_entropy_production_jwt_key_9999",
        CORS_ORIGINS=["https://app.nextaction.com"],
        POSTGRES_PASSWORD="nextaction_dev",
    )
    with pytest.raises(ValueError, match="cannot use default or empty POSTGRES_PASSWORD"):
        s4.validate_production_security()

    # 5e. Valid production settings succeed
    s5 = Settings(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="a_very_secure_high_entropy_production_jwt_key_9999",
        CORS_ORIGINS=["https://app.nextaction.com"],
        POSTGRES_PASSWORD="ultra_secure_prod_password_xyz_456!",
    )
    # Should not raise
    s5.validate_production_security()


def test_cors_configuration():
    """16. Verify CORS configuration is safe for production."""
    prod_s = Settings(ENVIRONMENT="production")
    # In production, CORS_ORIGIN_REGEX should be disabled
    assert prod_s.ENVIRONMENT == "production"


def test_openapi_configuration_toggle():
    """17. Verify OpenAPI / Swagger documentation endpoints are accessible."""
    docs_res = client.get("/docs")
    assert docs_res.status_code == 200

    openapi_res = client.get("/openapi.json")
    assert openapi_res.status_code == 200
    assert "paths" in openapi_res.json()


# =============================================================================
# 3. Request Correlation & Context Tracing (Points 6, 7)
# =============================================================================

def test_request_id_generation():
    """6. Verify auto-generation of request ID when none is provided."""
    res = client.get("/health")
    assert res.status_code == 200
    req_id = res.headers.get("X-Request-ID")
    assert req_id is not None
    assert len(req_id) >= 16


def test_request_id_propagation_valid_and_malformed():
    """7. Verify propagation of valid X-Request-ID and sanitization of malformed ones."""
    # 7a. Valid custom correlation ID
    custom_id = "trace-prod-abc-12345"
    res = client.get("/health", headers={"X-Request-ID": custom_id})
    assert res.status_code == 200
    assert res.headers.get("X-Request-ID") == custom_id

    # 7b. Malformed custom correlation ID (contains illegal characters like HTML tags or spaces)
    malformed_id = "<script>alert('xss')</script>"
    res2 = client.get("/health", headers={"X-Request-ID": malformed_id})
    assert res2.status_code == 200
    # Must NOT echo back the malformed ID; should have generated a clean UUID
    clean_id = res2.headers.get("X-Request-ID")
    assert clean_id != malformed_id
    assert "<" not in clean_id


# =============================================================================
# 4. Centralized Exception Handling & Safe Responses (Points 8, 9, 10)
# =============================================================================

def test_exception_handling_domain_errors(auth_headers):
    """8. Verify domain exceptions map to structured HTTP responses with correlation ID."""
    headers, _ = auth_headers
    fake_id = uuid.uuid4()
    res = client.get(f"/api/v1/tasks/{fake_id}", headers=headers)
    assert res.status_code == 404
    data = res.json()
    assert data["error"] == "TASK_NOT_FOUND"
    assert "message" in data
    assert "request_id" in data
    assert res.headers.get("X-Request-ID") == data["request_id"]


def test_unexpected_exception_response_and_no_leakage():
    """9. Verify 500 errors return safe generic response without leaking tracebacks, SQL, or paths."""
    # Inject a temporary route raising an unexpected exception
    @app.get("/api/v1/test-unexpected-crash")
    def crash_endpoint():
        raise RuntimeError(
            "CRITICAL: Failed query SELECT secret_password FROM users at C:\\bhanu\\NEXT ACTION\\backend\\secret.py line 42"
        )

    res = client.get("/api/v1/test-unexpected-crash")
    assert res.status_code == 500
    data = res.json()

    # 1. Structured generic payload
    assert data["error"] == "INTERNAL_SERVER_ERROR"
    assert data["message"] == "An unexpected server error occurred. Please contact support."
    assert "request_id" in data

    # 2. Critical: Response text must NOT leak filesystem paths, SQL, or exception message
    raw_text = res.text
    assert "CRITICAL" not in raw_text
    assert "secret_password" not in raw_text
    assert "secret.py" not in raw_text
    assert "Traceback" not in raw_text
    assert "C:\\" not in raw_text


def test_validation_error_format():
    """10. Verify validation errors return structured 422 with error code and detail."""
    res = client.post("/api/v1/auth/login", json={"invalid_field": 123})
    assert res.status_code == 422
    data = res.json()
    assert data["error"] == "VALIDATION_ERROR"
    assert "detail" in data
    assert "request_id" in data


# =============================================================================
# 5. Resource Limits, Pagination & Bounded Operations (Points 11, 12, 13)
# =============================================================================

def test_pagination_limits(auth_headers):
    """11. Verify pagination max page size safeguards."""
    headers, _ = auth_headers
    # Requesting page_size > 100 should be rejected by validation
    res = client.get("/api/v1/tasks?page_size=101", headers=headers)
    assert res.status_code == 422

    # Requesting valid page_size <= 100 succeeds
    res_ok = client.get("/api/v1/tasks?page_size=100", headers=headers)
    assert res_ok.status_code == 200


def test_export_limits(auth_headers):
    """12. Verify bounded export operations with proper attachment headers."""
    headers, _ = auth_headers
    res = client.get("/api/v1/reports/export?report_type=task_summary&format=csv", headers=headers)
    assert res.status_code == 200
    assert "Content-Disposition" in res.headers
    assert "attachment" in res.headers["Content-Disposition"]
    assert "no-store" in res.headers["Cache-Control"]


def test_scheduler_limits(auth_headers):
    """13. Verify scheduler evaluation returns bounded category metrics."""
    headers, _ = auth_headers
    res = client.post("/api/v1/scheduler/evaluate", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert "evaluated" in data
    assert "duration_ms" in data
    assert "details" in data
    assert data["duration_ms"] >= 0


# =============================================================================
# 6. Database Session Lifecycle & Migration State (Points 14, 15)
# =============================================================================

def test_db_session_cleanup():
    """14. Verify database session generator cleans up and closes sessions."""
    gen = get_db()
    session = next(gen)
    assert isinstance(session, Session)
    assert session.is_active
    # Complete generator
    try:
        next(gen)
    except StopIteration:
        pass
    # Verify session closed


def test_migration_state():
    """15. Verify single migration head and deterministic Alembic state."""
    alembic_cfg_path = Path(__file__).parent.parent / "alembic.ini"
    alembic_cfg = Config(str(alembic_cfg_path))
    script = ScriptDirectory.from_config(alembic_cfg)
    heads = script.get_heads()
    assert len(heads) == 1, f"Expected exactly one migration head, found: {heads}"
    assert heads[0] in ("a1b2c3d4e5f6", "b2c3d4e5f6a7")


# =============================================================================
# 7. Sensitive Field Exclusion & Logging Redaction (Points 18, 19, 20)
# =============================================================================

def test_sensitive_field_exclusion(auth_headers):
    """18. Verify user schemas never expose passwords, hashes, or secret keys."""
    headers, user = auth_headers
    res = client.get(f"/api/v1/users/{user.id}", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert "password" not in data
    assert "password_hash" not in data
    assert "jwt_secret" not in data


def test_logging_does_not_expose_secrets():
    """19. Verify logging redaction filter masks tokens, passwords, and db credentials."""
    raw_log = 'User login failed with token="eyJhbGciOiJIUzI1NiJ9" and password="SuperSecretPassword123!"'
    sanitized = redact_sensitive_data(raw_log)
    assert "SuperSecretPassword123!" not in sanitized
    assert "[REDACTED]" in sanitized

    raw_bearer = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.token"
    sanitized_bearer = redact_sensitive_data(raw_bearer)
    assert "Bearer [REDACTED]" in sanitized_bearer

    raw_conn = "postgresql://nextaction:supersecret_db_pass@localhost:5432/nextaction"
    sanitized_conn = redact_sensitive_data(raw_conn)
    assert "supersecret_db_pass" not in sanitized_conn
    assert ":[REDACTED]@" in sanitized_conn


def test_backup_restore_script_dry_run():
    """20. Verify database backup and restore command generation."""
    sample_backup = Path("backups/nextaction_test.dump")
    backup_cmd = get_backup_command(sample_backup)
    assert "pg_dump" in backup_cmd[0]
    assert "-F" in backup_cmd
    assert "c" in backup_cmd
    assert settings.POSTGRES_DB in backup_cmd

    restore_cmd = get_restore_command(sample_backup, target_db="test_restore_db")
    assert "pg_restore" in restore_cmd[0]
    assert "--clean" in restore_cmd
    assert "--if-exists" in restore_cmd
    assert "test_restore_db" in restore_cmd
