"""MongoDB repository for UserSettings documents."""

from typing import Any, Dict, Optional, Union
import uuid
from pymongo import ReturnDocument
from pymongo.database import Database
from app.documents.user_settings import UserSettingsDocument
from app.repositories.mongodb_base import BaseMongoRepository


class UserSettingsRepository(BaseMongoRepository):
    """Data access repository for user_settings collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("user_settings", db=db)

    def create(self, settings_data: Union[UserSettingsDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create new user settings document."""
        if isinstance(settings_data, UserSettingsDocument):
            payload = settings_data.to_mongo()
        else:
            payload = dict(settings_data)
        if "user_id" in payload:
            payload["user_id"] = self.to_uuid_str(payload["user_id"])
        return self.insert_doc(payload)

    def get_by_user_id(self, user_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve user settings by associated user_id."""
        uid_str = self.to_uuid_str(user_id)
        return self.find_one({"user_id": uid_str})

    def upsert_for_user(
        self,
        user_id: Union[str, uuid.UUID],
        settings_data: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Atomically insert or update preferences for a user."""
        uid_str = self.to_uuid_str(user_id)
        fields = dict(settings_data)
        doc_id = fields.pop("id", None) or fields.pop("_id", None) or str(uuid.uuid4())
        fields.pop("created_at", None)
        fields["user_id"] = uid_str
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)

        doc = self.collection.find_one_and_update(
            {"user_id": uid_str},
            {
                "$set": fields,
                "$setOnInsert": {
                    "_id": doc_id,
                    "created_at": now,
                },
            },
            upsert=True,
            return_document=ReturnDocument.AFTER,
        )
        return self.format_document(doc)

    def delete_by_user_id(self, user_id: Union[str, uuid.UUID]) -> bool:
        """Delete user settings by user_id."""
        uid_str = self.to_uuid_str(user_id)
        res = self.collection.delete_one({"user_id": uid_str})
        return res.deleted_count > 0
