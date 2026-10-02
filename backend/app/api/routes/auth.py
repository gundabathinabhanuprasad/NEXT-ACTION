from fastapi import APIRouter, Depends, Request, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.core.rate_limit import check_auth_rate_limit
from app.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    LogoutRequest,
    RefreshTokenRequest,
    TokenResponse,
    UserCreate,
    UserResponse,
)
from app.services.auth_service import (
    authenticate_user,
    change_password,
    register_user,
    revoke_refresh_token,
    rotate_refresh_token,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user",
    dependencies=[Depends(check_auth_rate_limit)],
)
def register_endpoint(
    db: DatabaseDep,
    payload: UserCreate,
) -> UserResponse:
    """Register a new user account with secure password hashing."""
    user = register_user(
        db=db,
        name=payload.name,
        email=payload.email,
        password=payload.password,
    )
    return UserResponse.model_validate(user)


@router.post(
    "/login",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="User login and JWT token issuance",
    dependencies=[Depends(check_auth_rate_limit)],
)
def login_endpoint(
    request: Request,
    db: DatabaseDep,
    payload: LoginRequest,
) -> TokenResponse:
    """Authenticate email & password credentials and return a signed JWT access token and refresh token."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    user, token, expires_in, refresh_token = authenticate_user(
        db=db,
        email=payload.email,
        password=payload.password,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        expires_in=expires_in,
        refresh_token=refresh_token,
    )


@router.post(
    "/refresh",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Rotate refresh token and issue new access token",
    dependencies=[Depends(check_auth_rate_limit)],
)
def refresh_endpoint(
    request: Request,
    db: DatabaseDep,
    payload: RefreshTokenRequest,
) -> TokenResponse:
    """Rotate an active refresh token with replay-attack detection and return new tokens."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    user, new_token, expires_in, new_refresh_token = rotate_refresh_token(
        db=db,
        raw_token=payload.refresh_token,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return TokenResponse(
        access_token=new_token,
        token_type="bearer",
        expires_in=expires_in,
        refresh_token=new_refresh_token,
    )


@router.post(
    "/logout",
    status_code=status.HTTP_200_OK,
    summary="User logout and refresh token revocation",
)
def logout_endpoint(
    db: DatabaseDep,
    payload: LogoutRequest,
) -> dict[str, str]:
    """Revoke user refresh token upon logout."""
    if payload.refresh_token:
        revoke_refresh_token(db=db, raw_token=payload.refresh_token)
    return {"message": "Logged out successfully."}


@router.get(
    "/me",
    response_model=UserResponse,
    status_code=status.HTTP_200_OK,
    summary="Get current authenticated user",
)
def get_current_user_endpoint(
    current_user: CurrentUserDep,
) -> UserResponse:
    """Retrieve identity of the currently authenticated user from JWT token."""
    return UserResponse.model_validate(current_user)


@router.post(
    "/change-password",
    response_model=UserResponse,
    status_code=status.HTTP_200_OK,
    summary="Change user password",
)
def change_password_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    payload: ChangePasswordRequest,
) -> UserResponse:
    """Securely change authenticated user's password requiring current password verification."""
    user = change_password(
        db=db,
        user=current_user,
        current_password=payload.current_password,
        new_password=payload.new_password,
    )
    return UserResponse.model_validate(user)
