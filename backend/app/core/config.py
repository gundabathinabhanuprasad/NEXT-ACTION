"""Application settings and environment configuration."""

from typing import Any, Optional, Union
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings schema."""

    PROJECT_NAME: str = "NextAction API"
    VERSION: str = "1.0.0"
    DESCRIPTION: str = "Backend API for the NextAction task and follow-up management system."
    API_V1_STR: str = "/api/v1"

    # Server Host & Port binding
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # Database configuration
    DATABASE_URL: Optional[str] = None

    POSTGRES_SERVER: str = "localhost"
    POSTGRES_PORT: int = 5432
    POSTGRES_USER: str = "nextaction"
    POSTGRES_PASSWORD: str = "nextaction_dev"
    POSTGRES_DB: str = "nextaction"

    # Authentication & JWT Configuration
    JWT_SECRET_KEY: str = "dev_secret_key_change_in_production_nextaction_jwt_auth_key"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # CORS Configuration for development clients
    CORS_ORIGINS: Union[list[str], str] = [
        "http://localhost",
        "http://localhost:8000",
        "http://localhost:8080",
        "http://localhost:3000",
        "http://localhost:5000",
        "http://127.0.0.1",
        "http://127.0.0.1:8000",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5000",
    ]
    CORS_ORIGIN_REGEX: Optional[str] = r"^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$"

    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"
    DOCS_ENABLED: bool = True

    # Database Pool Settings
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20
    DB_POOL_TIMEOUT: int = 30
    DB_POOL_RECYCLE: int = 1800

    # API & Performance Guardrails
    REQUEST_TIMEOUT_SECONDS: int = 30
    MAX_PAGE_SIZE: int = 100
    MAX_EXPORT_LIMIT: int = 5000

    # Rate Limiting
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_BACKEND: str = "memory"  # 'memory' or 'redis'
    RATE_LIMIT_MAX_ATTEMPTS: int = 300
    RATE_LIMIT_WINDOW_SECONDS: int = 60

    # Redis Configuration (for distributed rate limiting)
    REDIS_URL: Optional[str] = None
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 0
    REDIS_PASSWORD: Optional[str] = None
    REDIS_TIMEOUT_SECONDS: float = 2.0

    # Trusted Hosts & Infrastructure URLs
    TRUSTED_HOSTS: Union[list[str], str] = ["localhost", "127.0.0.1", "nextaction.local", "testserver"]
    FRONTEND_URL: str = "http://localhost:8080"
    API_BASE_URL: str = "http://localhost:8000"

    # Refresh Token Lifetime (Days)
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Managed Database SSL
    DB_SSLMODE: Optional[str] = None

    # Persistence Engine Selector: 'postgresql' (default) or 'mongodb'
    PERSISTENCE_ENGINE: str = "postgresql"

    # MongoDB Configuration (Dual-Engine Scaffolding)
    MONGODB_ENABLED: bool = False
    MONGODB_URI: Optional[str] = None
    MONGODB_DATABASE: str = "nextaction"
    MONGODB_MIN_POOL_SIZE: int = 1
    MONGODB_MAX_POOL_SIZE: int = 50
    MONGODB_SERVER_SELECTION_TIMEOUT_MS: int = 5000
    MONGODB_CONNECT_TIMEOUT_MS: int = 5000

    # Controlled Dual-Write Scaffolding (Phase 31)
    MONGODB_DUAL_WRITE_ENABLED: bool = False

    # Google OAuth Configuration
    GOOGLE_CLIENT_ID: Optional[str] = None
    GOOGLE_CLIENT_IDS: Union[list[str], str] = []

    def get_google_client_ids(self) -> list[str]:
        """Return unified list of authorized Google OAuth Client IDs."""
        ids: list[str] = []
        if self.GOOGLE_CLIENT_ID and self.GOOGLE_CLIENT_ID.strip():
            ids.append(self.GOOGLE_CLIENT_ID.strip())
        if isinstance(self.GOOGLE_CLIENT_IDS, list):
            for item in self.GOOGLE_CLIENT_IDS:
                cleaned = str(item).strip()
                if cleaned and cleaned not in ids:
                    ids.append(cleaned)
        return ids

    @field_validator("CORS_ORIGINS", "TRUSTED_HOSTS", "GOOGLE_CLIENT_IDS", mode="before")
    @classmethod
    def parse_string_list(cls, v: Any) -> list[str]:
        """Parse list of strings from JSON list, Python list, or comma-separated string."""
        if isinstance(v, str):
            v = v.strip()
            if not v:
                return []
            if v.startswith("[") and v.endswith("]"):
                import json, ast
                try:
                    return json.loads(v)
                except Exception:
                    try:
                        return ast.literal_eval(v)
                    except Exception:
                        items = v[1:-1].split(",")
                        return [item.strip().strip("'\"") for item in items if item.strip()]
            return [item.strip() for item in v.split(",") if item.strip()]
        if isinstance(v, (list, tuple)):
            return [str(item).strip() for item in v if str(item).strip()]
        return v

    @field_validator("PERSISTENCE_ENGINE")
    @classmethod
    def validate_persistence_engine(cls, v: str) -> str:
        """Validate configured persistence engine selector."""
        engine = v.strip().lower()
        if engine not in ("postgresql", "mongodb"):
            raise ValueError(
                f"Invalid PERSISTENCE_ENGINE: '{v}'. Supported values are 'postgresql', 'mongodb'."
            )
        return engine

    @model_validator(mode="after")
    def validate_engine_and_mongodb_coupling(self) -> "Settings":
        """Ensure MongoDB is enabled and configured when selected as active persistence engine or dual-write."""
        if self.PERSISTENCE_ENGINE == "mongodb":
            if not self.MONGODB_ENABLED:
                raise ValueError(
                    "Invalid configuration: PERSISTENCE_ENGINE is set to 'mongodb', "
                    "but MONGODB_ENABLED is False. Set MONGODB_ENABLED=true to enable MongoDB persistence."
                )
            if not self.MONGODB_URI or not self.MONGODB_URI.strip():
                raise ValueError(
                    "Invalid configuration: PERSISTENCE_ENGINE is set to 'mongodb', "
                    "but MONGODB_URI is empty or not configured."
                )
        if self.MONGODB_DUAL_WRITE_ENABLED:
            if not self.MONGODB_ENABLED:
                raise ValueError(
                    "Invalid configuration: MONGODB_DUAL_WRITE_ENABLED is set to True, "
                    "but MONGODB_ENABLED is False. Set MONGODB_ENABLED=true to enable MongoDB dual-write."
                )
            if not self.MONGODB_URI or not self.MONGODB_URI.strip():
                raise ValueError(
                    "Invalid configuration: MONGODB_DUAL_WRITE_ENABLED is set to True, "
                    "but MONGODB_URI is empty or not configured."
                )
        return self

    @property
    def database_url(self) -> str:
        """Construct or return the database connection URL."""
        if self.DATABASE_URL:
            base_url = self.DATABASE_URL
        else:
            base_url = (
                f"postgresql+psycopg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
                f"@{self.POSTGRES_SERVER}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
            )
        if self.DB_SSLMODE and "sslmode=" not in base_url and not base_url.startswith("sqlite"):
            delimiter = "&" if "?" in base_url else "?"
            base_url = f"{base_url}{delimiter}sslmode={self.DB_SSLMODE}"
        return base_url

    @property
    def database_connection_url(self) -> str:
        """Alias for database_url."""
        return self.database_url

    def validate_production_security(self) -> None:
        """Validate critical security and operational configurations when running in production."""
        if self.ENVIRONMENT.lower() == "production":
            insecure_markers = ["dev_secret", "change_in_production", "nextaction_jwt_auth_key"]
            if any(marker in self.JWT_SECRET_KEY for marker in insecure_markers):
                raise ValueError(
                    "FATAL SECURITY VIOLATION: Production environment cannot use default or development JWT_SECRET_KEY. "
                    "Configure a high-entropy secret via JWT_SECRET_KEY environment variable."
                )
            if len(self.JWT_SECRET_KEY) < 32:
                raise ValueError(
                    "FATAL SECURITY VIOLATION: Production JWT_SECRET_KEY must be at least 32 characters long."
                )
            if "*" in self.CORS_ORIGINS:
                raise ValueError(
                    "FATAL SECURITY VIOLATION: Production CORS cannot include wildcard '*' when credentials are supported."
                )
            if "*" in self.TRUSTED_HOSTS:
                raise ValueError(
                    "FATAL SECURITY VIOLATION: Production TRUSTED_HOSTS cannot include wildcard '*'."
                )
            if self.PERSISTENCE_ENGINE != "mongodb" or self.MONGODB_DUAL_WRITE_ENABLED:
                if self.POSTGRES_PASSWORD in ("nextaction_dev", ""):
                    raise ValueError(
                        "FATAL SECURITY VIOLATION: Production environment cannot use default or empty POSTGRES_PASSWORD. "
                        "Configure a secure database password via POSTGRES_PASSWORD environment variable."
                    )
            if self.MONGODB_ENABLED and (not self.MONGODB_URI or not self.MONGODB_URI.strip()):
                raise ValueError(
                    "FATAL SECURITY VIOLATION: MONGODB_ENABLED is True in production, but MONGODB_URI is not configured. "
                    "Configure a secure MongoDB connection URI via MONGODB_URI environment variable."
                )
            if self.PERSISTENCE_ENGINE == "mongodb":
                if not self.MONGODB_ENABLED:
                    raise ValueError(
                        "FATAL SECURITY VIOLATION: PERSISTENCE_ENGINE is 'mongodb' in production, but MONGODB_ENABLED is False."
                    )
                if not self.MONGODB_URI or not self.MONGODB_URI.strip():
                    raise ValueError(
                        "FATAL SECURITY VIOLATION: PERSISTENCE_ENGINE is 'mongodb' in production, but MONGODB_URI is not configured."
                    )

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


def redact_mongo_uri(uri: Optional[str]) -> str:
    """Return a sanitized version of the MongoDB URI with passwords/credentials redacted."""
    if not uri:
        return ""
    import re
    # Match mongodb://user:pass@host or mongodb+srv://user:pass@host (handles passwords with @ or special chars)
    return re.sub(r"://([^:@/]+):.*@([^/@]+)", r"://\1:***@\2", uri)


settings = Settings()
settings.validate_production_security()

