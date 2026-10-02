"""Generate secure .env.prod file for production deployment without exposing secrets."""

import secrets
import json

jwt_sec = secrets.token_hex(32)
db_pass = secrets.token_urlsafe(24)
redis_pass = secrets.token_urlsafe(24)

env_content = f"""# NextAction Production Environment Configuration (v1.0.0 Release Candidate)
ENVIRONMENT=production
LOG_LEVEL=INFO
DOCS_ENABLED=false

POSTGRES_SERVER=postgres
POSTGRES_PORT=5432
POSTGRES_USER=nextaction_admin
POSTGRES_PASSWORD={db_pass}
POSTGRES_DB=nextaction_prod

DB_POOL_SIZE=20
DB_MAX_OVERFLOW=40
DB_POOL_TIMEOUT=30
DB_POOL_RECYCLE=1800
DB_SSLMODE=

JWT_SECRET_KEY={jwt_sec}
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=7

CORS_ORIGINS=["https://app.nextaction.io","https://localhost","https://127.0.0.1","http://localhost:8080"]
TRUSTED_HOSTS=["localhost","127.0.0.1","app.nextaction.io","nextaction_prod_proxy","nextaction_prod_backend"]

RATE_LIMIT_ENABLED=true
RATE_LIMIT_BACKEND=redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD={redis_pass}
REDIS_TIMEOUT_SECONDS=2.0
"""

with open(".env.prod", "w", encoding="utf-8") as f:
    f.write(env_content)

print("SUCCESS: .env.prod generated securely.")
