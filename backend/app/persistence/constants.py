"""Constants for dual-engine persistence layer."""

from enum import Enum


class EngineType(str, Enum):
    """Supported persistence engines."""

    POSTGRESQL = "postgresql"
    MONGODB = "mongodb"
