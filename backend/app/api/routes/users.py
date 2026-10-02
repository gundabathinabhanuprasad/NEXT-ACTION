"""User and team member API endpoints."""

from typing import Optional
import uuid
from fastapi import APIRouter, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.auth import UserListResponse, UserResponse
from app.services.user_service import get_user_by_id, list_users

router = APIRouter(prefix="/users", tags=["Users"])


@router.get(
    "",
    response_model=UserListResponse,
    status_code=status.HTTP_200_OK,
    summary="List team users",
)
def list_users_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    search: Optional[str] = Query(default=None, description="Filter users by name or email"),
    is_active: Optional[bool] = Query(default=None, description="Filter by active status"),
    page: int = Query(default=1, ge=1, description="Page number"),
    page_size: int = Query(default=50, ge=1, le=100, description="Items per page"),
) -> UserListResponse:
    """List team users with safe public fields only. Requires authenticated JWT."""
    items, total = list_users(
        db=db,
        search=search,
        is_active=is_active,
        page=page,
        page_size=page_size,
    )
    return UserListResponse(
        items=[UserResponse.model_validate(item) for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/{user_id}",
    response_model=UserResponse,
    status_code=status.HTTP_200_OK,
    summary="Get user by ID",
)
def get_user_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    user_id: uuid.UUID,
) -> UserResponse:
    """Retrieve safe user profile details by ID."""
    user = get_user_by_id(db=db, user_id=user_id, allow_inactive=True)
    return UserResponse.model_validate(user)
