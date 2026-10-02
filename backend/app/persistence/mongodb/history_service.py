"""MongoDB History and Activity Service Adapter.

Provides audit trail persistence, filtering, and retrieval backed by TaskHistoryRepository.
"""

from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.documents.task_history import TaskHistoryDocument
from app.repositories.task_history_repository import TaskHistoryRepository
from app.repositories.task_repository import TaskRepository
from app.repositories.user_repository import UserRepository
from app.schemas.history import TaskHistoryResponse
from app.services.exceptions import TaskNotFoundError


class MongoHistoryService:
    """Audit history service implementation for MongoDB."""

    def __init__(
        self,
        history_repo: Optional[TaskHistoryRepository] = None,
        task_repo: Optional[TaskRepository] = None,
        user_repo: Optional[UserRepository] = None,
    ):
        self.history_repo = history_repo or TaskHistoryRepository()
        self.task_repo = task_repo or TaskRepository()
        self.user_repo = user_repo or UserRepository()

    def log_history(
        self,
        db: Any = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        action: str = "",
        old_value: Optional[str] = None,
        new_value: Optional[str] = None,
        reason: Optional[str] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> TaskHistoryDocument:
        """Create and persist an audit history entry."""
        task_str = str(task_id) if task_id else None
        user_str = str(created_by_user_id) if created_by_user_id else None

        doc_dict = self.history_repo.create_entry(
            task_id=task_str,
            action=action,
            old_value=old_value,
            new_value=new_value,
            reason=reason,
            created_by_user_id=user_str,
        )
        return TaskHistoryDocument.model_validate(doc_dict)

    def get_task_history(
        self,
        db: Any = None,
        task_id: Union[str, uuid.UUID] = "",
        action: Optional[str] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
        order: str = "asc",
        page: Optional[int] = None,
        page_size: Optional[int] = None,
    ) -> List[TaskHistoryDocument]:
        """Retrieve chronological history for a specific task."""
        task_str = str(task_id)
        # Verify task exists
        task = self.task_repo.get_by_id(task_str)
        if not task:
            raise TaskNotFoundError(task_str)

        query: Dict[str, Any] = {"task_id": task_str}
        if action:
            query["action"] = action.strip().lower()
        if actor_id:
            query["created_by_user_id"] = str(actor_id)

        skip = ((page - 1) * page_size) if page and page_size else 0
        limit = page_size or 0

        entries = self.history_repo.find_many(
            query,
            sort_by="created_at",
            sort_order=order,
            limit=limit,
            skip=skip,
        )
        return [TaskHistoryDocument.model_validate(e) for e in entries]

    def get_recent_activity(
        self,
        db: Any = None,
        limit: int = 20,
        action: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
    ) -> List[TaskHistoryDocument]:
        """Retrieve recent activity logs across all tasks."""
        query: Dict[str, Any] = {}
        if action:
            query["action"] = action.strip().lower()
        if task_id:
            query["task_id"] = str(task_id)
        if actor_id:
            query["created_by_user_id"] = str(actor_id)

        entries = self.history_repo.find_many(
            query,
            sort_by="created_at",
            sort_order="desc",
            limit=limit,
        )
        return [TaskHistoryDocument.model_validate(e) for e in entries]

    def list_activity(
        self,
        db: Any = None,
        page: int = 1,
        page_size: int = 20,
        action: Optional[str] = None,
        task_id: Optional[Union[str, uuid.UUID]] = None,
        actor_id: Optional[Union[str, uuid.UUID]] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> Tuple[List[TaskHistoryDocument], int]:
        """List paginated activity timeline logs."""
        query: Dict[str, Any] = {}
        if action:
            query["action"] = action.strip().lower()
        if task_id:
            query["task_id"] = str(task_id)
        if actor_id:
            query["created_by_user_id"] = str(actor_id)

        created_filter: Dict[str, Any] = {}
        if start_date:
            created_filter["$gte"] = start_date
        if end_date:
            created_filter["$lte"] = end_date
        if created_filter:
            query["created_at"] = created_filter

        raw_items, total = self.history_repo.paginate(
            query=query,
            page=page,
            page_size=page_size,
            sort=[("created_at", -1), ("_id", -1)],
        )
        items = [TaskHistoryDocument.model_validate(e) for e in raw_items]
        return items, total

    def serialize_task_history(self, history: Any) -> TaskHistoryResponse:
        """Transform a task history item (ORM model, document, or dict) into TaskHistoryResponse."""
        if hasattr(history, "model_dump"):
            data = history.model_dump()
        elif isinstance(history, dict):
            data = history
        else:
            # SQLAlchemy ORM fallback
            from app.services.history_service import serialize_task_history as pg_serialize
            return pg_serialize(history)

        entry_id = data.get("id") or data.get("_id")
        task_id = data.get("task_id")
        user_id = data.get("created_by_user_id")

        actor_name: Optional[str] = None
        actor_email: Optional[str] = None
        if user_id:
            user_doc = self.user_repo.get_by_id(user_id)
            if user_doc:
                actor_name = user_doc.get("name")
                actor_email = user_doc.get("email")
            else:
                actor_name = "Former user"
        else:
            actor_name = "System"

        task_title: Optional[str] = None
        if task_id:
            t_doc = self.task_repo.get_by_id(task_id)
            if t_doc:
                task_title = t_doc.get("title")

        return TaskHistoryResponse(
            id=uuid.UUID(str(entry_id)),
            task_id=uuid.UUID(str(task_id)) if task_id else None,
            task_title=task_title,
            action=data.get("action", ""),
            old_value=data.get("old_value"),
            new_value=data.get("new_value"),
            reason=data.get("reason"),
            created_by_user_id=uuid.UUID(str(user_id)) if user_id else None,
            actor_name=actor_name,
            actor_email=actor_email,
            created_at=data.get("created_at"),
        )
