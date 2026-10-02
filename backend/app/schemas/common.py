"""Common response and error schemas."""

from typing import Generic, List, Optional, TypeVar
from pydantic import BaseModel, Field

T = TypeVar("T")


class HealthResponse(BaseModel):
    """Health check response schema."""

    status: str
    database: Optional[str] = None


class ReadinessResponse(BaseModel):
    """Readiness probe response schema."""

    status: str = Field(description="Service readiness status ('ready' or 'not_ready')")
    database: str = Field(description="Database connectivity status ('connected' or 'unavailable')")
    mongodb: Optional[str] = Field(default=None, description="MongoDB connectivity status ('connected', 'unavailable', or None when disabled)")



class ErrorResponse(BaseModel):
    """Standardized error response payload."""

    error: str = Field(description="Machine-readable error code")
    message: str = Field(description="Human-readable error description")


class PaginatedResponse(BaseModel, Generic[T]):
    """Generic paginated response schema."""

    items: List[T]
    total: int
    page: int
    page_size: int
