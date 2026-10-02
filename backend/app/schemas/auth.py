"""Authentication and User Pydantic request/response schemas."""

from datetime import datetime
from typing import List, Optional
import uuid
from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserCreate(BaseModel):
    """Schema for registering a new User."""

    name: str = Field(min_length=1, max_length=255, description="Full name of the user")
    email: str = Field(min_length=3, max_length=255, description="Email address")
    password: str = Field(min_length=8, max_length=128, description="Plaintext password (minimum 8 characters)")


class UserResponse(BaseModel):
    """Safe public schema for User entity (never exposes password or password_hash)."""

    id: uuid.UUID
    name: str
    email: str
    is_active: bool
    created_at: datetime
    updated_at: datetime
    google_id: Optional[str] = None
    auth_provider: Optional[str] = "local"

    model_config = ConfigDict(from_attributes=True)


class UserListResponse(BaseModel):
    """Paginated list of users."""

    items: List[UserResponse]
    total: int
    page: int
    page_size: int



class LoginRequest(BaseModel):
    """Schema for user credentials authentication."""

    email: str = Field(min_length=1, description="Registered email address")
    password: str = Field(min_length=1, description="Account password")


class GoogleLoginRequest(BaseModel):
    """Schema for Google OAuth credential authentication."""

    id_token: str = Field(min_length=1, description="Google OAuth2 ID token returned by Google Sign-In")


class TokenResponse(BaseModel):
    """Schema returned upon successful authentication or token refresh."""

    access_token: str = Field(description="Signed JWT access token")
    token_type: str = Field(default="bearer", description="Token type")
    expires_in: int = Field(description="Expiration time in seconds")
    refresh_token: Optional[str] = Field(default=None, description="Opaque refresh token for session renewal")


class RefreshTokenRequest(BaseModel):
    """Schema for rotating an existing refresh token."""

    refresh_token: str = Field(min_length=1, description="Opaque refresh token to rotate")


class LogoutRequest(BaseModel):
    """Schema for user logout and refresh token revocation."""

    refresh_token: Optional[str] = Field(default=None, description="Optional refresh token to revoke")


class ChangePasswordRequest(BaseModel):
    """Schema for authenticated password change."""

    current_password: str = Field(min_length=1, max_length=128, description="Current account password")
    new_password: str = Field(min_length=8, max_length=128, description="New password (minimum 8 characters)")
