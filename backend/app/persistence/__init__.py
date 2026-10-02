"""Persistence layer package providing dual-engine dispatch between PostgreSQL and MongoDB."""

from app.persistence.constants import EngineType
from app.persistence.context import get_active_engine, override_engine
from app.persistence.gateway import PersistenceGateway, get_persistence_gateway

__all__ = [
    "EngineType",
    "get_active_engine",
    "override_engine",
    "PersistenceGateway",
    "get_persistence_gateway",
]
