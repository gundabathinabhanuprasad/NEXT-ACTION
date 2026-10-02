"""Tests for Phase 22 deployment hardening, security, distributed rate limiting, and refresh tokens."""

from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock
import pytest
from fastapi.testclient import TestClient
import redis

from app.core.config import Settings
from app.core.rate_limit import InMemoryRateLimiter, RedisRateLimiter
from app.core.security import generate_refresh_token, hash_refresh_token
from app.main import app
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.services.auth_service import (
    authenticate_user,
    create_refresh_token_for_user,
    revoke_refresh_token,
    rotate_refresh_token,
)
from app.services.exceptions import (
    InactiveUserError,
    RefreshTokenExpiredError,
    RefreshTokenNotFoundError,
    RefreshTokenRevokedError,
)

client = TestClient(app)


# =============================================================================
# 1. Production CORS & Trusted Host Configuration Tests
# =============================================================================

def test_production_wildcard_cors_rejected():
    """Verify that settings reject wildcard '*' CORS origin in production."""
    with pytest.raises(ValueError, match="FATAL SECURITY VIOLATION: Production CORS cannot include wildcard"):
        s = Settings(
            ENVIRONMENT="production",
            JWT_SECRET_KEY="a" * 32,
            POSTGRES_PASSWORD="secure_strong_db_password_123",
            CORS_ORIGINS=["*"],
        )
        s.validate_production_security()


def test_production_wildcard_trusted_hosts_rejected():
    """Verify that settings reject wildcard '*' trusted host in production."""
    with pytest.raises(ValueError, match="FATAL SECURITY VIOLATION: Production TRUSTED_HOSTS cannot include wildcard"):
        s = Settings(
            ENVIRONMENT="production",
            JWT_SECRET_KEY="a" * 32,
            POSTGRES_PASSWORD="secure_strong_db_password_123",
            CORS_ORIGINS=["https://app.nextaction.com"],
            TRUSTED_HOSTS=["*"],
        )
        s.validate_production_security()


def test_production_valid_configuration_passes():
    """Verify valid production settings pass security validation."""
    s = Settings(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="a" * 32,
        POSTGRES_PASSWORD="secure_strong_db_password_123",
        CORS_ORIGINS=["https://app.nextaction.com"],
        TRUSTED_HOSTS=["app.nextaction.com", "api.nextaction.com"],
        DB_SSLMODE="require",
    )
    s.validate_production_security()
    assert "sslmode=require" in s.database_url


# =============================================================================
# 2. Server-side Refresh Token & Rotation Tests
# =============================================================================

def test_refresh_token_generation_and_hashing():
    """Verify refresh token generation produces high entropy and SHA-256 hash matches."""
    token = generate_refresh_token()
    assert len(token) >= 48
    thash = hash_refresh_token(token)
    assert len(thash) == 64
    assert thash == hash_refresh_token(token)


def test_refresh_token_lifecycle_login_rotate_logout(db):
    """Verify full login -> refresh rotation -> logout lifecycle."""
    email = f"refresh_user_{datetime.now().timestamp()}@example.com"
    pwd = "SecurePassword123!"

    # 1. Register user
    reg = client.post("/api/v1/auth/register", json={"name": "Refresh Tester", "email": email, "password": pwd})
    assert reg.status_code == 201

    # 2. Login returns access_token AND refresh_token
    login_res = client.post("/api/v1/auth/login", json={"email": email, "password": pwd})
    assert login_res.status_code == 200
    data = login_res.json()
    assert "access_token" in data
    assert "refresh_token" in data
    old_access = data["access_token"]
    old_refresh = data["refresh_token"]

    # 3. Rotate refresh token
    rotate_res = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    assert rotate_res.status_code == 200
    rotated_data = rotate_res.json()
    new_access = rotated_data["access_token"]
    new_refresh = rotated_data["refresh_token"]

    assert new_access != old_access
    assert new_refresh != old_refresh

    # 4. Old access token can still be used until expiry, but old refresh token is revoked
    replay_res = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    assert replay_res.status_code == 401
    err_body = replay_res.json()
    err_text = err_body.get("message") or err_body.get("detail", "")
    assert "revoked" in err_text.lower()

    # Replay attack invalidates all sessions: even the new_refresh is now revoked!
    new_after_replay = client.post("/api/v1/auth/refresh", json={"refresh_token": new_refresh})
    assert new_after_replay.status_code == 401

    # 5. Log in again to test clean logout
    login2 = client.post("/api/v1/auth/login", json={"email": email, "password": pwd})
    assert login2.status_code == 200
    refresh2 = login2.json()["refresh_token"]

    logout_res = client.post("/api/v1/auth/logout", json={"refresh_token": refresh2})
    assert logout_res.status_code == 200

    # Refreshing with logged out token fails
    refresh_after_logout = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh2})
    assert refresh_after_logout.status_code == 401


def test_refresh_token_expired(db):
    """Verify expired refresh token raises RefreshTokenExpiredError."""
    # Create test user
    email = f"expired_refresh_{datetime.now().timestamp()}@example.com"
    user = User(name="Expired", email=email, password_hash="dummy", is_active=True)
    db.add(user)
    db.commit()

    raw_token = generate_refresh_token()
    token_hash = hash_refresh_token(raw_token)
    past = datetime.now(timezone.utc) - timedelta(hours=1)
    record = RefreshToken(
        user_id=user.id,
        token_hash=token_hash,
        expires_at=past,
        is_revoked=False,
    )
    db.add(record)
    db.commit()

    with pytest.raises(RefreshTokenExpiredError):
        rotate_refresh_token(db, raw_token)


def test_inactive_user_cannot_refresh(db):
    """Verify deactivated user cannot rotate refresh token."""
    email = f"inactive_refresh_{datetime.now().timestamp()}@example.com"
    user = User(name="Inactive", email=email, password_hash="dummy", is_active=False)
    db.add(user)
    db.commit()

    record, raw_token = create_refresh_token_for_user(db, user)
    with pytest.raises(InactiveUserError):
        rotate_refresh_token(db, raw_token)


# =============================================================================
# 3. Redis Distributed Rate Limiter & Fallback Tests
# =============================================================================

def test_redis_rate_limiter_normal_sliding_window():
    """Verify RedisRateLimiter correctly tracks requests and blocks when limit reached."""
    mock_redis = MagicMock()
    mock_pipe = MagicMock()
    mock_redis.pipeline.return_value = mock_pipe

    # First request: 0 existing entries in window
    mock_pipe.execute.return_value = [None, 0, []]
    limiter = RedisRateLimiter(redis_client=mock_redis)

    is_limited, retry_after = limiter.is_rate_limited("client_1", max_attempts=3, window_seconds=60)
    assert not is_limited
    assert retry_after == 0

    # Limit reached: 3 existing entries in window
    mock_pipe.execute.return_value = [None, 3, [("1234.5", 1000.0)]]
    limiter._redis_client = mock_redis
    is_limited, retry_after = limiter.is_rate_limited("client_1", max_attempts=3, window_seconds=60)
    assert is_limited
    assert retry_after > 0


def test_redis_rate_limiter_graceful_fallback_on_redis_error():
    """Verify RedisRateLimiter transparently falls back to in-memory limiter on Redis error."""
    mock_redis = MagicMock()
    mock_redis.pipeline.side_effect = redis.ConnectionError("Redis connection refused")
    fallback = InMemoryRateLimiter()

    limiter = RedisRateLimiter(redis_client=mock_redis, fallback_limiter=fallback)

    # 1. Fallback handles requests seamlessly without raising exceptions
    is_limited, retry_after = limiter.is_rate_limited("key_a", max_attempts=2, window_seconds=10)
    assert not is_limited

    is_limited, retry_after = limiter.is_rate_limited("key_a", max_attempts=2, window_seconds=10)
    assert not is_limited

    # 2. Third request exceeds fallback limit
    is_limited, retry_after = limiter.is_rate_limited("key_a", max_attempts=2, window_seconds=10)
    assert is_limited
    assert retry_after > 0

    # 3. Different key is isolated
    is_limited_b, _ = limiter.is_rate_limited("key_b", max_attempts=2, window_seconds=10)
    assert not is_limited_b
