"""Client service encapsulating Client CRUD operations.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import ClientNotFoundError


def get_client(db: Optional[Session] = None, client_id: Union[str, uuid.UUID] = "") -> Any:
    """Retrieve a client by ID or raise ClientNotFoundError."""
    return get_persistence_gateway().client_service.get_client(db=db, client_id=client_id)


def create_client(
    db: Optional[Session] = None,
    name: str = "",
    company: Optional[str] = None,
    email: Optional[str] = None,
    phone: Optional[str] = None,
    notes: Optional[str] = None,
) -> Any:
    """Create and persist a new Client entity."""
    return get_persistence_gateway().client_service.create_client(
        db=db,
        name=name,
        company=company,
        email=email,
        phone=phone,
        notes=notes,
    )


def update_client(
    db: Optional[Session] = None,
    client_id: Union[str, uuid.UUID] = "",
    name: Optional[str] = None,
    company: Optional[str] = None,
    email: Optional[str] = None,
    phone: Optional[str] = None,
    notes: Optional[str] = None,
) -> Any:
    """Update existing client attributes."""
    return get_persistence_gateway().client_service.update_client(
        db=db,
        client_id=client_id,
        name=name,
        company=company,
        email=email,
        phone=phone,
        notes=notes,
    )


def delete_client(db: Optional[Session] = None, client_id: Union[str, uuid.UUID] = "") -> bool:
    """Delete existing client."""
    return get_persistence_gateway().client_service.delete_client(db=db, client_id=client_id)


def list_clients(
    db: Optional[Session] = None,
    search: Optional[str] = None,
    page: int = 1,
    page_size: int = 100,
) -> Tuple[List[Any], int]:
    """Retrieve filtered and paginated list of clients."""
    return get_persistence_gateway().client_service.list_clients(
        db=db,
        search=search,
        page=page,
        page_size=page_size,
    )
