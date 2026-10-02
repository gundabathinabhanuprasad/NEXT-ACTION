"""PostgreSQL / SQLAlchemy Workflow Service Adapter."""

from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.workflow import Workflow
from app.services.exceptions import WorkflowNotFoundError


class PostgresWorkflowService:
    """PostgreSQL workflow service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def get_workflow(self, db: Optional[Session] = None, workflow_id: Union[str, uuid.UUID] = "") -> Workflow:
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(workflow_id))
            workflow = session.get(Workflow, parsed_id)
            if not workflow:
                raise WorkflowNotFoundError(parsed_id)
            return workflow
        finally:
            if close_needed:
                session.close()

    def create_workflow(
        self,
        db: Optional[Session] = None,
        name: str = "",
        description: Optional[str] = None,
        is_active: bool = True,
    ) -> Workflow:
        session, close_needed = self._ensure_session(db)
        try:
            workflow = Workflow(
                name=name.strip(),
                description=description,
                is_active=is_active,
            )
            session.add(workflow)
            session.commit()
            session.refresh(workflow)

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_workflow(workflow, DualWriteOperation.CREATE)

            return workflow
        finally:
            if close_needed:
                session.close()

    def update_workflow(
        self,
        db: Optional[Session] = None,
        workflow_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        description: Optional[str] = None,
        is_active: Optional[bool] = None,
    ) -> Workflow:
        session, close_needed = self._ensure_session(db)
        try:
            workflow = self.get_workflow(session, workflow_id)

            if name is not None:
                workflow.name = name.strip()
            if description is not None:
                workflow.description = description
            if is_active is not None:
                workflow.is_active = is_active

            session.commit()
            session.refresh(workflow)

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_workflow(workflow, DualWriteOperation.UPDATE)

            return workflow
        finally:
            if close_needed:
                session.close()

    def delete_workflow(self, db: Optional[Session] = None, workflow_id: Union[str, uuid.UUID] = "") -> bool:
        session, close_needed = self._ensure_session(db)
        try:
            workflow = self.get_workflow(session, workflow_id)
            session.delete(workflow)
            session.commit()

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_workflow(workflow, DualWriteOperation.DELETE)

            return True
        finally:
            if close_needed:
                session.close()

    def list_workflows(
        self,
        db: Optional[Session] = None,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 100,
    ) -> Tuple[List[Workflow], int]:
        session, close_needed = self._ensure_session(db)
        try:
            stmt = select(Workflow)
            count_stmt = select(func.count(Workflow.id))

            if search:
                term = f"%{search.strip()}%"
                condition = or_(
                    Workflow.name.ilike(term),
                    Workflow.description.ilike(term),
                )
                stmt = stmt.where(condition)
                count_stmt = count_stmt.where(condition)

            if is_active is not None:
                stmt = stmt.where(Workflow.is_active == is_active)
                count_stmt = count_stmt.where(Workflow.is_active == is_active)

            total = session.scalar(count_stmt) or 0
            offset = max(0, (page - 1) * page_size)
            stmt = stmt.order_by(Workflow.name.asc()).offset(offset).limit(page_size)
            items = list(session.scalars(stmt).all())

            return items, total
        finally:
            if close_needed:
                session.close()
