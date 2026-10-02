"""Database session management and engine configuration."""

from typing import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from app.core.config import settings

engine_kwargs = {
    "pool_pre_ping": True,
    "echo": False,
}

if "postgres" in settings.database_url or "postgresql" in settings.database_url:
    engine_kwargs.update(
        {
            "pool_size": settings.DB_POOL_SIZE,
            "max_overflow": settings.DB_MAX_OVERFLOW,
            "pool_timeout": settings.DB_POOL_TIMEOUT,
            "pool_recycle": settings.DB_POOL_RECYCLE,
        }
    )

engine = create_engine(
    settings.database_url,
    **engine_kwargs,
)


SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)


def get_db() -> Generator[Session, None, None]:
    """Yield a database session context and ensure clean closing."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
