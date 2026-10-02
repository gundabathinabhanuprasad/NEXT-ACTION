"""MongoDB repository for RefreshToken documents."""

from datetime import datetime
from typing import Any, Dict, List, Optional, Union
import uuid
from pymongo.database import Database
from app.documents.common import utcnow
from app.documents.refresh_token import RefreshTokenDocument
from app.repositories.mongodb_base import BaseMongoRepository


class RefreshTokenRepository(BaseMongoRepository):
    """Data access repository for refresh_tokens collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("refresh_tokens", db=db)

    def create(self, token_data: Union[RefreshTokenDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new refresh token document."""
        if isinstance(token_data, RefreshTokenDocument):
            payload = token_data.to_mongo()
        else:
            payload = dict(token_data)
        return self.insert_doc(payload)

    def get_by_id(self, token_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve a token document by UUID string."""
        return self.find_by_id(token_id)

    def get_by_token_hash(self, token_hash: str) -> Optional[Dict[str, Any]]:
        """Find a refresh token by its SHA-256 hash."""
        return self.find_one({"token_hash": token_hash})

    def revoke_token(
        self,
        token_hash: str,
        replaced_by_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> bool:
        """Mark a refresh token as revoked, optionally linking the replacement token ID."""
        now = utcnow()
        update_fields: Dict[str, Any] = {
            "is_revoked": True,
            "revoked_at": now,
            "updated_at": now,
        }
        if replaced_by_id is not None:
            update_fields["replaced_by_id"] = str(replaced_by_id)

        result = self.collection.update_one(
            {"token_hash": token_hash, "is_revoked": False},
            {"$set": update_fields},
        )
        return result.modified_count > 0

    def revoke_all_for_user(self, user_id: Union[str, uuid.UUID]) -> int:
        """Revoke all active refresh tokens for a user (e.g. upon logout all sessions or password reset)."""
        now = utcnow()
        result = self.collection.update_many(
            {"user_id": str(user_id), "is_revoked": False},
            {"$set": {"is_revoked": True, "revoked_at": now, "updated_at": now}},
        )
        return result.modified_count

    def list_active_for_user(self, user_id: Union[str, uuid.UUID]) -> List[Dict[str, Any]]:
        """List unexpired, unrevoked tokens for a user."""
        now = utcnow()
        query = {
            "user_id": str(user_id),
            "is_revoked": False,
            "expires_at": {"$gt": now},
        }
        return self.find_many(query, sort_by="created_at", sort_order="desc")

    def delete_expired(self, before_timestamp: Optional[datetime] = None) -> int:
        """Purge expired or revoked tokens older than the provided threshold."""
        threshold = before_timestamp or utcnow()
        result = self.collection.delete_many({
            "$or": [
                {"expires_at": {"$lte": threshold}},
                {"is_revoked": True, "revoked_at": {"$lte": threshold}},
            ]
        })
        return result.deleted_count
