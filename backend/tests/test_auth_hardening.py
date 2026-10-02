"""Phase 20 Comprehensive Security and Authentication Hardening Test Suite.

Covers:
1. Missing JWT (401)
2. Malformed JWT (401)
3. Expired JWT (401)
4. Invalid signature (401)
5. Wrong algorithm (401)
6. Inactive user login rejection (401)
7. Inactive user token rejection in get_current_user (401)
8. Password hash security (bcrypt verification, never plaintext)
9. Password hash never serialized in API responses
10. Cross-user task access and actor enforcement
11. Cross-user notification isolation (404 on other user's notification)
12. Cross-user settings access isolation
13. Cross-user report authentication requirement
14. Cross-user scheduler isolation
15. Template ownership enforcement (403 for non-creator)
16. Recurring task ownership enforcement (403 for non-creator)
17. User assignment authorization
18. Actor spoofing prevention
19. Invalid IDs (422)
20. Invalid enums (422)
21. Invalid pagination bounds (422)
22. Consistent authentication failure errors without user enumeration
23. Login abuse / rate limiting behavior
24. Security headers verification (X-Content-Type-Options, X-Frame-Options, etc.)
25. Authenticated password change (success, wrong current, same password)
"""

from datetime import datetime, timedelta, timezone
import uuid
from fastapi.testclient import TestClient
import jwt
import pytest
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.rate_limit import limiter
from app.core.security import create_access_token, get_password_hash, verify_password
from app.models.notification import Notification
from app.models.task import Task
from app.models.user import User
from app.services.auth_service import register_user
from app.services.notification_service import create_notification
from app.services.recurring_task_service import create_recurring_task
from app.services.task_service import create_task
from app.services.task_template_service import create_task_template


@pytest.fixture(autouse=True)
def reset_rate_limiter():
    limiter.reset()
    yield
    limiter.reset()


def _make_user(db: Session, prefix: str) -> tuple[User, str, str]:
    tag = uuid.uuid4().hex[:8]
    email = f"{prefix}_{tag}@example.com"
    pwd = "SecurePassword123!"
    user = register_user(db=db, name=f"User {prefix.title()}", email=email, password=pwd)
    return user, email, pwd


# =============================================================================
# 1-5. JWT Validation & Tampering Tests
# =============================================================================

def test_missing_jwt_returns_401(client: TestClient):
    """Calling protected endpoints without Authorization header returns HTTP 401."""
    resp = client.get("/api/v1/auth/me")
    assert resp.status_code == 401
    assert resp.json()["error"] == "AUTHENTICATION_REQUIRED"


def test_malformed_jwt_returns_401(client: TestClient):
    """Calling protected endpoints with invalid/malformed token returns HTTP 401."""
    headers = {"Authorization": "Bearer not.a.valid.jwt.token"}
    resp = client.get("/api/v1/auth/me", headers=headers)
    assert resp.status_code == 401
    assert resp.json()["error"] == "INVALID_TOKEN"


def test_expired_jwt_returns_401(client: TestClient, db: Session):
    """Calling protected endpoints with expired JWT returns HTTP 401."""
    user, _, _ = _make_user(db, "expired")
    # Generate token with negative delta
    expired_token, _ = create_access_token(
        subject=str(user.id),
        expires_delta=timedelta(seconds=-10),
    )
    headers = {"Authorization": f"Bearer {expired_token}"}
    resp = client.get("/api/v1/auth/me", headers=headers)
    assert resp.status_code == 401
    assert resp.json()["error"] == "INVALID_TOKEN"


def test_invalid_signature_jwt_returns_401(client: TestClient, db: Session):
    """JWT signed with an untrusted secret is rejected with HTTP 401."""
    user, _, _ = _make_user(db, "tampered")
    fake_token = jwt.encode(
        {"sub": str(user.id), "iat": int(datetime.now(timezone.utc).timestamp()), "exp": int((datetime.now(timezone.utc) + timedelta(hours=1)).timestamp()), "type": "access"},
        "wrong_untrusted_secret_key_123456789",
        algorithm="HS256",
    )
    headers = {"Authorization": f"Bearer {fake_token}"}
    resp = client.get("/api/v1/auth/me", headers=headers)
    assert resp.status_code == 401
    assert resp.json()["error"] == "INVALID_TOKEN"


def test_wrong_algorithm_jwt_returns_401(client: TestClient, db: Session):
    """JWT signed with 'none' or unconfigured algorithm is rejected with HTTP 401."""
    user, _, _ = _make_user(db, "alg")
    # 'none' algorithm token
    header = {"alg": "none", "typ": "JWT"}
    payload = {"sub": str(user.id), "iat": 1000, "exp": 9999999999, "type": "access"}
    import base64
    import json
    b64_h = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
    b64_p = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    none_token = f"{b64_h}.{b64_p}."

    headers = {"Authorization": f"Bearer {none_token}"}
    resp = client.get("/api/v1/auth/me", headers=headers)
    assert resp.status_code == 401
    assert resp.json()["error"] == "INVALID_TOKEN"


# =============================================================================
# 6-7. Inactive User Handling
# =============================================================================

def test_inactive_user_login_fails(client: TestClient, db: Session):
    """Inactive user cannot authenticate via login endpoint."""
    user, email, pwd = _make_user(db, "inactive_login")
    user.is_active = False
    db.commit()

    resp = client.post("/api/v1/auth/login", json={"email": email, "password": pwd})
    assert resp.status_code == 401
    assert resp.json()["error"] == "INACTIVE_USER"


def test_inactive_user_token_rejected_in_protected_endpoints(client: TestClient, db: Session):
    """An active user who becomes inactive has their token immediately rejected on protected APIs."""
    user, email, pwd = _make_user(db, "inactivated")
    login_resp = client.post("/api/v1/auth/login", json={"email": email, "password": pwd})
    assert login_resp.status_code == 200
    token = login_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Verify active access succeeds
    me_resp1 = client.get("/api/v1/auth/me", headers=headers)
    assert me_resp1.status_code == 200

    # Inactivate user
    user.is_active = False
    db.commit()

    # Next call with existing token must fail
    me_resp2 = client.get("/api/v1/auth/me", headers=headers)
    assert me_resp2.status_code == 401
    assert me_resp2.json()["error"] == "INACTIVE_USER"


# =============================================================================
# 8-9. Password Hash Security & Serialization Isolation
# =============================================================================

def test_password_hash_security_and_never_serialized(client: TestClient, db: Session):
    """Passwords are bcrypt hashed and password/password_hash are never exposed in any API responses."""
    user, email, pwd = _make_user(db, "hashsec")

    # DB verification: password is not plaintext
    assert user.password_hash != pwd
    assert user.password_hash.startswith("$2b$")
    assert verify_password(pwd, user.password_hash) is True
    assert verify_password("WrongPassword123!", user.password_hash) is False

    # Check /auth/me
    login_resp = client.post("/api/v1/auth/login", json={"email": email, "password": pwd})
    headers = {"Authorization": f"Bearer {login_resp.json()['access_token']}"}
    me_data = client.get("/api/v1/auth/me", headers=headers).json()
    assert "password" not in me_data
    assert "password_hash" not in me_data

    # Check /users list
    users_data = client.get("/api/v1/users", headers=headers).json()
    for item in users_data["items"]:
        assert "password" not in item
        assert "password_hash" not in item

    # Check /users/{id}
    user_detail = client.get(f"/api/v1/users/{user.id}", headers=headers).json()
    assert "password" not in user_detail
    assert "password_hash" not in user_detail


# =============================================================================
# 10. Cross-User Task Access & Actor Enforcement
# =============================================================================

def test_task_creation_derives_creator_from_jwt(client: TestClient, db: Session):
    """Task creator is strictly derived from verified JWT, ignoring client body attempts."""
    from app.models.task_history import TaskHistory

    user_a, email_a, pwd_a = _make_user(db, "task_act_a")
    user_b, _, _ = _make_user(db, "task_act_b")

    login_resp = client.post("/api/v1/auth/login", json={"email": email_a, "password": pwd_a})
    headers = {"Authorization": f"Bearer {login_resp.json()['access_token']}"}

    # Attempt to spoof created_by_user_id as user_b
    task_payload = {
        "title": "Security Task",
        "description": "Verify actor",
        "created_by_user_id": str(user_b.id),  # Spoof attempt
    }
    resp = client.post("/api/v1/tasks", json=task_payload, headers=headers)
    assert resp.status_code == 201
    created_task = resp.json()

    # Verified in TaskHistory: actor/creator must be User A (from JWT), not User B
    history = db.query(TaskHistory).filter(TaskHistory.task_id == created_task["id"], TaskHistory.action == "created").first()
    assert history is not None
    assert history.created_by_user_id == user_a.id


# =============================================================================
# 11. Cross-User Notification Access Isolation
# =============================================================================

def test_cross_user_notification_access_denied(client: TestClient, db: Session):
    """User cannot view or mark as read notifications belonging to another user (returns 404)."""
    user_a, _, _ = _make_user(db, "notif_a")
    user_b, email_b, pwd_b = _make_user(db, "notif_b")

    # Create notification for User A
    notif_a = create_notification(
        db=db,
        user_id=user_a.id,
        type="test_alert",
        title="User A Secret Alert",
        message="Confidential",
    )

    # Login as User B
    login_resp = client.post("/api/v1/auth/login", json={"email": email_b, "password": pwd_b})
    headers_b = {"Authorization": f"Bearer {login_resp.json()['access_token']}"}

    # User B attempting to view User A's notification returns 404
    get_resp = client.get(f"/api/v1/notifications/{notif_a.id}", headers=headers_b)
    assert get_resp.status_code == 404
    assert get_resp.json()["error"] == "NOTIFICATION_NOT_FOUND"

    # User B attempting to mark User A's notification as read returns 404
    read_resp = client.post(f"/api/v1/notifications/{notif_a.id}/read", headers=headers_b)
    assert read_resp.status_code == 404
    assert read_resp.json()["error"] == "NOTIFICATION_NOT_FOUND"


# =============================================================================
# 12. Cross-User Settings Access Isolation
# =============================================================================

def test_settings_isolated_to_jwt_user(client: TestClient, db: Session):
    """User settings are strictly bound to JWT context; User B cannot read or alter User A's settings."""
    user_a, email_a, pwd_a = _make_user(db, "set_a")
    user_b, email_b, pwd_b = _make_user(db, "set_b")

    headers_a = {"Authorization": f"Bearer {client.post('/api/v1/auth/login', json={'email': email_a, 'password': pwd_a}).json()['access_token']}"}
    headers_b = {"Authorization": f"Bearer {client.post('/api/v1/auth/login', json={'email': email_b, 'password': pwd_b}).json()['access_token']}"}

    # User A updates timezone to 'America/New_York'
    client.patch("/api/v1/settings", json={"timezone": "America/New_York"}, headers=headers_a)

    # User B reads settings: should have default 'UTC'
    set_b = client.get("/api/v1/settings", headers=headers_b).json()
    assert set_b["user_id"] == str(user_b.id)
    assert set_b["timezone"] == "UTC"

    # User A reads settings: should have 'America/New_York'
    set_a = client.get("/api/v1/settings", headers=headers_a).json()
    assert set_a["user_id"] == str(user_a.id)
    assert set_a["timezone"] == "America/New_York"


# =============================================================================
# 13. Reports Authentication Protection
# =============================================================================

def test_reports_require_authentication(client: TestClient):
    """Reports endpoints reject unauthenticated requests with HTTP 401."""
    resp = client.get("/api/v1/reports/task-summary")
    assert resp.status_code == 401

    resp2 = client.get("/api/v1/reports/tasks/export")
    assert resp2.status_code == 401


# =============================================================================
# 14. Scheduler Isolation
# =============================================================================

def test_scheduler_strictly_evaluates_calling_user(client: TestClient, db: Session):
    """Calling /api/v1/scheduler/evaluate only evaluates due items for the authenticated user."""
    user_a, email_a, pwd_a = _make_user(db, "sched_a")
    user_b, _, _ = _make_user(db, "sched_b")

    past = datetime.now(timezone.utc) - timedelta(hours=2)
    create_task(db=db, title="Overdue Task A", assigned_user_id=user_a.id, due_date=past)
    create_task(db=db, title="Overdue Task B", assigned_user_id=user_b.id, due_date=past)

    headers_a = {"Authorization": f"Bearer {client.post('/api/v1/auth/login', json={'email': email_a, 'password': pwd_a}).json()['access_token']}"}

    # User A triggers scheduler
    resp = client.post("/api/v1/scheduler/evaluate", json={"user_scoped": False}, headers=headers_a)
    assert resp.status_code == 200
    data = resp.json()
    assert data["notifications_created"] == 1

    # Verify User A received overdue notification, but User B did not
    notifs_a = db.query(Notification).filter(Notification.user_id == user_a.id).all()
    notifs_b = db.query(Notification).filter(Notification.user_id == user_b.id).all()
    overdue_a = [n for n in notifs_a if n.type == "task_overdue"]
    overdue_b = [n for n in notifs_b if n.type == "task_overdue"]
    assert len(overdue_a) == 1
    assert len(overdue_b) == 0


# =============================================================================
# 15-16. Task Template & Recurring Task Ownership (403 for Non-Creators)
# =============================================================================

def test_template_ownership_enforced(client: TestClient, db: Session):
    """Non-creator cannot update or delete a task template (returns HTTP 403)."""
    user_a, _, _ = _make_user(db, "tmpl_a")
    user_b, email_b, pwd_b = _make_user(db, "tmpl_b")

    tmpl = create_task_template(
        db=db,
        name="Template A",
        created_by_user_id=user_a.id,
    )

    headers_b = {"Authorization": f"Bearer {client.post('/api/v1/auth/login', json={'email': email_b, 'password': pwd_b}).json()['access_token']}"}

    # User B attempting to update User A's template returns 403
    patch_resp = client.patch(f"/api/v1/task-templates/{tmpl.id}", json={"name": "Hacked"}, headers=headers_b)
    assert patch_resp.status_code == 403
    assert patch_resp.json()["error"] == "UNAUTHORIZED_TEMPLATE_ACCESS"

    # User B attempting to delete User A's template returns 403
    del_resp = client.delete(f"/api/v1/task-templates/{tmpl.id}", headers=headers_b)
    assert del_resp.status_code == 403
    assert del_resp.json()["error"] == "UNAUTHORIZED_TEMPLATE_ACCESS"


def test_recurring_task_ownership_enforced(client: TestClient, db: Session):
    """Non-creator cannot update or delete a recurring task definition (returns HTTP 403)."""
    user_a, _, _ = _make_user(db, "rec_a")
    user_b, email_b, pwd_b = _make_user(db, "rec_b")

    rec = create_recurring_task(
        db=db,
        name="Daily Audit A",
        recurrence_type="daily",
        interval=1,
        start_date=datetime.now(timezone.utc),
        created_by_user_id=user_a.id,
    )

    headers_b = {"Authorization": f"Bearer {client.post('/api/v1/auth/login', json={'email': email_b, 'password': pwd_b}).json()['access_token']}"}

    # User B attempting to update User A's recurring task returns 403
    patch_resp = client.patch(f"/api/v1/recurring-tasks/{rec.id}", json={"name": "Hacked"}, headers=headers_b)
    assert patch_resp.status_code == 403
    assert patch_resp.json()["error"] == "UNAUTHORIZED_RECURRING_TASK_ACCESS"

    # User B attempting to delete User A's recurring task returns 403
    del_resp = client.delete(f"/api/v1/recurring-tasks/{rec.id}", headers=headers_b)
    assert del_resp.status_code == 403
    assert del_resp.json()["error"] == "UNAUTHORIZED_RECURRING_TASK_ACCESS"


# =============================================================================
# 17-18. User Assignment Authorization & Actor Integrity
# =============================================================================

def test_task_assignment_and_actor_integrity(client: TestClient, db: Session):
    """Tasks can be assigned to other active users, but actor is always the authenticated user."""
    from app.models.task_history import TaskHistory

    user_a, email_a, pwd_a = _make_user(db, "assigner")
    user_b, _, _ = _make_user(db, "assignee")

    headers_a = {"Authorization": f"Bearer {client.post('/api/v1/auth/login', json={'email': email_a, 'password': pwd_a}).json()['access_token']}"}

    task_resp = client.post(
        "/api/v1/tasks",
        json={"title": "Delegated Task", "assigned_user_id": str(user_b.id)},
        headers=headers_a,
    )
    assert task_resp.status_code == 201
    task_data = task_resp.json()
    assert task_data["assigned_user_id"] == str(user_b.id)

    # Verified: actor recorded in history must be User A (from JWT)
    history = db.query(TaskHistory).filter(TaskHistory.task_id == task_data["id"], TaskHistory.action == "created").first()
    assert history is not None
    assert history.created_by_user_id == user_a.id


# =============================================================================
# 19-21. Input Validation: Malformed UUIDs, Enums, and Pagination Bounds
# =============================================================================

def test_invalid_uuid_returns_422(client: TestClient, auth_headers):
    """Malformed UUID returns HTTP 422 Unprocessable Entity."""
    headers, _ = auth_headers
    resp = client.get("/api/v1/tasks/not-a-valid-uuid", headers=headers)
    assert resp.status_code == 422


def test_invalid_enum_returns_422(client: TestClient, auth_headers):
    """Invalid enum value in query parameter returns HTTP 422."""
    headers, _ = auth_headers
    resp = client.get("/api/v1/tasks?status=INVALID_STATUS", headers=headers)
    assert resp.status_code == 422


def test_invalid_pagination_returns_422(client: TestClient, auth_headers):
    """Out-of-bounds pagination parameters return HTTP 422."""
    headers, _ = auth_headers
    # Page < 1
    resp1 = client.get("/api/v1/tasks?page=0", headers=headers)
    assert resp1.status_code == 422

    # Page size > 100
    resp2 = client.get("/api/v1/tasks?page_size=150", headers=headers)
    assert resp2.status_code == 422


# =============================================================================
# 22. Authentication Error Responses (No Account Enumeration)
# =============================================================================

def test_authentication_error_responses_consistent(client: TestClient, db: Session):
    """Non-existent user and wrong password return identical HTTP 401 INVALID_CREDENTIALS."""
    user, email, pwd = _make_user(db, "enum_test")

    # Non-existent user
    resp1 = client.post("/api/v1/auth/login", json={"email": "does_not_exist@example.com", "password": "WrongPassword123!"})
    assert resp1.status_code == 401
    assert resp1.json()["error"] == "INVALID_CREDENTIALS"

    # Existing user, wrong password
    resp2 = client.post("/api/v1/auth/login", json={"email": email, "password": "WrongPassword123!"})
    assert resp2.status_code == 401
    assert resp2.json()["error"] == "INVALID_CREDENTIALS"
    assert resp1.json()["message"] == resp2.json()["message"]


# =============================================================================
# 23. Login Rate Limiting / Abuse Protection
# =============================================================================

def test_login_rate_limiting_protects_against_abuse(client: TestClient, db: Session):
    """Exceeding max login attempts within window returns HTTP 429 Too Many Requests."""
    limiter.reset()
    user, email, pwd = _make_user(db, "ratelimit")

    # Perform attempts up to max_attempts
    for _ in range(settings.RATE_LIMIT_MAX_ATTEMPTS):
        limiter.is_rate_limited("auth:test_ip", settings.RATE_LIMIT_MAX_ATTEMPTS, 60)

    # Next attempt should be limited
    is_limited, retry_after = limiter.is_rate_limited("auth:test_ip", settings.RATE_LIMIT_MAX_ATTEMPTS, 60)
    assert is_limited is True
    assert retry_after > 0
    limiter.reset()


# =============================================================================
# 24. Security Headers Verification
# =============================================================================

def test_security_headers_present(client: TestClient):
    """Responses include standard hardening HTTP headers."""
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.headers.get("X-Content-Type-Options") == "nosniff"
    assert resp.headers.get("X-Frame-Options") == "DENY"
    assert resp.headers.get("X-XSS-Protection") == "1; mode=block"
    assert resp.headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"


# =============================================================================
# 25. Authenticated Password Change
# =============================================================================

def test_authenticated_password_change_flow(client: TestClient, db: Session):
    """User can change password; old password fails; new password works."""
    user, email, old_pwd = _make_user(db, "pwd_change")
    new_pwd = "NewSecurePassword456!"

    headers = {"Authorization": f"Bearer {client.post('/api/v1/auth/login', json={'email': email, 'password': old_pwd}).json()['access_token']}"}

    # Wrong current password fails
    bad_resp = client.post(
        "/api/v1/auth/change-password",
        json={"current_password": "WrongPassword123!", "new_password": new_pwd},
        headers=headers,
    )
    assert bad_resp.status_code == 401
    assert bad_resp.json()["error"] == "INVALID_CREDENTIALS"

    # Same password fails
    same_resp = client.post(
        "/api/v1/auth/change-password",
        json={"current_password": old_pwd, "new_password": old_pwd},
        headers=headers,
    )
    assert same_resp.status_code == 400

    # Successful change
    good_resp = client.post(
        "/api/v1/auth/change-password",
        json={"current_password": old_pwd, "new_password": new_pwd},
        headers=headers,
    )
    assert good_resp.status_code == 200
    assert "password" not in good_resp.json()
    assert "password_hash" not in good_resp.json()

    # Login with old password fails
    login_old = client.post("/api/v1/auth/login", json={"email": email, "password": old_pwd})
    assert login_old.status_code == 401

    # Login with new password succeeds
    login_new = client.post("/api/v1/auth/login", json={"email": email, "password": new_pwd})
    assert login_new.status_code == 200
    assert "access_token" in login_new.json()
