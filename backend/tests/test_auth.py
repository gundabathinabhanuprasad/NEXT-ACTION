"""Comprehensive authentication and authorization test suite for NextAction.

Executes against live PostgreSQL database.
"""

from datetime import timedelta
import uuid
from fastapi.testclient import TestClient
import pytest
from app.core.security import create_access_token, get_password_hash, verify_password
from app.db import SessionLocal
from app.main import app
from app.models import Task, TaskHistory, User
from app.services.auth_service import register_user

client = TestClient(app)


@pytest.fixture
def db():
    """Provide a database session for direct inspection."""
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture
def registered_user(db):
    """Create and return a registered user with known credentials."""
    email = f"auth_test_{uuid.uuid4().hex[:8]}@example.com"
    password = "StrongPassword123!"
    user = register_user(db=db, name="Auth User", email=email, password=password)
    return user, email, password


@pytest.fixture
def auth_headers(registered_user):
    """Provide valid Authorization headers for the registered user."""
    user, email, password = registered_user
    login_resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert login_resp.status_code == 200
    token = login_resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}, user


# =========================================================================
# A & B: User Registration & Duplicate Email Rejection
# =========================================================================
def test_user_registration_and_duplicate_rejection():
    """Verify user registration returns 201 with safe fields, and rejects duplicate email with 409."""
    email = f"reg_{uuid.uuid4().hex[:8]}@example.com"
    password = "SecurePassword456!"

    # 1. Valid registration
    resp = client.post(
        "/api/v1/auth/register",
        json={"name": "New Registrant", "email": email, "password": password},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["name"] == "New Registrant"
    assert data["email"] == email.lower()
    assert data["is_active"] is True
    assert "password" not in data
    assert "password_hash" not in data

    # 2. Duplicate registration with same email (case insensitive)
    dup_resp = client.post(
        "/api/v1/auth/register",
        json={"name": "Duplicate Registrant", "email": email.upper(), "password": "OtherPassword789!"},
    )
    assert dup_resp.status_code == 409
    assert dup_resp.json()["error"] == "USER_ALREADY_EXISTS"


# =========================================================================
# C & D: Login & Invalid Login
# =========================================================================
def test_login_success_and_invalid_credentials(registered_user):
    """Verify login issues JWT on valid credentials and returns generic 401 on failure."""
    user, email, password = registered_user

    # Valid login
    resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert resp.status_code == 200
    token_data = resp.json()
    assert "access_token" in token_data
    assert token_data["token_type"] == "bearer"
    assert token_data["expires_in"] > 0

    # Wrong password
    bad_pw_resp = client.post("/api/v1/auth/login", json={"email": email, "password": "WrongPassword!"})
    assert bad_pw_resp.status_code == 401
    assert bad_pw_resp.json()["error"] == "INVALID_CREDENTIALS"

    # Non-existent email
    bad_email_resp = client.post("/api/v1/auth/login", json={"email": "nonexistent@example.com", "password": password})
    assert bad_email_resp.status_code == 401
    assert bad_email_resp.json()["error"] == "INVALID_CREDENTIALS"


# =========================================================================
# E, F, G, H, I: /auth/me & Token Validation
# =========================================================================
def test_auth_me_and_token_validation(registered_user, db):
    """Verify /auth/me endpoint with valid, missing, malformed, expired, and inactive user tokens."""
    user, email, password = registered_user

    # Valid token
    login_resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    token = login_resp.json()["access_token"]
    me_resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me_resp.status_code == 200
    assert me_resp.json()["id"] == str(user.id)
    assert me_resp.json()["email"] == email

    # Missing token
    no_tok_resp = client.get("/api/v1/auth/me")
    assert no_tok_resp.status_code == 401
    assert no_tok_resp.json()["error"] == "AUTHENTICATION_REQUIRED"

    # Malformed token
    malformed_resp = client.get("/api/v1/auth/me", headers={"Authorization": "Bearer not.a.valid.jwt"})
    assert malformed_resp.status_code == 401
    assert malformed_resp.json()["error"] == "INVALID_TOKEN"

    # Expired token
    expired_token, _ = create_access_token(subject=str(user.id), expires_delta=timedelta(seconds=-10))
    exp_resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {expired_token}"})
    assert exp_resp.status_code == 401
    assert exp_resp.json()["error"] == "INVALID_TOKEN"

    # Inactive user token
    inactive_user = register_user(
        db=db,
        name="Inactive Account",
        email=f"inactive_{uuid.uuid4().hex[:8]}@example.com",
        password="Password123!",
    )
    inactive_user.is_active = False
    db.commit()

    inact_token, _ = create_access_token(subject=str(inactive_user.id))
    inact_resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {inact_token}"})
    assert inact_resp.status_code == 401
    assert inact_resp.json()["error"] == "INACTIVE_USER"


# =========================================================================
# J, K, L: Protected APIs Require Authentication
# =========================================================================
def test_protected_apis_require_authentication(auth_headers):
    """Verify tasks, reminders, and follow-ups reject unauthenticated requests with 401."""
    headers, user = auth_headers

    # Tasks endpoint
    unauth_tasks = client.get("/api/v1/tasks")
    assert unauth_tasks.status_code == 401
    auth_tasks = client.get("/api/v1/tasks", headers=headers)
    assert auth_tasks.status_code == 200

    # Reminders endpoint
    unauth_rem = client.get("/api/v1/reminders/due")
    assert unauth_rem.status_code == 401
    auth_rem = client.get("/api/v1/reminders/due", headers=headers)
    assert auth_rem.status_code == 200

    # Follow-ups endpoint (missing follow-up with auth -> 404, without auth -> 401)
    random_id = str(uuid.uuid4())
    unauth_fu = client.get(f"/api/v1/follow-ups/{random_id}")
    assert unauth_fu.status_code == 401
    auth_fu = client.get(f"/api/v1/follow-ups/{random_id}", headers=headers)
    assert auth_fu.status_code == 404


# =========================================================================
# M: User Identity Security & Spoofing Prevention
# =========================================================================
def test_actor_identity_derived_from_jwt_not_request_body(db, auth_headers):
    """Verify the acting user is securely derived from the JWT and client-supplied user_id is ignored."""
    headers_a, user_a = auth_headers

    # Create User B
    user_b = register_user(
        db=db,
        name="User B",
        email=f"user_b_{uuid.uuid4().hex[:8]}@example.com",
        password="Password123!",
    )

    # User A creates task while attempting to spoof created_by_user_id as User B
    create_payload = {
        "title": "Security Identity Task",
        "created_by_user_id": str(user_b.id),  # Spoof attempt
    }
    create_resp = client.post("/api/v1/tasks", json=create_payload, headers=headers_a)
    assert create_resp.status_code == 201
    task_id = create_resp.json()["id"]

    # Verify history actor is User A, NOT User B
    hist_resp = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers_a)
    assert hist_resp.status_code == 200
    created_hist = hist_resp.json()[0]
    assert created_hist["created_by_user_id"] == str(user_a.id)
    assert created_hist["created_by_user_id"] != str(user_b.id)

    # User A records attempt while attempting to pass User B in body
    attempt_resp = client.post(
        f"/api/v1/tasks/{task_id}/attempt",
        json={"user_id": str(user_b.id), "notes": "Attempt spoof check"},
        headers=headers_a,
    )
    assert attempt_resp.status_code == 200

    # Verify attempt history actor is User A
    hist_resp2 = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers_a)
    attempt_hist = hist_resp2.json()[1]
    assert attempt_hist["created_by_user_id"] == str(user_a.id)
    assert attempt_hist["created_by_user_id"] != str(user_b.id)


# =========================================================================
# N: Assignment Security
# =========================================================================
def test_assignment_security(db, auth_headers):
    """Verify assignment sets target assignee from payload, but assigner actor is JWT user."""
    headers_a, user_a = auth_headers
    user_b = register_user(
        db=db,
        name="Assignee User B",
        email=f"assignee_b_{uuid.uuid4().hex[:8]}@example.com",
        password="Password123!",
    )

    # Create task
    task_resp = client.post("/api/v1/tasks", json={"title": "Assignment Security Task"}, headers=headers_a)
    task_id = task_resp.json()["id"]

    # User A assigns task to User B
    assign_resp = client.post(
        f"/api/v1/tasks/{task_id}/assign",
        json={"assigned_user_id": str(user_b.id)},
        headers=headers_a,
    )
    assert assign_resp.status_code == 200
    assert assign_resp.json()["assigned_user_id"] == str(user_b.id)

    # Verify history: created_by_user_id is User A (the assigner), new_value is User B (the assignee)
    hist_resp = client.get(f"/api/v1/tasks/{task_id}/history", headers=headers_a)
    assign_hist = [h for h in hist_resp.json() if h["action"] == "reassigned"][0]
    assert assign_hist["created_by_user_id"] == str(user_a.id)
    assert assign_hist["new_value"] == str(user_b.id)


# =========================================================================
# O & P: Password Hashing Security & Public Health Endpoint
# =========================================================================
def test_password_security_and_health_endpoint():
    """Verify password hashing invariants and that /health remains public."""
    # 1. Password hashing
    plain = "MySecretPass99!"
    hashed = get_password_hash(plain)
    assert hashed != plain
    assert hashed.startswith("$2b$") or hashed.startswith("$2a$")
    assert verify_password(plain, hashed) is True
    assert verify_password("WrongPass", hashed) is False

    # 2. Health check remains public without Authorization header
    health_resp = client.get("/health")
    assert health_resp.status_code == 200
    assert health_resp.json() == {"status": "healthy", "database": "connected"}
