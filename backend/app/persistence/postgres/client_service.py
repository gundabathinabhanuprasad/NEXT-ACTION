"""PostgreSQL / SQLAlchemy Client Service Adapter."""

from typing import Any, List, Optional, Tuple, Union
import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models.client import Client
from app.services.exceptions import ClientNotFoundError


class PostgresClientService:
    """PostgreSQL client service adapter."""

    def _ensure_session(self, db: Optional[Session]) -> Tuple[Session, bool]:
        if db is not None:
            return db, False
        return SessionLocal(), True

    def get_client(self, db: Optional[Session] = None, client_id: Union[str, uuid.UUID] = "") -> Client:
        session, close_needed = self._ensure_session(db)
        try:
            parsed_id = uuid.UUID(str(client_id))
            client = session.get(Client, parsed_id)
            if not client:
                raise ClientNotFoundError(parsed_id)
            return client
        finally:
            if close_needed:
                session.close()

    def create_client(
        self,
        db: Optional[Session] = None,
        name: str = "",
        company: Optional[str] = None,
        email: Optional[str] = None,
        phone: Optional[str] = None,
        notes: Optional[str] = None,
    ) -> Client:
        session, close_needed = self._ensure_session(db)
        try:
            client = Client(
                name=name.strip(),
                company=company.strip() if company else None,
                email=email.strip() if email else None,
                phone=phone.strip() if phone else None,
                notes=notes,
            )
            session.add(client)
            session.commit()
            session.refresh(client)

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_client(client, DualWriteOperation.CREATE)

            return client
        finally:
            if close_needed:
                session.close()

    def update_client(
        self,
        db: Optional[Session] = None,
        client_id: Union[str, uuid.UUID] = "",
        name: Optional[str] = None,
        company: Optional[str] = None,
        email: Optional[str] = None,
        phone: Optional[str] = None,
        notes: Optional[str] = None,
    ) -> Client:
        session, close_needed = self._ensure_session(db)
        try:
            client = self.get_client(session, client_id)

            if name is not None:
                client.name = name.strip()
            if company is not None:
                client.company = company.strip() if company else None
            if email is not None:
                client.email = email.strip() if email else None
            if phone is not None:
                client.phone = phone.strip() if phone else None
            if notes is not None:
                client.notes = notes

            session.commit()
            session.refresh(client)

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_client(client, DualWriteOperation.UPDATE)

            return client
        finally:
            if close_needed:
                session.close()

    def delete_client(self, db: Optional[Session] = None, client_id: Union[str, uuid.UUID] = "") -> bool:
        session, close_needed = self._ensure_session(db)
        try:
            client = self.get_client(session, client_id)
            session.delete(client)
            session.commit()

            # Controlled dual-write to MongoDB (Phase 31)
            from app.migration.dual_write import DualWriteOperation, dual_writer
            dual_writer.sync_client(client, DualWriteOperation.DELETE)

            return True
        finally:
            if close_needed:
                session.close()

    def list_clients(
        self,
        db: Optional[Session] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 100,
    ) -> Tuple[List[Client], int]:
        session, close_needed = self._ensure_session(db)
        try:
            stmt = select(Client)
            count_stmt = select(func.count(Client.id))

            if search:
                term = f"%{search.strip()}%"
                condition = or_(
                    Client.name.ilike(term),
                    Client.company.ilike(term),
                    Client.email.ilike(term),
                )
                stmt = stmt.where(condition)
                count_stmt = count_stmt.where(condition)

            total = session.scalar(count_stmt) or 0
            offset = max(0, (page - 1) * page_size)
            stmt = stmt.order_by(Client.name.asc()).offset(offset).limit(page_size)
            items = list(session.scalars(stmt).all())

            return items, total
        finally:
            if close_needed:
                session.close()
