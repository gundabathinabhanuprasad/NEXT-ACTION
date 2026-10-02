"""MongoDB Follow-Up Service implementation using embedded task subdocuments."""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Union
import uuid

from app.documents.common import utcnow
from app.documents.task import FollowUpSubDocument
from app.repositories import TaskRepository
from app.services.exceptions import FollowUpNotFoundError, TaskNotFoundError


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
            scheduled_at=scheduled_at,
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

        for fu in task.get("follow_ups", []):
            if fu.get("id") == fid_str:
                return FollowUpSubDocument.model_validate(fu)

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
        return [FollowUpSubDocument.model_validate(f) for f in task.get("follow_ups", [])]

    def list_due_follow_ups(
        self,
        db: Any = None,
        as_of: Optional[datetime] = None,
    ) -> List[FollowUpSubDocument]:
        """List uncompleted follow-ups scheduled on or before as_of across all tasks."""
        target_time = as_of or datetime.now(timezone.utc)
        tasks = self.task_repo.collection.find(
            {"follow_ups": {"$elemMatch": {"completed_at": None, "scheduled_at": {"$lte": target_time}}}}
        )
        due: List[FollowUpSubDocument] = []
        for t in tasks:
            for fu in t.get("follow_ups", []):
                if fu.get("completed_at") is None and fu.get("scheduled_at") and fu["scheduled_at"] <= target_time:
                    due.append(FollowUpSubDocument.model_validate(fu))
        due.sort(key=lambda x: x.scheduled_at or datetime.min.replace(tzinfo=timezone.utc))
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
            follow_ups = [FollowUpSubDocument.model_validate(fu) for fu in task.get("follow_ups", [])]
            if is_completed is True:
                follow_ups = [fu for fu in follow_ups if fu.completed_at is not None]
            elif is_completed is False:
                follow_ups = [fu for fu in follow_ups if fu.completed_at is None]
            follow_ups.sort(key=lambda x: x.scheduled_at or datetime.min.replace(tzinfo=timezone.utc))
            return follow_ups

        query: Dict[str, Any] = {}
        if is_completed is True:
            query = {"follow_ups.completed_at": {"$ne": None}}
        elif is_completed is False:
            query = {"follow_ups.completed_at": None}

        tasks = self.task_repo.collection.find(query)
        res: List[FollowUpSubDocument] = []
        for t in tasks:
            for fu in t.get("follow_ups", []):
                if is_completed is True and fu.get("completed_at") is not None:
                    res.append(FollowUpSubDocument.model_validate(fu))
                elif is_completed is False and fu.get("completed_at") is None:
                    res.append(FollowUpSubDocument.model_validate(fu))
                elif is_completed is None:
                    res.append(FollowUpSubDocument.model_validate(fu))
        res.sort(key=lambda x: x.scheduled_at or datetime.min.replace(tzinfo=timezone.utc))
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

        for fu in updated.get("follow_ups", []):
            if fu.get("id") == fid_str:
                return FollowUpSubDocument.model_validate(fu)

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
