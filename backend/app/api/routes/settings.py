"""Settings and User Personalization API routes."""

from fastapi import APIRouter, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.settings import UserSettingsResponse, UserSettingsUpdate
from app.services.settings_service import (
    get_user_settings,
    reset_user_settings,
    update_user_settings,
)

router = APIRouter(prefix="/settings", tags=["Settings & Personalization"])


@router.get(
    "",
    response_model=UserSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Get current user settings and preferences",
)
def get_settings_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> UserSettingsResponse:
    """Retrieve personal configuration, defaults, regional, and notification preferences.

    Actor identity is derived exclusively from the verified JWT.
    Auto-provisions defaults if no record exists yet.
    """
    settings = get_user_settings(db, current_user.id)
    return UserSettingsResponse.model_validate(settings)


@router.patch(
    "",
    response_model=UserSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Update current user settings and preferences",
)
def update_settings_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    payload: UserSettingsUpdate,
) -> UserSettingsResponse:
    """Partial update of user settings.

    Only explicitly supplied fields are updated; unspecified preferences are preserved.
    """
    settings = update_user_settings(db, current_user.id, payload)
    return UserSettingsResponse.model_validate(settings)


@router.post(
    "/reset",
    response_model=UserSettingsResponse,
    status_code=status.HTTP_200_OK,
    summary="Reset user settings to system defaults",
)
def reset_settings_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
) -> UserSettingsResponse:
    """Reset all user preferences back to system default values."""
    settings = reset_user_settings(db, current_user.id)
    return UserSettingsResponse.model_validate(settings)
