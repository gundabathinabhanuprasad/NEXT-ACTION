"""MongoDB repository for Client documents."""

from typing import Any, Dict, List, Optional, Tuple, Union
import uuid
import re
from pymongo.database import Database
from app.documents.client import ClientDocument
from app.repositories.mongodb_base import BaseMongoRepository


class ClientRepository(BaseMongoRepository):
    """Data access repository for clients collection."""

    def __init__(self, db: Optional[Database] = None):
        super().__init__("clients", db=db)

    def create(self, client_data: Union[ClientDocument, Dict[str, Any]]) -> Dict[str, Any]:
        """Create a new client document."""
        if isinstance(client_data, ClientDocument):
            payload = client_data.to_mongo()
        else:
            payload = dict(client_data)
        return self.insert_doc(payload)

    def get_by_id(self, client_id: Union[str, uuid.UUID]) -> Optional[Dict[str, Any]]:
        """Retrieve client by UUID string identifier."""
        return self.find_by_id(client_id)

    def update(
        self,
        client_id: Union[str, uuid.UUID],
        fields: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        """Update client fields."""
        return self.update_by_id(client_id, fields)

    def delete(self, client_id: Union[str, uuid.UUID]) -> bool:
        """Delete client by identifier."""
        return self.delete_by_id(client_id)

    def list_clients(
        self,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """List clients with optional text search across name, company, email."""
        query: Dict[str, Any] = {}
        if search and search.strip():
            escaped = re.escape(search.strip())
            pattern = {"$regex": escaped, "$options": "i"}
            query["$or"] = [
                {"name": pattern},
                {"company": pattern},
                {"email": pattern},
            ]
        return self.paginate_find(query, sort_by="name", sort_order="asc", page=page, page_size=page_size)
