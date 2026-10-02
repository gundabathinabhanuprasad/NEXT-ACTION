"""User service for team listing and profile operations.

Dispatches to active persistence engine (PostgreSQL or MongoDB) via PersistenceGateway.
"""

from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy.orm import Session

from app.persistence.gateway import get_persistence_gateway
from app.services.exceptions import InactiveUserError, UserNotFoundError


def get_user_by_id(
    db: Optional[Session] = None,
    user_id: Union[str, uuid.UUID] = "",
    allow_inactive: bool = False,
) -> Any:
    """Retrieve user by UUID or raise appropriate domain error."""
    return get_persistence_gateway().user_service.get_user_by_id(
        db=db, user_id=user_id, allow_inactive=allow_inactive
    )


def list_users(
    db: Optional[Session] = None,
    search: Optional[str] = None,
    is_active: Optional[bool] = None,
    page: int = 1,
    page_size: int = 50,
) -> Tuple[List[Any], int]:
    """Retrieve filtered and paginated list of users alongside total count."""
    return get_persistence_gateway().user_service.list_users(
        db=db,
        search=search,
        is_active=is_active,
        page=page,
        page_size=page_size,
    )
