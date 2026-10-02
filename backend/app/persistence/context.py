"""Persistence engine context management and resolution."""

from contextlib import contextmanager
from contextvars import ContextVar
import logging
from typing import Generator, Optional
from app.core.config import settings
from app.persistence.constants import EngineType

logger = logging.getLogger("nextaction.persistence")

_engine_context_var: ContextVar[Optional[str]] = ContextVar("persistence_engine", default=None)


def get_active_engine(explicit_engine: Optional[str] = None) -> str:
    """Resolve the currently active persistence engine.

    Resolution order:
    1. Explicit engine parameter (if provided)
    2. Context variable override (e.g. for scoped tests)
    3. Global configuration (settings.PERSISTENCE_ENGINE, defaults to 'postgresql')
    """
    if explicit_engine is not None:
        engine = explicit_engine.strip().lower()
    else:
        ctx_engine = _engine_context_var.get()
        if ctx_engine is not None:
            engine = ctx_engine.strip().lower()
        else:
            engine = settings.PERSISTENCE_ENGINE.strip().lower()

    if engine not in (EngineType.POSTGRESQL.value, EngineType.MONGODB.value):
        raise ValueError(
            f"Unsupported persistence engine: '{engine}'. Supported engines are 'postgresql', 'mongodb'."
        )

    if engine == EngineType.MONGODB.value and not settings.MONGODB_ENABLED:
        raise RuntimeError(
            "MongoDB persistence was selected, but MONGODB_ENABLED is False. "
            "Set MONGODB_ENABLED=true in configuration to activate MongoDB persistence."
        )

    return engine


@contextmanager
def override_engine(engine: str) -> Generator[str, None, None]:
    """Context manager to temporarily override the active persistence engine."""
    resolved = engine.strip().lower()
    if resolved not in (EngineType.POSTGRESQL.value, EngineType.MONGODB.value):
        raise ValueError(f"Invalid persistence engine override: '{engine}'")

    token = _engine_context_var.set(resolved)
    try:
        yield resolved
    finally:
        _engine_context_var.reset(token)
