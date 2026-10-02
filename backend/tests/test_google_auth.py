"""Tests for Google Authentication (OAuth2 ID Token Verification and Session Issuance).

Validates server-side credential verification, account linking, duplicate prevention,
inactive user rejection, and NextAction JWT token lifecycle.
"""

from typing import Any, Dict
from unittest.mock import MagicMock, patch
import uuid
import pytest
from fastapi.testclient import TestClient
from app.core.config import settings
from app.core.google_auth import GoogleIdentity, InvalidGoogleTokenError, verify_google_id_token
from app.core.security import decode_access_token
from app.main import app
from app.models.user import User
from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import InactiveUserError

client = TestClient(app)


# ==============================================================================
# 1. CORE GOOGLE TOKEN VERIFIER TESTS
# ==============================================================================

def test_verify_google_id_token_empty_or_whitespace():
    """Verify empty or whitespace Google tokens are rejected immediately."""
    with pytest.raises(InvalidGoogleTokenError, match="Google credential is required"):
        verify_google_id_token("")

    with pytest.raises(InvalidGoogleTokenError, match="Google credential is required"):
        verify_google_id_token("   ")


def test_verify_google_id_token_valid():
    """Verify valid Google token extracts strongly-typed GoogleIdentity claims."""
    mock_payload = {
        "iss": "https://accounts.google.com",
        "sub": "google-user-123456789",
        "email": "Alex.Tester@Gmail.COM",
        "email_verified": True,
        "name": "Alex Tester",
        "picture": "https://lh3.googleusercontent.com/a/abc",
        "aud": "valid-client-id.apps.googleusercontent.com",
    }

    with patch("google.oauth2.id_token.verify_oauth2_token", return_value=mock_payload):
        identity = verify_google_id_token(
            "dummy-valid-token",
            client_ids=["valid-client-id.apps.googleusercontent.com"],
        )
        assert identity.google_id == "google-user-123456789"
        assert identity.email == "alex.tester@gmail.com"
        assert identity.name == "Alex Tester"
        assert identity.email_verified is True
        assert identity.picture == "https://lh3.googleusercontent.com/a/abc"


def test_verify_google_id_token_expired():
    """Verify expired Google tokens raise InvalidGoogleTokenError."""
    with patch(
        "google.oauth2.id_token.verify_oauth2_token",
        side_effect=ValueError("Token expired: exp is in the past"),
    ):
        with pytest.raises(InvalidGoogleTokenError, match="Token expired"):
            verify_google_id_token("expired-token")


def test_verify_google_id_token_wrong_audience():
    """Verify token with unexpected audience raises InvalidGoogleTokenError."""
    mock_payload = {
        "iss": "https://accounts.google.com",
        "sub": "google-user-123456789",
        "email": "alex@gmail.com",
        "email_verified": True,
        "aud": "some-other-client-id.apps.googleusercontent.com",
    }

    with patch("google.oauth2.id_token.verify_oauth2_token", return_value=mock_payload):
        with pytest.raises(InvalidGoogleTokenError, match="audience mismatch"):
            verify_google_id_token(
                "token-wrong-aud",
                client_ids=["expected-client-id.apps.googleusercontent.com"],
            )


def test_verify_google_id_token_unverified_email():
    """Verify token where email_verified is False is strictly rejected."""
    mock_payload = {
        "iss": "https://accounts.google.com",
        "sub": "google-user-123456789",
        "email": "unverified@gmail.com",
        "email_verified": False,
        "aud": "my-client.apps.googleusercontent.com",
    }

    with patch("google.oauth2.id_token.verify_oauth2_token", return_value=mock_payload):
        with pytest.raises(InvalidGoogleTokenError, match="email is not verified"):
            verify_google_id_token("token-unverified-email", client_ids=["my-client.apps.googleusercontent.com"])


def test_verify_google_id_token_invalid_issuer():
    """Verify token from untrusted issuer is rejected."""
    mock_payload = {
        "iss": "https://untrusted-issuer.example.com",
        "sub": "attacker-sub",
        "email": "attacker@example.com",
        "email_verified": True,
        "aud": "valid-client-id.apps.googleusercontent.com",
    }

    with patch("google.oauth2.id_token.verify_oauth2_token", return_value=mock_payload):
        with pytest.raises(InvalidGoogleTokenError, match="Invalid Google token issuer"):
            verify_google_id_token("forged-issuer-token", client_ids=["valid-client-id.apps.googleusercontent.com"])


def test_verify_google_id_token_missing_sub_or_email():
    """Verify token missing sub or email claim is rejected."""
    missing_sub = {
        "iss": "https://accounts.google.com",
        "email": "valid@gmail.com",
        "email_verified": True,
        "aud": "valid-client-id.apps.googleusercontent.com",
    }
    with patch("google.oauth2.id_token.verify_oauth2_token", return_value=missing_sub):
        with pytest.raises(InvalidGoogleTokenError, match="subject identifier"):
            verify_google_id_token("no-sub-token", client_ids=["valid-client-id.apps.googleusercontent.com"])

    missing_email = {
        "iss": "https://accounts.google.com",
        "sub": "12345",
        "email_verified": True,
        "aud": "valid-client-id.apps.googleusercontent.com",
    }
    with patch("google.oauth2.id_token.verify_oauth2_token", return_value=missing_email):
        with pytest.raises(InvalidGoogleTokenError, match="valid email"):
            verify_google_id_token("no-email-token", client_ids=["valid-client-id.apps.googleusercontent.com"])


# ==============================================================================
# 2. ENDPOINT INTEGRATION TESTS (POST /api/v1/auth/google)
# ==============================================================================

def test_google_auth_endpoint_new_user_creation():
    """Verify new Google user is created in database and receives valid NextAction JWTs."""
    mock_identity = GoogleIdentity(
        google_id="google_sub_new_user_9999",
        email="new.google.user@example.com",
        name="New Google User",
        email_verified=True,
    )

    with patch("app.services.auth_service.verify_google_id_token", return_value=mock_identity):
        response = client.post(
            "/api/v1/auth/google",
            json={"id_token": "valid.google.id.token.new.user"},
        )
        assert response.status_code == 200, response.text
        data = response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"
        assert data["expires_in"] == settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
        assert data["refresh_token"] is not None

        # Verify access token decodes to the newly created user ID
        claims = decode_access_token(data["access_token"])
        assert claims is not None
        user_id = claims["sub"]

        # Verify user can access /api/v1/auth/me
        me_resp = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {data['access_token']}"},
        )
        assert me_resp.status_code == 200
        me_data = me_resp.json()
        assert me_data["id"] == user_id
        assert me_data["email"] == "new.google.user@example.com"
        assert me_data["name"] == "New Google User"
        assert me_data["is_active"] is True


def test_google_auth_endpoint_account_linking_existing_user():
    """Verify existing password user is safely linked to Google without creating duplicates."""
    # 1. Register a user via standard email/password registration
    unique_suffix = uuid.uuid4().hex[:8]
    reg_email = f"linkable_{unique_suffix}@example.com"
    reg_resp = client.post(
        "/api/v1/auth/register",
        json={
            "name": "Original Name",
            "email": reg_email,
            "password": "Password123!",
        },
    )
    assert reg_resp.status_code == 201, reg_resp.text
    original_user_id = reg_resp.json()["id"]

    # 2. Authenticate using Google with the same verified email
    mock_identity = GoogleIdentity(
        google_id=f"google_sub_linked_{unique_suffix}",
        email=reg_email,
        name="Google Updated Name",
        email_verified=True,
    )

    with patch("app.services.auth_service.verify_google_id_token", return_value=mock_identity):
        google_resp = client.post(
            "/api/v1/auth/google",
            json={"id_token": "valid.google.id.token.link"},
        )
        assert google_resp.status_code == 200, google_resp.text
        data = google_resp.json()

        # Decoded subject must be the EXACT original user ID (no duplicate account created)
        claims = decode_access_token(data["access_token"])
        assert claims["sub"] == original_user_id

        # Profile /me returns same original user ID
        me_resp = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {data['access_token']}"},
        )
        assert me_resp.status_code == 200
        assert me_resp.json()["id"] == original_user_id


def test_google_auth_endpoint_duplicate_prevention_on_subsequent_login():
    """Verify repeated Google logins for the same account return the exact same user ID."""
    unique_suffix = uuid.uuid4().hex[:8]
    mock_identity = GoogleIdentity(
        google_id=f"google_sub_repeat_{unique_suffix}",
        email=f"repeat_{unique_suffix}@example.com",
        name="Repeat User",
        email_verified=True,
    )

    with patch("app.services.auth_service.verify_google_id_token", return_value=mock_identity):
        # First login (creates user)
        resp1 = client.post("/api/v1/auth/google", json={"id_token": "token1"})
        assert resp1.status_code == 200
        user_id_1 = decode_access_token(resp1.json()["access_token"])["sub"]

        # Second login (fetches existing user)
        resp2 = client.post("/api/v1/auth/google", json={"id_token": "token2"})
        assert resp2.status_code == 200
        user_id_2 = decode_access_token(resp2.json()["access_token"])["sub"]

        assert user_id_1 == user_id_2


def test_google_auth_endpoint_invalid_token_rejection():
    """Verify invalid or unverified Google tokens return HTTP 401 Unauthorized."""
    with patch(
        "app.services.auth_service.verify_google_id_token",
        side_effect=InvalidGoogleTokenError("Invalid token signature"),
    ):
        resp = client.post(
            "/api/v1/auth/google",
            json={"id_token": "bad-signature-token"},
        )
        assert resp.status_code == 401
        assert "Invalid token signature" in resp.text or "error" in resp.json()


def test_google_auth_endpoint_missing_payload_validation():
    """Verify empty payload fails Pydantic validation with HTTP 422."""
    resp = client.post("/api/v1/auth/google", json={})
    assert resp.status_code == 422

    resp_empty_token = client.post("/api/v1/auth/google", json={"id_token": ""})
    assert resp_empty_token.status_code == 422
