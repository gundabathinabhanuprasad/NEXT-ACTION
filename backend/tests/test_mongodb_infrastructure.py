"""Tests for Phase 28 MongoDB infrastructure, connection scaffolding, and dual-engine coexistence."""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch
import uuid
import pytest
from fastapi.testclient import TestClient
from pymongo.errors import ConnectionFailure

from app.core.config import Settings, redact_mongo_uri, settings
from app.db.mongodb import (
    check_mongo_ready,
    close_mongo_client,
    get_mongo_client,
    get_mongo_database,
    get_mongo_session,
    init_mongo_client,
    init_mongo_indexes,
)
from app.main import app
from app.repositories.mongodb_base import BaseMongoRepository

client = TestClient(app)


def test_mongodb_disabled_by_default():
    """1. Verify MongoDB is disabled by default and PostgreSQL operates normally."""
    assert settings.MONGODB_ENABLED is False
    assert get_mongo_client() is None

    result = init_mongo_client()
    assert result is None


def test_app_starts_and_health_probes_without_mongodb():
    """2. Verify /health and /ready operate normally with MongoDB disabled."""
    health_res = client.get("/health")
    assert health_res.status_code == 200
    assert health_res.json() == {"status": "healthy", "database": "connected"}

    ready_res = client.get("/ready")
    assert ready_res.status_code == 200
    ready_data = ready_res.json()
    assert ready_data["status"] == "ready"
    assert ready_data["database"] == "connected"
    # When disabled, mongodb field is excluded or None
    assert ready_data.get("mongodb") is None


def test_redact_mongo_uri():
    """3. Verify credentials in MongoDB URIs are properly redacted."""
    standard_uri = "mongodb://admin:secretPassword123@localhost:27017/nextaction"
    redacted = redact_mongo_uri(standard_uri)
    assert "secretPassword123" not in redacted
    assert "admin:***@localhost:27017/nextaction" in redacted

    srv_uri = "mongodb+srv://atlas_user:P@ssword!@cluster0.abcde.mongodb.net/nextaction?retryWrites=true"
    redacted_srv = redact_mongo_uri(srv_uri)
    assert "P@ssword!" not in redacted_srv
    assert "atlas_user:***@cluster0.abcde.mongodb.net" in redacted_srv

    assert redact_mongo_uri(None) == ""
    assert redact_mongo_uri("") == ""


def test_validate_production_security_with_mongodb():
    """4. Verify production configuration validation enforces MONGODB_URI when enabled."""
    prod_settings = Settings(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="a_very_long_secure_production_secret_key_32_bytes!",
        POSTGRES_PASSWORD="secure_prod_password_123",
        MONGODB_ENABLED=True,
        MONGODB_URI=None,
    )
    with pytest.raises(ValueError, match="MONGODB_URI is not configured"):
        prod_settings.validate_production_security()


def test_init_mongo_client_missing_uri():
    """5. Verify init_mongo_client raises ValueError when enabled without URI."""
    with patch.object(settings, "MONGODB_ENABLED", True):
        with patch.object(settings, "MONGODB_URI", None):
            with pytest.raises(ValueError, match="MONGODB_URI is empty or not configured"):
                init_mongo_client()


def test_init_mongo_client_connection_failure():
    """6. Verify init_mongo_client handles connection failure without exposing credentials."""
    unreachable_uri = "mongodb://testuser:superSecretPassword@127.0.0.1:19999/nextaction"
    with patch.object(settings, "MONGODB_ENABLED", True):
        with patch.object(settings, "MONGODB_URI", unreachable_uri):
            with patch.object(settings, "MONGODB_SERVER_SELECTION_TIMEOUT_MS", 200):
                with patch.object(settings, "MONGODB_CONNECT_TIMEOUT_MS", 200):
                    with pytest.raises(ConnectionFailure) as exc_info:
                        init_mongo_client()
                    # Ensure secret is redacted in error message
                    assert "superSecretPassword" not in str(exc_info.value)
                    assert "testuser:***@" in str(exc_info.value)


def test_readiness_probe_with_mongodb_enabled_success():
    """7. Verify /ready reports both PostgreSQL and MongoDB when MongoDB is enabled and healthy."""
    with patch.object(settings, "MONGODB_ENABLED", True):
        with patch("app.main.check_mongo_ready", return_value=True):
            res = client.get("/ready")
            assert res.status_code == 200
            data = res.json()
            assert data["status"] == "ready"
            assert data["database"] == "connected"
            assert data["mongodb"] == "connected"


def test_readiness_probe_with_mongodb_enabled_failure():
    """8. Verify /ready returns HTTP 503 when MongoDB is enabled but unreachable."""
    with patch.object(settings, "MONGODB_ENABLED", True):
        with patch("app.main.check_mongo_ready", return_value=False):
            res = client.get("/ready")
            assert res.status_code == 503
            data = res.json()
            assert data["status"] == "not_ready"
            assert data["database"] == "connected"
            assert data["mongodb"] == "unavailable"


def test_base_repository_uuid_and_utc_helpers():
    """9. Verify BaseMongoRepository utility methods for UUID conversion and UTC normalization."""
    # UUID formatting
    u = uuid.uuid4()
    assert BaseMongoRepository.to_uuid_str(u) == str(u)
    assert BaseMongoRepository.to_uuid_str(str(u)) == str(u)
    assert BaseMongoRepository.to_uuid_str("custom-non-uuid-string") == "custom-non-uuid-string"

    # UTC datetime normalization
    naive_dt = datetime(2026, 9, 30, 10, 0, 0)
    utc_dt = BaseMongoRepository.ensure_utc(naive_dt)
    assert utc_dt.tzinfo == timezone.utc
    assert utc_dt.hour == 10

    already_utc = datetime(2026, 9, 30, 10, 0, 0, tzinfo=timezone.utc)
    assert BaseMongoRepository.ensure_utc(already_utc) == already_utc
    assert BaseMongoRepository.ensure_utc(None) is None


def test_base_repository_format_document():
    """10. Verify BaseMongoRepository format_document standardizes _id to string id."""
    raw_doc = {"_id": "test-uuid-1234", "name": "Task 1", "status": "pending"}
    formatted = BaseMongoRepository.format_document(raw_doc)
    assert formatted["id"] == "test-uuid-1234"
    assert formatted["_id"] == "test-uuid-1234"
    assert formatted["name"] == "Task 1"

    assert BaseMongoRepository.format_document(None) is None


def test_init_mongo_indexes_idempotency():
    """11. Verify init_mongo_indexes idempotency on mock database."""
    mock_db = MagicMock()
    mock_collection = MagicMock()
    mock_db.__getitem__.return_value = mock_collection

    # First call
    init_mongo_indexes(mock_db)
    mock_collection.create_index.assert_called_once_with(
        [("created_at", -1)],
        name="idx_infra_health_created_at",
    )

    # Second call should execute without raising exceptions
    init_mongo_indexes(mock_db)
    assert mock_collection.create_index.call_count == 2


def test_mongo_session_interface_and_lifecycle():
    """12. Verify get_mongo_session context manager interface and shutdown cleanup."""
    mock_client = MagicMock()
    mock_session = MagicMock()
    mock_client.start_session.return_value = mock_session

    with get_mongo_session(client=mock_client) as session:
        assert session == mock_session

    mock_session.end_session.assert_called_once()

    # Test error when client is uninitialized
    with patch("app.db.mongodb.get_mongo_client", return_value=None):
        with pytest.raises(RuntimeError, match="MongoDB client is not initialized"):
            with get_mongo_session(client=None):
                pass

    # Test clean close
    with patch("app.db.mongodb._mongo_client", mock_client):
        close_mongo_client()
        mock_client.close.assert_called_once()
        assert get_mongo_client() is None
