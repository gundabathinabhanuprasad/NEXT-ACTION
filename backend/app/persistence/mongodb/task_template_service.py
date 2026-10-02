"""MongoDB TaskTemplate Service implementation."""

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple, Union
import uuid

from app.documents.task_template import TaskTemplateDocument
from app.models.enums import TaskPriority
from app.repositories import (
    ClientRepository,
    TaskTemplateRepository,
    UserRepository,
    WorkflowRepository,
)
from app.services.exceptions import (
    ClientNotFoundError,
    InactiveUserError,
    TaskTemplateNotFoundError,
    UnauthorizedTemplateAccessError,
    UserNotFoundError,
    WorkflowNotFoundError,
)


class MongoTaskTemplateService:
    """Task template service backed by MongoDB task_templates collection."""

    def __init__(
        self,
        template_repo: Optional[TaskTemplateRepository] = None,
        user_repo: Optional[UserRepository] = None,
        client_repo: Optional[ClientRepository] = None,
        workflow_repo: Optional[WorkflowRepository] = None,
    ):
        self.template_repo = template_repo or TaskTemplateRepository()
        self.user_repo = user_repo or UserRepository()
        self.client_repo = client_repo or ClientRepository()
        self.workflow_repo = workflow_repo or WorkflowRepository()

    def _to_doc(self, raw: Dict[str, Any]) -> TaskTemplateDocument:
        """Convert BSON dict to validated TaskTemplateDocument."""
        data = dict(raw)
        if "_id" in data:
            data["id"] = str(data.pop("_id"))
        return TaskTemplateDocument.model_validate(data)

    def get_task_template(
        self,
        db: Any = None,
        template_id: Union[str, uuid.UUID] = "",
    ) -> TaskTemplateDocument:
        """Retrieve task template by ID or raise TaskTemplateNotFoundError."""
        tpl = self.template_repo.get_by_id(template_id)
        if not tpl:
            raise TaskTemplateNotFoundError(template_id)
        return self._to_doc(tpl)

    def list_task_templates(
        self,
        db: Any = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        created_by_user_id: Optional[Union[str, uuid.UUID]] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[TaskTemplateDocument], int]:
        """List task templates with optional search, active filtering, and pagination."""
        items, total = self.template_repo.list_templates(
            is_active=is_active,
            created_by_user_id=created_by_user_id,
            search=search,
            page=page,
            page_size=page_size,
        )
        return [self._to_doc(i) for i in items], total

    def create_task_template(
        self,
        db: Any = None,
        name: str = "",
        created_by_user_id: Union[str, uuid.UUID] = "",
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        priority: TaskPriority = TaskPriority.MEDIUM,
        max_attempts: int = 2,
        default_due_offset_days: Optional[int] = None,
        default_next_action_offset_days: Optional[int] = None,
        is_active: bool = True,
    ) -> TaskTemplateDocument:
        """Create a new reusable task template blueprint."""
        if client_id is not None:
            client = self.client_repo.get_by_id(client_id)
            if not client:
                raise ClientNotFoundError(client_id)

        if workflow_id is not None:
            wf = self.workflow_repo.get_by_id(workflow_id)
            if not wf:
                raise WorkflowNotFoundError(workflow_id)

        if assigned_user_id is not None:
            user = self.user_repo.get_by_id(assigned_user_id)
            if not user:
                raise UserNotFoundError(assigned_user_id)
            if not user.get("is_active", True):
                raise InactiveUserError()

        doc = TaskTemplateDocument(
            name=name.strip(),
            created_by_user_id=str(created_by_user_id),
            description=description.strip() if description else None,
            subject_line=subject_line.strip() if subject_line else None,
            workflow_id=str(workflow_id) if workflow_id is not None else None,
            client_id=str(client_id) if client_id is not None else None,
            assigned_user_id=str(assigned_user_id) if assigned_user_id is not None else None,
            priority=priority,
            max_attempts=max_attempts,
            default_due_offset_days=default_due_offset_days,
            default_next_action_offset_days=default_next_action_offset_days,
            is_active=is_active,
        )
        saved = self.template_repo.create(doc)
        return self._to_doc(saved)

    def update_task_template(
        self,
        db: Any = None,
        template_id: Union[str, uuid.UUID] = "",
        current_user_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        priority: Optional[TaskPriority] = None,
        max_attempts: Optional[int] = None,
        default_due_offset_days: Optional[int] = None,
        default_next_action_offset_days: Optional[int] = None,
        is_active: Optional[bool] = None,
    ) -> TaskTemplateDocument:
        """Update an existing task template blueprint with authorization check."""
        tpl = self.get_task_template(template_id=template_id)
        if str(tpl.created_by_user_id) != str(current_user_id):
            raise UnauthorizedTemplateAccessError(template_id)

        update_fields: Dict[str, Any] = {}
        if name is not None:
            update_fields["name"] = name.strip()
        if description is not None:
            update_fields["description"] = description.strip() if description else None
        if subject_line is not None:
            update_fields["subject_line"] = subject_line.strip() if subject_line else None
        if workflow_id is not None:
            wf = self.workflow_repo.get_by_id(workflow_id)
            if not wf:
                raise WorkflowNotFoundError(workflow_id)
            update_fields["workflow_id"] = str(workflow_id)
        if client_id is not None:
            client = self.client_repo.get_by_id(client_id)
            if not client:
                raise ClientNotFoundError(client_id)
            update_fields["client_id"] = str(client_id)
        if assigned_user_id is not None:
            user = self.user_repo.get_by_id(assigned_user_id)
            if not user:
                raise UserNotFoundError(assigned_user_id)
            if not user.get("is_active", True):
                raise InactiveUserError()
            update_fields["assigned_user_id"] = str(assigned_user_id)
        if priority is not None:
            update_fields["priority"] = priority.value if hasattr(priority, "value") else str(priority)
        if max_attempts is not None:
            update_fields["max_attempts"] = max_attempts
        if default_due_offset_days is not None:
            update_fields["default_due_offset_days"] = default_due_offset_days
        if default_next_action_offset_days is not None:
            update_fields["default_next_action_offset_days"] = default_next_action_offset_days
        if is_active is not None:
            update_fields["is_active"] = is_active

        updated = self.template_repo.update(template_id, update_fields)
        if not updated:
            raise TaskTemplateNotFoundError(template_id)
        return self._to_doc(updated)

    def delete_task_template(
        self,
        db: Any = None,
        template_id: Union[str, uuid.UUID] = "",
        current_user_id: Union[str, uuid.UUID] = "",
    ) -> None:
        """Delete a task template blueprint with authorization check."""
        tpl = self.get_task_template(template_id=template_id)
        if str(tpl.created_by_user_id) != str(current_user_id):
            raise UnauthorizedTemplateAccessError(template_id)
        self.template_repo.delete(template_id)

    def create_task_from_template(
        self,
        db: Any = None,
        template_id: Union[str, uuid.UUID] = "",
        created_by_user_id: Union[str, uuid.UUID] = "",
        title: Optional[str] = None,
        description: Optional[str] = None,
        subject_line: Optional[str] = None,
        workflow_id: Optional[Union[str, uuid.UUID]] = None,
        client_id: Optional[Union[str, uuid.UUID]] = None,
        assigned_user_id: Optional[Union[str, uuid.UUID]] = None,
        priority: Optional[TaskPriority] = None,
        max_attempts: Optional[int] = None,
        due_date: Optional[datetime] = None,
        next_action_date: Optional[datetime] = None,
    ) -> Any:
        """Instantiate a concrete Task from a TaskTemplate in MongoDB."""
        template = self.get_task_template(template_id=template_id)
        now = datetime.now(timezone.utc)

        effective_due_date = due_date
        if effective_due_date is None and template.default_due_offset_days is not None:
            effective_due_date = now + timedelta(days=template.default_due_offset_days)

        effective_next_action_date = next_action_date
        if effective_next_action_date is None and template.default_next_action_offset_days is not None:
            effective_next_action_date = now + timedelta(days=template.default_next_action_offset_days)

        effective_title = title if title is not None else template.name
        effective_description = description if description is not None else template.description
        effective_subject_line = subject_line if subject_line is not None else template.subject_line
        effective_workflow_id = workflow_id if workflow_id is not None else template.workflow_id
        effective_client_id = client_id if client_id is not None else template.client_id
        effective_assigned_user_id = assigned_user_id if assigned_user_id is not None else template.assigned_user_id
        effective_priority = priority if priority is not None else template.priority
        effective_max_attempts = max_attempts if max_attempts is not None else template.max_attempts

        from app.services.task_service import create_task
        from app.services.history_service import log_history

        task = create_task(
            db=db,
            title=effective_title,
            description=effective_description,
            subject_line=effective_subject_line,
            workflow_id=effective_workflow_id,
            client_id=effective_client_id,
            assigned_user_id=effective_assigned_user_id,
            template_id=template.id,
            priority=effective_priority,
            max_attempts=effective_max_attempts,
            due_date=effective_due_date,
            next_action_date=effective_next_action_date,
            created_by_user_id=created_by_user_id,
        )

        log_history(
            db=db,
            task_id=task.id,
            action="created_from_template",
            old_value=None,
            new_value=f"Template: {template.name} ({template.id})",
            reason=f"Generated from TaskTemplate '{template.name}'",
            created_by_user_id=created_by_user_id,
        )
        return task
