"""Google OAuth2 ID token server-side verification.

Validates Google identity tokens against Google's public certificates,
expiration timestamps, authorized audiences (Google Client IDs), and identity claims.
"""

from dataclasses import dataclass
import logging
from typing import Any, Dict, List, Optional
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from app.core.config import settings
from app.services.exceptions import InvalidCredentialsError

logger = logging.getLogger("nextaction.auth.google")

GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


@dataclass
class GoogleIdentity:
    """Verified identity claims extracted from a validated Google ID token."""

    google_id: str
    email: str
    name: str
    email_verified: bool
    picture: Optional[str] = None


class InvalidGoogleTokenError(InvalidCredentialsError):
    """Raised when a Google ID token fails signature, expiry, audience, or claim checks."""

    def __init__(self, message: str = "Invalid or expired Google authentication credential."):
        super().__init__(message=message)


def verify_google_id_token(
    token: str,
    client_ids: Optional[List[str]] = None,
    request: Optional[Any] = None,
) -> GoogleIdentity:
    """Validate a Google OAuth2 ID token and extract verified user identity claims.

    Args:
        token: Raw Google ID token (JWT) from client.
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

    try:
        # Note: If audience is None, google_id_token verifies signature and exp without aud check.
        # We perform explicit multi-audience validation below.
        single_aud = allowed_audiences[0] if len(allowed_audiences) == 1 else None
        payload: Dict[str, Any] = google_id_token.verify_oauth2_token(
            token.strip(),
            req,
            audience=single_aud,
        )
    except ValueError as e:
        logger.warning(f"Google ID token verification failed: {e}")
        raise InvalidGoogleTokenError(f"Invalid Google ID token: {str(e)}") from e
    except Exception as e:
        logger.warning(f"Google ID token verification unexpected error: {e}")
        raise InvalidGoogleTokenError("Failed to verify Google credential.") from e

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
