"""FastAPI API package."""

from app.api.dependencies import DatabaseDep
from app.api.exception_handlers import register_exception_handlers
from app.api.router import api_v1_router

__all__ = ["api_v1_router", "DatabaseDep", "register_exception_handlers"]
