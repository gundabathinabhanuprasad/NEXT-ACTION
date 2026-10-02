"""Google OAuth2 ID token and Access token server-side verification.

Validates Google identity tokens against Google's public certificates,
expiration timestamps, authorized audiences (Google Client IDs), and identity claims.
Also provides fallback verification for OAuth2 access tokens via Google tokeninfo/userinfo.
"""

from dataclasses import dataclass
import json
import logging
from typing import Any, Dict, List, Optional
import urllib.request

from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from app.core.config import settings
from app.services.exceptions import InvalidCredentialsError

logger = logging.getLogger("nextaction.auth.google")

GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


@dataclass
class GoogleIdentity:
    """Verified identity claims extracted from a validated Google ID token or access token."""

    google_id: str
    email: str
    name: str
    email_verified: bool
    picture: Optional[str] = None


class InvalidGoogleTokenError(InvalidCredentialsError):
    """Raised when a Google token fails signature, expiry, audience, or claim checks."""

    def __init__(self, message: str = "Invalid or expired Google authentication credential."):
        super().__init__(message=message)


def _try_verify_access_token(token: str, allowed_audiences: Optional[List[str]]) -> Optional[Dict[str, Any]]:
    """Attempt to verify token as an OAuth2 access token via Google tokeninfo and userinfo."""
    try:
        url = f"https://oauth2.googleapis.com/tokeninfo?access_token={token}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            info = json.loads(resp.read().decode("utf-8"))

        aud = info.get("aud") or info.get("azp")
        if allowed_audiences and aud and aud not in allowed_audiences:
            logger.warning(f"Google access token aud '{aud}' not in {allowed_audiences}")
            return None

        userinfo_url = "https://www.googleapis.com/oauth2/v3/userinfo"
        u_req = urllib.request.Request(userinfo_url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(u_req, timeout=10) as u_resp:
            userinfo = json.loads(u_resp.read().decode("utf-8"))

        email_verified_raw = userinfo.get("email_verified", info.get("email_verified"))
        email_verified = email_verified_raw is True or str(email_verified_raw).lower() == "true"

        return {
            "iss": "https://accounts.google.com",
            "sub": userinfo.get("sub") or info.get("sub") or info.get("user_id"),
            "email": userinfo.get("email") or info.get("email"),
            "email_verified": email_verified,
            "name": userinfo.get("name") or (userinfo.get("email") or "").split("@")[0],
            "picture": userinfo.get("picture"),
            "aud": aud or (allowed_audiences[0] if allowed_audiences else None),
        }
    except Exception as e:
        logger.debug(f"Token is not a valid Google access token: {e}")
        return None


def verify_google_id_token(
    token: str,
    client_ids: Optional[List[str]] = None,
    request: Optional[Any] = None,
) -> GoogleIdentity:
    """Validate a Google OAuth2 ID token (or access token) and extract verified user identity claims.

    Args:
        token: Raw Google ID token (JWT) or access token from client.
        client_ids: Optional override of accepted Google Client IDs (defaults to settings).
        request: Optional HTTP transport request object for mockability in tests.

    Returns:
        GoogleIdentity: Verified user profile.

    Raises:
        InvalidGoogleTokenError: If token is malformed, expired, forged, wrong audience,
            or contains an unverified email address.
    """
    if not token or not token.strip():
        raise InvalidGoogleTokenError("Google credential is required.")

    req = request or google_requests.Request()
    allowed_audiences = client_ids if client_ids is not None else settings.get_google_client_ids()

    payload: Optional[Dict[str, Any]] = None

    try:
        single_aud = allowed_audiences[0] if len(allowed_audiences) == 1 else None
        payload = google_id_token.verify_oauth2_token(
            token.strip(),
            req,
            audience=single_aud,
        )
    except ValueError as e:
        # Check if the token is an OAuth2 access token
        payload = _try_verify_access_token(token.strip(), allowed_audiences)
        if not payload:
            logger.warning(f"Google ID token verification failed: {e}")
            raise InvalidGoogleTokenError(f"Invalid Google ID token: {str(e)}") from e
    except Exception as e:
        payload = _try_verify_access_token(token.strip(), allowed_audiences)
        if not payload:
            logger.warning(f"Google token verification unexpected error: {e}")
            raise InvalidGoogleTokenError("Failed to verify Google credential.") from e

    if not payload:
        raise InvalidGoogleTokenError("Failed to verify Google credential.")

    # Explicit audience check if multiple client IDs are configured
    if allowed_audiences:
        token_aud = payload.get("aud")
        if token_aud not in allowed_audiences:
            logger.warning(
                f"Google token audience mismatch: token_aud '{token_aud}' not in {allowed_audiences}"
            )
            raise InvalidGoogleTokenError("Google token audience mismatch.")

    # Check issuer
    issuer = payload.get("iss")
    if issuer not in GOOGLE_ISSUERS:
        logger.warning(f"Invalid Google token issuer: '{issuer}'")
        raise InvalidGoogleTokenError(f"Invalid Google token issuer: {issuer}")

    # Check email verified
    email_verified = payload.get("email_verified")
    if not email_verified:
        logger.warning("Google account email is not verified.")
        raise InvalidGoogleTokenError("Google account email is not verified.")

    email = payload.get("email")
    if not email or not isinstance(email, str) or not email.strip():
        raise InvalidGoogleTokenError("Google token does not contain a valid email address.")

    google_id = payload.get("sub")
    if not google_id or not isinstance(google_id, str) or not google_id.strip():
        raise InvalidGoogleTokenError("Google token does not contain a subject identifier.")

    name = payload.get("name") or payload.get("given_name") or email.split("@")[0]
    picture = payload.get("picture")

    return GoogleIdentity(
        google_id=google_id.strip(),
        email=email.strip().lower(),
        name=str(name).strip(),
        email_verified=True,
        picture=str(picture).strip() if picture else None,
    )
