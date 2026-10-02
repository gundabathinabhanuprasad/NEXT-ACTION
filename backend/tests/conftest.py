"""Pytest shared fixtures for backend test suites."""

import uuid
import pytest
from fastapi.testclient import TestClient
from app.core.config import settings
from app.core.rate_limit import limiter
from app.db import SessionLocal
from app.main import app
from app.services.auth_service import register_user

_test_client = TestClient(app)


@pytest.fixture(autouse=True)
def configure_test_environment(monkeypatch):
    """Ensure tests run under 'test' environment and default PostgreSQL baseline."""
    monkeypatch.setenv("PERSISTENCE_ENGINE", "postgresql")
    monkeypatch.setenv("MONGODB_ENABLED", "false")

    orig_env = settings.ENVIRONMENT
    orig_engine = settings.PERSISTENCE_ENGINE
    orig_mongo = settings.MONGODB_ENABLED

    settings.ENVIRONMENT = "test"
    settings.PERSISTENCE_ENGINE = "postgresql"
    settings.MONGODB_ENABLED = False
    limiter.reset()
    yield
    settings.ENVIRONMENT = orig_env
    settings.PERSISTENCE_ENGINE = orig_engine
    settings.MONGODB_ENABLED = orig_mongo
    limiter.reset()


@pytest.fixture
def client():
    """Provide a TestClient instance."""
    return _test_client


@pytest.fixture
def db():
    """Provide a clean database session for direct inspection and operations."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture
def test_user(db):
    """Create a sample authenticated user and return credentials."""
    email = f"scheduling_user_{uuid.uuid4().hex[:8]}@example.com"
    password = "TestPassword123!"
    user = register_user(db=db, name="Scheduling Test Operator", email=email, password=password)
    return user, email, password


@pytest.fixture
def auth_headers(test_user, client):
    """Provide valid Authorization headers for the authenticated user."""
    user, email, password = test_user
    login_resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert login_resp.status_code == 200
    token = login_resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}, user
