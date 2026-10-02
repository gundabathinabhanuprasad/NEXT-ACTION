"""MongoDB Client Service implementation."""

from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.documents.client import ClientDocument
from app.repositories import ClientRepository
from app.services.exceptions import ClientNotFoundError


class MongoClientService:
    """Client service implementation using MongoDB collections and repositories."""

    def __init__(self, client_repo: Optional[ClientRepository] = None):
        self.client_repo = client_repo or ClientRepository()

    def _to_doc(self, raw_data: Optional[Dict[str, Any]]) -> ClientDocument:
        if raw_data is None:
            raise ClientNotFoundError("Unknown")
        return ClientDocument.model_validate(raw_data)

    def create_client(
        self,
        db: Any = None,
        name: str = "",
        company: Optional[str] = None,
        email: Optional[str] = None,
        phone: Optional[str] = None,
        notes: Optional[str] = None,
        address: Optional[str] = None,
    ) -> ClientDocument:
        """Create a new client document."""
        doc = ClientDocument(
            name=name.strip(),
            company=company.strip() if company else None,
            email=email.strip().lower() if email else None,
            phone=phone.strip() if phone else None,
            notes=notes,
        )
        saved = self.client_repo.create(doc)
        return self._to_doc(saved)

    def get_client(
        self,
        db: Any = None,
        client_id: Union[str, uuid.UUID] = "",
    ) -> ClientDocument:
        """Retrieve client by UUID string or raise ClientNotFoundError."""
        client_dict = self.client_repo.get_by_id(client_id)
        if not client_dict:
            raise ClientNotFoundError(client_id)
        return self._to_doc(client_dict)

    def list_clients(
        self,
        db: Any = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 100,
    ) -> Tuple[List[ClientDocument], int]:
        """List clients with text search and pagination."""
        items, total = self.client_repo.list_clients(search=search, page=page, page_size=page_size)
        return [self._to_doc(i) for i in items], total

    def update_client(
        self,
        db: Any = None,
        client_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        company: Optional[str] = None,
        email: Optional[str] = None,
        phone: Optional[str] = None,
        notes: Optional[str] = None,
        address: Optional[str] = None,
    ) -> ClientDocument:
        """Update client fields."""
        client = self.get_client(client_id=client_id)
        updates: Dict[str, Any] = {}
        if name is not None:
            updates["name"] = name.strip()
        if company is not None:
            updates["company"] = company.strip() if company else None
        if email is not None:
            updates["email"] = email.strip().lower() if email else None
        if phone is not None:
            updates["phone"] = phone.strip() if phone else None
        if notes is not None:
            updates["notes"] = notes

        if updates:
            updated = self.client_repo.update(client.id, updates)
            return self._to_doc(updated)
        return client

    def delete_client(
        self,
        db: Any = None,
        client_id: Union[str, uuid.UUID] = "",
    ) -> bool:
        """Delete client by identifier."""
        self.get_client(client_id=client_id)
        return self.client_repo.delete(client_id)
