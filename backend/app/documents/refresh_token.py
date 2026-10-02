"""MongoDB document schema for RefreshToken entity."""

from datetime import datetime
from typing import Optional
from pydantic import Field
from app.documents.common import BaseDocument


class RefreshTokenDocument(BaseDocument):
    """Server-side revocable refresh token document."""

    user_id: str = Field(description="Associated User UUID string")
    token_hash: str = Field(min_length=64, max_length=64, description="SHA-256 token hash")
    expires_at: datetime = Field(description="Token expiration UTC timestamp")
    is_revoked: bool = Field(default=False)
    revoked_at: Optional[datetime] = Field(default=None)
    replaced_by_id: Optional[str] = Field(default=None, description="Next RefreshToken UUID string")
    ip_address: Optional[str] = Field(default=None, max_length=45)
    user_agent: Optional[str] = Field(default=None, max_length=500)
