"""Base MongoDB repository providing core primitives, pagination, UUID mapping, and UTC datetime helpers."""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
from pymongo import ASCENDING, DESCENDING, ReturnDocument
from pymongo.collection import Collection
from pymongo.database import Database

from app.db.mongodb import get_mongo_database


class BaseMongoRepository:
    """Foundational data access class for MongoDB collections."""

    def __init__(self, collection_name: str, db: Optional[Database] = None):
        self.collection_name = collection_name
        self._db = db

    @property
    def db(self) -> Database:
        """Retrieve the associated MongoDB database instance."""
        database = self._db if self._db is not None else get_mongo_database()
        if database is None:
            raise RuntimeError(
                f"Cannot access collection '{self.collection_name}': MongoDB database is not initialized."
            )
        return database

    @property
    def collection(self) -> Collection:
        """Retrieve the target MongoDB collection."""
        return self.db[self.collection_name]

    @staticmethod
    def to_uuid_str(val: Union[str, uuid.UUID]) -> str:
        """Standardize UUID representation to hyphenated lowercase string for cross-engine parity."""
        if isinstance(val, uuid.UUID):
            return str(val)
        try:
            return str(uuid.UUID(str(val)))
        except ValueError:
            return str(val)

    @staticmethod
    def ensure_utc(dt: Optional[datetime]) -> Optional[datetime]:
        """Ensure a datetime instance is timezone-aware UTC."""
        if dt is None:
            return None
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)

    @staticmethod
    def format_document(doc: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """Normalize BSON document to standard domain representation, mapping _id to string id."""
        if doc is None:
            return None
        formatted = dict(doc)
        if "_id" in formatted:
            formatted["id"] = str(formatted["_id"])
        return formatted

    def count(self, filter_query: Optional[Dict[str, Any]] = None) -> int:
        """Count documents matching the specified filter."""
        query = filter_query or {}
        return self.collection.count_documents(query)

    def exists(self, filter_query: Dict[str, Any]) -> bool:
        """Check if at least one document matches the query filter."""
        return self.collection.count_documents(filter_query, limit=1) > 0

    def find_by_id(self, id_val: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve a single document by its UUID string identifier."""
        id_str = self.to_uuid_str(id_val)
        doc = self.collection.find_one({"_id": id_str})
        return self.format_document(doc)

    def find_one(self, filter_query: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Retrieve a single document matching the specified criteria."""
        doc = self.collection.find_one(filter_query)
        return self.format_document(doc)

    def find_many(
        self,
        filter_query: Optional[Dict[str, Any]] = None,
        sort_by: str = "created_at",
        sort_order: str = "desc",
        limit: Optional[int] = None,
        skip: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """Retrieve a list of documents matching the specified criteria."""
        query = filter_query or {}
        mongo_order = DESCENDING if sort_order.lower() == "desc" else ASCENDING
        cursor = self.collection.find(query).sort(sort_by, mongo_order)
        if skip is not None and skip > 0:
            cursor = cursor.skip(skip)
        if limit is not None:
            cursor = cursor.limit(limit)
        return [self.format_document(doc) for doc in cursor if doc is not None]

    def insert_doc(self, doc_data: Dict[str, Any]) -> Dict[str, Any]:
        """Insert a document, ensuring _id is set and returning formatted result."""
        payload = dict(doc_data)
        if "_id" not in payload and "id" in payload:
            payload["_id"] = self.to_uuid_str(payload["id"])
        elif "_id" not in payload:
            payload["_id"] = str(uuid.uuid4())
        else:
            payload["_id"] = self.to_uuid_str(payload["_id"])

        if "id" not in payload:
            payload["id"] = payload["_id"]

        now = self.ensure_utc(datetime.now(timezone.utc))
        if "created_at" not in payload or payload["created_at"] is None:
            payload["created_at"] = now
        else:
            payload["created_at"] = self.ensure_utc(payload["created_at"])

        if "updated_at" not in payload or payload["updated_at"] is None:
            payload["updated_at"] = now
        else:
            payload["updated_at"] = self.ensure_utc(payload["updated_at"])

        self.collection.insert_one(payload)
        return self.format_document(payload)

    def update_by_id(
        self,
        id_val: Union[str, uuid.UUID],
        update_fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update fields of an existing document by its identifier and touch updated_at."""
        id_str = self.to_uuid_str(id_val)
        fields = dict(update_fields)
        fields["updated_at"] = self.ensure_utc(datetime.now(timezone.utc))

        doc = self.collection.find_one_and_update(
            {"_id": id_str},
            {"$set": fields},
            return_document=ReturnDocument.AFTER,
        )
        return self.format_document(doc)

    def delete_by_id(self, id_val: Union[str, uuid.UUID]) -> bool:
        """Delete a document by identifier, returning True if a document was deleted."""
        id_str = self.to_uuid_str(id_val)
        result = self.collection.delete_one({"_id": id_str})
        return result.deleted_count > 0

    def delete_many(self, filter_query: Dict[str, Any]) -> int:
        """Delete documents matching criteria, returning count of deleted documents."""
        result = self.collection.delete_many(filter_query)
        return result.deleted_count

    def paginate_find(
        self,
        filter_query: Optional[Dict[str, Any]] = None,
        sort_by: str = "created_at",
        sort_order: str = "desc",
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """Perform paginated document retrieval with total count calculation."""
        query = filter_query or {}
        total = self.collection.count_documents(query)

        mongo_order = DESCENDING if sort_order.lower() == "desc" else ASCENDING
        skip_count = max(0, (page - 1) * page_size)

        cursor = (
            self.collection.find(query)
            .sort(sort_by, mongo_order)
            .skip(skip_count)
            .limit(page_size)
        )

        items = [self.format_document(doc) for doc in cursor if doc is not None]
        return items, total

    def paginate(
        self,
        query: Optional[Dict[str, Any]] = None,
        page: int = 1,
        page_size: int = 20,
        sort: Optional[Any] = None,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """Perform paginated document retrieval with total count calculation supporting list of sort tuples."""
        filter_query = query or {}
        total = self.collection.count_documents(filter_query)

        skip_count = max(0, (page - 1) * page_size)
        cursor = self.collection.find(filter_query).skip(skip_count).limit(page_size)

        if sort is not None:
            cursor = cursor.sort(sort)
        else:
            cursor = cursor.sort("created_at", DESCENDING)

        items = [self.format_document(doc) for doc in cursor if doc is not None]
        return items, total
