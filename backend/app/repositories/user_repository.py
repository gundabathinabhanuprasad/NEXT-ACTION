"""MongoDB repository for User documents."""

from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
from pymongo.database import Database
from app.documents.user import UserDocument
from app.repositories.mongodb_base import BaseMongoRepository


class UserRepository(BaseMongoRepository):
    """Data access repository for users collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("users", db=db)

    def create(self, user_data: Union[UserDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new user document."""
        if isinstance(user_data, UserDocument):
            payload = user_data.to_mongo()
        else:
            payload = dict(user_data)
        if "email" in payload:
            payload["email"] = payload["email"].strip().lower()
        return self.insert_doc(payload)

    def get_by_id(self, user_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve user by UUID string."""
        return self.find_by_id(user_id)

    def get_by_email(self, email: str) -> Optional[Dict[str, Any]]:
        """Retrieve user by normalized lowercase email."""
        norm_email = email.strip().lower()
        return self.find_one({"email": norm_email})

    def get_by_google_id(self, google_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve user by verified Google subject ID."""
        if not google_id or not str(google_id).strip():
            return None
        return self.find_one({"google_id": str(google_id).strip()})

    def email_exists(self, email: str) -> bool:
        """Check if an account exists with the given email."""
        norm_email = email.strip().lower()
        return self.exists({"email": norm_email})

    def update(
        self,
        user_id: Union[str, uuid.UUID],
        fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update user fields."""
        payload = dict(fields)
        if "email" in payload:
            payload["email"] = payload["email"].strip().lower()
        return self.update_by_id(user_id, payload)

    def delete(self, user_id: Union[str, uuid.UUID]) -> bool:
        """Delete user by identifier."""
        return self.delete_by_id(user_id)

    def list_users(
        self,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """List users with optional is_active filter and pagination."""
        query = {}
        if is_active is not None:
            query["is_active"] = is_active
        return self.paginate_find(query, sort_by="created_at", sort_order="desc", page=page, page_size=page_size)
