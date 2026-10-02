"""Distributed and in-process rate limiting for sensitive endpoints."""

from abc import ABC, abstractmethod
from collections import defaultdict
from datetime import datetime, timezone
import logging
import threading
import time
from typing import Dict, List, Optional, Tuple
from fastapi import HTTPException, Request, status
import redis

from app.core.config import settings

logger = logging.getLogger("nextaction.rate_limit")


class BaseRateLimiter(ABC):
    """Abstract base class for rate limiters."""

    @abstractmethod
    def is_rate_limited(
        self,
        key: str,
        max_attempts: int,
        window_seconds: int,
    ) -> Tuple[bool, int]:
        """Check if key has exceeded max_attempts in window_seconds.

        Returns (is_limited, retry_after_seconds).
        """
        pass

    @abstractmethod
    def reset(self) -> None:
        """Clear all stored rate limit records."""
        pass


class InMemoryRateLimiter(BaseRateLimiter):
    """Thread-safe sliding-window rate limiter with memory-bounded automatic eviction."""

    def __init__(self, max_keys: int = 10000):
        self._lock = threading.Lock()
        self._records: Dict[str, List[float]] = defaultdict(list)
        self._max_keys = max_keys

    def is_rate_limited(
        self,
        key: str,
        max_attempts: int,
        window_seconds: int,
    ) -> Tuple[bool, int]:
        """Check if key has exceeded max_attempts in window_seconds."""
        now = datetime.now(timezone.utc).timestamp()
        cutoff = now - window_seconds

        with self._lock:
            # Memory safety: if too many keys, evict stale entries
            if len(self._records) > self._max_keys:
                stale_keys = [
                    k for k, timestamps in self._records.items()
                    if not timestamps or timestamps[-1] < cutoff
                ]
                for k in stale_keys:
                    del self._records[k]

            # Filter out timestamps outside the sliding window
            timestamps = [t for t in self._records[key] if t > cutoff]
            self._records[key] = timestamps

            if len(timestamps) >= max_attempts:
                oldest = timestamps[0]
                retry_after = max(1, int(oldest + window_seconds - now))
                return True, retry_after

            self._records[key].append(now)
            return False, 0

    def reset(self) -> None:
        """Clear all stored rate limit records."""
        with self._lock:
            self._records.clear()


class RedisRateLimiter(BaseRateLimiter):
    """Distributed sliding-window rate limiter backed by Redis with graceful fallback.

    If Redis is unreachable or raises an error, the rate limiter logs a warning
    and gracefully falls back to the embedded InMemoryRateLimiter so traffic is never dropped.
    """

    def __init__(
        self,
        redis_client: Optional[redis.Redis] = None,
        fallback_limiter: Optional[InMemoryRateLimiter] = None,
    ):
        self._redis_client = redis_client
        self._fallback = fallback_limiter or InMemoryRateLimiter()

    def _get_client(self) -> Optional[redis.Redis]:
        """Obtain or initialize the Redis client connection."""
        if self._redis_client is not None:
            return self._redis_client
        try:
            if settings.REDIS_URL:
                self._redis_client = redis.Redis.from_url(
                    settings.REDIS_URL,
                    socket_timeout=settings.REDIS_TIMEOUT_SECONDS,
                    socket_connect_timeout=settings.REDIS_TIMEOUT_SECONDS,
                    decode_responses=True,
                )
            else:
                self._redis_client = redis.Redis(
                    host=settings.REDIS_HOST,
                    port=settings.REDIS_PORT,
                    db=settings.REDIS_DB,
                    password=settings.REDIS_PASSWORD,
                    socket_timeout=settings.REDIS_TIMEOUT_SECONDS,
                    socket_connect_timeout=settings.REDIS_TIMEOUT_SECONDS,
                    decode_responses=True,
                )
            return self._redis_client
        except Exception as exc:
            logger.warning(
                f"Failed to connect to Redis ({exc}). Falling back to in-memory rate limiting."
            )
            return None

    def is_rate_limited(
        self,
        key: str,
        max_attempts: int,
        window_seconds: int,
    ) -> Tuple[bool, int]:
        """Check rate limit using Redis sorted sets with sliding window."""
        client = self._get_client()
        if client is None:
            return self._fallback.is_rate_limited(key, max_attempts, window_seconds)

        now = time.time()
        cutoff = now - window_seconds
        redis_key = f"ratelimit:{key}"

        try:
            pipe = client.pipeline()
            # 1. Purge entries older than sliding window
            pipe.zremrangebyscore(redis_key, 0, cutoff)
            # 2. Count current elements in window
            pipe.zcard(redis_key)
            # 3. Retrieve oldest element in window for Retry-After calculation
            pipe.zrange(redis_key, 0, 0, withscores=True)
            results = pipe.execute()

            current_count = results[1]
            oldest_entries = results[2]

            if current_count >= max_attempts:
                if oldest_entries:
                    oldest_ts = float(oldest_entries[0][1])
                    retry_after = max(1, int(oldest_ts + window_seconds - now))
                else:
                    retry_after = window_seconds
                return True, retry_after

            # Record this request attempt and refresh key TTL
            pipe2 = client.pipeline()
            pipe2.zadd(redis_key, {str(now): now})
            pipe2.expire(redis_key, window_seconds + 5)
            pipe2.execute()

            return False, 0
        except Exception as exc:
            logger.warning(
                f"Redis rate limiting operation failed ({exc}). Gracefully falling back to in-memory limiter."
            )
            return self._fallback.is_rate_limited(key, max_attempts, window_seconds)

    def reset(self) -> None:
        """Clear rate limit keys in Redis and reset fallback."""
        self._fallback.reset()
        client = self._get_client()
        if client is not None:
            try:
                keys = client.keys("ratelimit:*")
                if keys:
                    client.delete(*keys)
            except Exception as exc:
                logger.warning(f"Failed to reset Redis rate limit keys: {exc}")


def get_rate_limiter() -> BaseRateLimiter:
    """Factory creating configured rate limiter backend."""
    if settings.RATE_LIMIT_BACKEND.lower() == "redis":
        return RedisRateLimiter()
    return InMemoryRateLimiter()


limiter = get_rate_limiter()


def check_auth_rate_limit(
    request: Request,
    action: str = "auth",
) -> None:
    """FastAPI dependency to rate limit sensitive authentication routes.

    Uses client IP address to scope requests.
    """
    if not settings.RATE_LIMIT_ENABLED or settings.ENVIRONMENT == "test":
        return

    # Extract client IP; handle forwarded headers if present
    client_ip = "127.0.0.1"
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        client_ip = forwarded.split(",")[0].strip()
    elif request.client and request.client.host:
        client_ip = request.client.host

    key = f"{action}:{client_ip}"
    is_limited, retry_after = limiter.is_rate_limited(
        key=key,
        max_attempts=settings.RATE_LIMIT_MAX_ATTEMPTS,
        window_seconds=settings.RATE_LIMIT_WINDOW_SECONDS,
    )

    if is_limited:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Rate limit exceeded. Please wait {retry_after} seconds before trying again.",
            headers={"Retry-After": str(retry_after)},
        )
