"""MongoDB Follow-Up Service implementation using embedded task subdocuments."""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Union
import uuid

from app.documents.common import utcnow
from app.documents.task import FollowUpSubDocument
from app.repositories import TaskRepository
from app.services.exceptions import FollowUpNotFoundError, TaskNotFoundError


def _safe_sort_key(dt: Optional[datetime]) -> datetime:
    """Return a timezone-aware UTC datetime for safe cross-comparison and sorting."""
    if dt is None:
        return datetime.min.replace(tzinfo=timezone.utc)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def _safe_parse_follow_up(raw: Any) -> Optional[FollowUpSubDocument]:
    """Safely validate a raw MongoDB subdocument into a FollowUpSubDocument."""
    if not isinstance(raw, dict):
        return None
    try:
        data = dict(raw)
        if not data.get("scheduled_at"):
            data["scheduled_at"] = utcnow()
        return FollowUpSubDocument.model_validate(data)
    except Exception:
        return None


class MongoFollowUpService:
    """Follow-up service implementation using embedded task follow-ups."""

    def __init__(self, task_repo: Optional[TaskRepository] = None):
        self.task_repo = task_repo or TaskRepository()

    def create_follow_up(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        scheduled_at: Optional[datetime] = None,
        notes: Optional[str] = None,
    ) -> FollowUpSubDocument:
        """Create an embedded follow-up within target task."""
        task = self.task_repo.get_by_id(task_id)
        if not task:
            raise TaskNotFoundError(task_id)

        follow_up = FollowUpSubDocument(
            task_id=str(task_id),
            scheduled_at=scheduled_at or utcnow(),
            notes=notes.strip() if notes else None,
        )
        self.task_repo.add_follow_up(task_id, follow_up)
        return follow_up

    def get_follow_up(
        self,
        db: Any = None,
        follow_up_id: Union[str, uuid.UUID] = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> FollowUpSubDocument:
        """Look up follow-up subdocument by ID."""
        fid_str = str(follow_up_id)
        if task_id is not None:
            task = self.task_repo.get_by_id(task_id)
        else:
            task = self.task_repo.find_one({"follow_ups.id": fid_str})

        if not task:
            raise FollowUpNotFoundError(follow_up_id)

        for fu in (task.get("follow_ups") or []):
            if isinstance(fu, dict) and fu.get("id") == fid_str:
                parsed = _safe_parse_follow_up(fu)
                if parsed:
                    return parsed

        raise FollowUpNotFoundError(follow_up_id)

    def list_task_follow_ups(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
    ) -> List[FollowUpSubDocument]:
        """List embedded follow-ups for task."""
        task = self.task_repo.get_by_id(task_id)
        if not task:
            raise TaskNotFoundError(task_id)
        items = []
        tid_str = str(task_id)
        for f in (task.get("follow_ups") or []):
            if isinstance(f, dict) and not f.get("task_id"):
                f["task_id"] = tid_str
            parsed = _safe_parse_follow_up(f)
            if parsed:
                if parsed.task_id is None:
                    parsed.task_id = tid_str
                items.append(parsed)
        return items

    def list_due_follow_ups(
        self,
        db: Any = None,
        as_of: Optional[datetime] = None,
    ) -> List[FollowUpSubDocument]:
        """List uncompleted follow-ups scheduled on or before as_of across all tasks."""
        target_time = as_of or datetime.now(timezone.utc)
        tasks = self.task_repo.collection.find(
            {"follow_ups": {"$elemMatch": {"completed_at": None, "scheduled_at": {"$lte": target_time}}}},
            projection={"follow_ups": 1, "_id": 1},
        )
        due: List[FollowUpSubDocument] = []
        for t in tasks:
            t_id = str(t.get("_id", ""))
            for fu in (t.get("follow_ups") or []):
                if isinstance(fu, dict) and not fu.get("task_id"):
                    fu["task_id"] = t_id
                parsed = _safe_parse_follow_up(fu)
                if not parsed:
                    continue
                if parsed.task_id is None:
                    parsed.task_id = t_id
                sched = _safe_sort_key(parsed.scheduled_at)
                target_tz = _safe_sort_key(target_time)
                if parsed.completed_at is None and sched <= target_tz:
                    due.append(parsed)
        due.sort(key=lambda x: _safe_sort_key(x.scheduled_at))
        return due

    def list_follow_ups(
        self,
        db: Any = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        is_completed: Optional[bool] = None,
    ) -> List[FollowUpSubDocument]:
        """List follow-ups filtered by task and completion status."""
        if task_id is not None:
            task = self.task_repo.get_by_id(task_id)
            if not task:
                return []
            follow_ups = []
            tid_str = str(task_id)
            for fu in (task.get("follow_ups") or []):
                if isinstance(fu, dict) and not fu.get("task_id"):
                    fu["task_id"] = tid_str
                parsed = _safe_parse_follow_up(fu)
                if parsed:
                    if parsed.task_id is None:
                        parsed.task_id = tid_str
                    follow_ups.append(parsed)
            if is_completed is True:
                follow_ups = [fu for fu in follow_ups if fu.completed_at is not None]
            elif is_completed is False:
                follow_ups = [fu for fu in follow_ups if fu.completed_at is None]
            follow_ups.sort(key=lambda x: _safe_sort_key(x.scheduled_at))
            return follow_ups

        query: Dict[str, Any] = {"follow_ups.0": {"$exists": True}}
        if is_completed is True:
            query["follow_ups.completed_at"] = {"$ne": None}
        elif is_completed is False:
            query["follow_ups.completed_at"] = None

        cursor = self.task_repo.collection.find(
            query,
            projection={"follow_ups": 1, "_id": 1},
        )
        res: List[FollowUpSubDocument] = []
        for t in cursor:
            t_id = str(t.get("_id", ""))
            for fu in (t.get("follow_ups") or []):
                if isinstance(fu, dict) and not fu.get("task_id"):
                    fu["task_id"] = t_id
                parsed = _safe_parse_follow_up(fu)
                if not parsed:
                    continue
                if parsed.task_id is None:
                    parsed.task_id = t_id
                if is_completed is True and parsed.completed_at is not None:
                    res.append(parsed)
                elif is_completed is False and parsed.completed_at is None:
                    res.append(parsed)
                elif is_completed is None:
                    res.append(parsed)
        res.sort(key=lambda x: _safe_sort_key(x.scheduled_at))
        return res

    def complete_follow_up(
        self,
        db: Any = None,
        follow_up_id: Union[str, uuid.UUID] = "",
        completed_at: Optional[datetime] = None,
        notes: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> FollowUpSubDocument:
        """Mark embedded follow-up completed."""
        fid_str = str(follow_up_id)
        if task_id is None:
            task = self.task_repo.find_one({"follow_ups.id": fid_str})
            if not task:
                raise FollowUpNotFoundError(follow_up_id)
            tid_str = task["_id"]
        else:
            tid_str = str(task_id)

        now = completed_at or utcnow()
        updated = self.task_repo.complete_follow_up(tid_str, fid_str, completed_at=now)
        if not updated:
            raise FollowUpNotFoundError(follow_up_id)

        if notes is not None:
            self.task_repo.collection.update_one(
                {"_id": tid_str, "follow_ups.id": fid_str},
                {"$set": {"follow_ups.$.notes": notes}},
            )
            updated = self.task_repo.get_by_id(tid_str) or updated

        for fu in (updated.get("follow_ups") or []):
            if isinstance(fu, dict) and fu.get("id") == fid_str:
                parsed = _safe_parse_follow_up(fu)
                if parsed:
                    return parsed

        raise FollowUpNotFoundError(follow_up_id)

    def delete_follow_up(
        self,
        db: Any = None,
        follow_up_id: Union[str, uuid.UUID] = "",
        task_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> bool:
        """Remove embedded follow-up from task."""
        fid_str = str(follow_up_id)
        if task_id is None:
            task = self.task_repo.find_one({"follow_ups.id": fid_str})
            if not task:
                raise FollowUpNotFoundError(follow_up_id)
            tid_str = task["_id"]
        else:
            tid_str = str(task_id)

        doc = self.task_repo.collection.find_one_and_update(
            {"_id": tid_str},
            {"$pull": {"follow_ups": {"id": fid_str}}},
        )
        return doc is not None
