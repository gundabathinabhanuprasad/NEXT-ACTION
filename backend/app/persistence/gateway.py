"""Centralized Persistence Gateway for Dual-Engine Dispatch.

Resolves service layer calls to PostgreSQL or MongoDB persistence implementations
dynamically based on configuration or contextual overrides, without scattering engine checks.
"""

import logging
from typing import Optional

from app.persistence.constants import EngineType
from app.persistence.context import get_active_engine
from app.persistence.interfaces import (
    ClientPersistenceService,
    FollowUpPersistenceService,
    HistoryPersistenceService,
    NotificationPersistenceService,
    ReminderPersistenceService,
    SettingsPersistenceService,
    TaskPersistenceService,
    UserPersistenceService,
    WorkflowPersistenceService,
)
from app.persistence.mongodb import (
    MongoClientService,
    MongoFollowUpService,
    MongoHistoryService,
    MongoNotificationService,
    MongoReminderService,
    MongoSettingsService,
    MongoTaskService,
    MongoUserService,
    MongoWorkflowService,
)
from app.persistence.postgres import (
    PostgresClientService,
    PostgresFollowUpService,
    PostgresHistoryService,
    PostgresNotificationService,
    PostgresReminderService,
    PostgresSettingsService,
    PostgresTaskService,
    PostgresUserService,
    PostgresWorkflowService,
)

logger = logging.getLogger("nextaction.persistence.gateway")


class PersistenceGateway:
    """Centralized persistence gateway dispatching to the configured persistence engine."""

    def __init__(self, explicit_engine: Optional[str] = None):
        self._explicit_engine = explicit_engine
        # Cached adapter instances per engine
        self._pg_task = PostgresTaskService()
        self._pg_user = PostgresUserService()
        self._pg_client = PostgresClientService()
        self._pg_workflow = PostgresWorkflowService()
        self._pg_settings = PostgresSettingsService()
        self._pg_notification = PostgresNotificationService()
        self._pg_reminder = PostgresReminderService()
        self._pg_follow_up = PostgresFollowUpService()
        self._pg_history = PostgresHistoryService()

        self._mongo_task: Optional[MongoTaskService] = None
        self._mongo_user: Optional[MongoUserService] = None
        self._mongo_client: Optional[MongoClientService] = None
        self._mongo_workflow: Optional[MongoWorkflowService] = None
        self._mongo_settings: Optional[MongoSettingsService] = None
        self._mongo_notification: Optional[MongoNotificationService] = None
        self._mongo_reminder: Optional[MongoReminderService] = None
        self._mongo_follow_up: Optional[MongoFollowUpService] = None
        self._mongo_history: Optional[MongoHistoryService] = None

    @property
    def active_engine(self) -> str:
        """Resolve the active persistence engine."""
        return get_active_engine(self._explicit_engine)

    @property
    def is_mongodb(self) -> bool:
        """Check if MongoDB is the active engine."""
        return self.active_engine == EngineType.MONGODB.value

    @property
    def is_postgresql(self) -> bool:
        """Check if PostgreSQL is the active engine."""
        return self.active_engine == EngineType.POSTGRESQL.value

    # Lazy-instantiation helpers for MongoDB adapters
    def _get_mongo_task(self) -> MongoTaskService:
        if self._mongo_task is None:
            self._mongo_task = MongoTaskService()
        return self._mongo_task

    def _get_mongo_user(self) -> MongoUserService:
        if self._mongo_user is None:
            self._mongo_user = MongoUserService()
        return self._mongo_user

    def _get_mongo_client(self) -> MongoClientService:
        if self._mongo_client is None:
            self._mongo_client = MongoClientService()
        return self._mongo_client

    def _get_mongo_workflow(self) -> MongoWorkflowService:
        if self._mongo_workflow is None:
            self._mongo_workflow = MongoWorkflowService()
        return self._mongo_workflow

    def _get_mongo_settings(self) -> MongoSettingsService:
        if self._mongo_settings is None:
            self._mongo_settings = MongoSettingsService()
        return self._mongo_settings

    def _get_mongo_notification(self) -> MongoNotificationService:
        if self._mongo_notification is None:
            self._mongo_notification = MongoNotificationService()
        return self._mongo_notification

    def _get_mongo_reminder(self) -> MongoReminderService:
        if self._mongo_reminder is None:
            self._mongo_reminder = MongoReminderService()
        return self._mongo_reminder

    def _get_mongo_follow_up(self) -> MongoFollowUpService:
        if self._mongo_follow_up is None:
            self._mongo_follow_up = MongoFollowUpService()
        return self._mongo_follow_up

    def _get_mongo_history(self) -> MongoHistoryService:
        if self._mongo_history is None:
            self._mongo_history = MongoHistoryService()
        return self._mongo_history

    @property
    def task_service(self) -> TaskPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_task()
        return self._pg_task

    @property
    def user_service(self) -> UserPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_user()
        return self._pg_user

    @property
    def client_service(self) -> ClientPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_client()
        return self._pg_client

    @property
    def workflow_service(self) -> WorkflowPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_workflow()
        return self._pg_workflow

    @property
    def settings_service(self) -> SettingsPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_settings()
        return self._pg_settings

    @property
    def notification_service(self) -> NotificationPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_notification()
        return self._pg_notification

    @property
    def reminder_service(self) -> ReminderPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_reminder()
        return self._pg_reminder

    @property
    def follow_up_service(self) -> FollowUpPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_follow_up()
        return self._pg_follow_up

    @property
    def history_service(self) -> HistoryPersistenceService:
        if self.is_mongodb:
            return self._get_mongo_history()
        return self._pg_history


_global_gateway = PersistenceGateway()


def get_persistence_gateway(engine: Optional[str] = None) -> PersistenceGateway:
    """Retrieve the persistence gateway singleton or an engine-specific instance."""
    if engine is not None:
        return PersistenceGateway(explicit_engine=engine)
    return _global_gateway
