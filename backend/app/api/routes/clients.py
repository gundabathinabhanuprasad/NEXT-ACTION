"""Clients REST API router with JWT authentication."""

from typing import List, Optional
import uuid
from fastapi import APIRouter, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.client import (
    ClientCreate,
    ClientListResponse,
    ClientResponse,
    ClientUpdate,
)
from app.services.client_service import (
    create_client,
    get_client,
    list_clients,
    update_client,
)

router = APIRouter(prefix="/clients", tags=["Clients"])


@router.post(
    "",
    response_model=ClientResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new client",
)
def create_client_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    payload: ClientCreate,
) -> ClientResponse:
    """Create a new Client / Contact."""
    client = create_client(
        db=db,
        name=payload.name,
        company=payload.company,
        email=payload.email,
        phone=payload.phone,
        notes=payload.notes,
    )
    return ClientResponse.model_validate(client)


@router.get(
    "",
    response_model=ClientListResponse,
    status_code=status.HTTP_200_OK,
    summary="List and search clients",
)
def list_clients_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    search: Optional[str] = Query(default=None, description="Search term for name/company/email"),
    page: int = Query(default=1, ge=1, description="Page number"),
    page_size: int = Query(default=100, ge=1, le=200, description="Items per page"),
) -> ClientListResponse:
    """Retrieve filtered and paginated clients."""
    items, total = list_clients(db=db, search=search, page=page, page_size=page_size)
    return ClientListResponse(
        items=[ClientResponse.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/{client_id}",
    response_model=ClientResponse,
    status_code=status.HTTP_200_OK,
    summary="Get a client by ID",
)
def get_client_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    client_id: uuid.UUID,
) -> ClientResponse:
    """Retrieve client details by ID."""
    client = get_client(db=db, client_id=client_id)
    return ClientResponse.model_validate(client)


@router.patch(
    "/{client_id}",
    response_model=ClientResponse,
    status_code=status.HTTP_200_OK,
    summary="Update a client",
)
def update_client_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    client_id: uuid.UUID,
    payload: ClientUpdate,
) -> ClientResponse:
    """Update existing client attributes."""
    client = update_client(
        db=db,
        client_id=client_id,
        name=payload.name,
        company=payload.company,
        email=payload.email,
        phone=payload.phone,
        notes=payload.notes,
    )
    return ClientResponse.model_validate(client)
