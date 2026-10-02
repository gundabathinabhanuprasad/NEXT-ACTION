"""Deterministic record fingerprinting and checksum utilities."""

from datetime import datetime, timezone
from enum import Enum
import hashlib
import json
from typing import Any, Dict, List, Optional
import uuid


def normalize_datetime(dt: datetime) -> str:
    """Normalize datetime to UTC ISO string with millisecond precision (BSON compatible)."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    # Format with 3-digit millisecond precision and trailing Z
    formatted = dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    return formatted


def canonicalize_value(val: Any) -> Any:
    """Recursively canonicalize data types for deterministic serialization."""
    if val is None:
        return None
    if isinstance(val, (str, int, float, bool)):
        return val
    if isinstance(val, uuid.UUID):
        return str(val).lower()
    if isinstance(val, datetime):
        return normalize_datetime(val)
    if isinstance(val, Enum):
        return val.value
    if isinstance(val, dict):
        canonical = {}
        for k in sorted(val.keys()):
            # Ignore internal database metadata fields and normalize id
            if k == "_migration_id":
                continue
            normalized_key = "id" if k == "_id" else k
            canonical[normalized_key] = canonicalize_value(val[k])
        return canonical
    if isinstance(val, (list, tuple, set)):
        return [canonicalize_value(x) for x in val]
    if hasattr(val, "model_dump"):
        return canonicalize_value(val.model_dump())
    if hasattr(val, "__dict__"):
        return canonicalize_value({k: v for k, v in val.__dict__.items() if not k.startswith("_")})
    return str(val)


# Critical business fields to fingerprint per entity type
FINGERPRINT_FIELDS: Dict[str, List[str]] = {
    "users": ["id", "name", "email", "password_hash", "is_active"],
    "user_settings": [
        "id",
        "user_id",
        "timezone",
        "theme",
        "default_task_priority",
        "default_max_attempts",
        "notify_task_assigned",
    ],
    "clients": ["id", "name", "company", "email", "phone", "notes"],
    "workflows": ["id", "name", "description", "is_active"],
    "task_templates": [
        "id",
        "name",
        "description",
        "workflow_id",
        "client_id",
        "priority",
        "max_attempts",
        "is_active",
    ],
    "recurring_tasks": [
        "id",
        "name",
        "description",
        "workflow_id",
        "client_id",
        "priority",
        "recurrence_type",
        "interval",
        "is_active",
    ],
    "tasks": [
        "id",
        "title",
        "description",
        "subject_line",
        "workflow_id",
        "client_id",
        "assigned_user_id",
        "status",
        "priority",
        "due_date",
        "next_action_date",
        "attempt_count",
        "max_attempts",
        "completed_at",
        "reminders",
        "follow_ups",
    ],
    "task_history": [
        "id",
        "task_id",
        "action",
        "old_value",
        "new_value",
        "reason",
        "created_by_user_id",
    ],
    "recurring_task_executions": [
        "id",
        "recurring_task_id",
        "scheduled_for",
        "task_id",
        "status",
    ],
    "notifications": [
        "id",
        "user_id",
        "task_id",
        "type",
        "title",
        "message",
        "dedup_key",
        "is_read",
    ],
    "events": [
        "id",
        "title",
        "description",
        "start_at",
        "end_at",
        "location",
        "task_id",
        "client_id",
    ],
    "refresh_tokens": [
        "id",
        "user_id",
        "token_hash",
        "expires_at",
        "is_revoked",
    ],
}


def filter_fingerprint_dict(entity_type: str, data: Dict[str, Any]) -> Dict[str, Any]:
    """Filter dictionary down to canonical fingerprint fields for entity type."""
    fields = FINGERPRINT_FIELDS.get(entity_type)
    if not fields:
        return data

    filtered = {}
    for f in fields:
        if f in data:
            filtered[f] = data[f]
        elif f == "id" and "_id" in data:
            filtered["id"] = data["_id"]
        elif f in ("reminders", "follow_ups") and f not in data:
            filtered[f] = []
    return filtered


def compute_fingerprint(data: Any, entity_type: Optional[str] = None) -> str:
    """Compute SHA-256 fingerprint over canonicalized JSON representation.

    Args:
        data: Dictionary or object representing the record.
        entity_type: Optional entity collection name to filter relevant fields.

    Returns:
        Hex-encoded SHA-256 digest string.
    """
    raw_dict = data
    if hasattr(data, "model_dump"):
        raw_dict = data.model_dump()
    elif hasattr(data, "__dict__"):
        raw_dict = {k: v for k, v in data.__dict__.items() if not k.startswith("_")}

    if isinstance(raw_dict, dict) and entity_type:
        raw_dict = filter_fingerprint_dict(entity_type, raw_dict)

    canonical = canonicalize_value(raw_dict)
    canonical_json = json.dumps(canonical, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical_json.encode("utf-8")).hexdigest()
