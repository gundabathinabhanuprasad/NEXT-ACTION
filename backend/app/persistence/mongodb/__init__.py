"""MongoDB persistence service adapters."""

from app.persistence.mongodb.client_service import MongoClientService
from app.persistence.mongodb.follow_up_service import MongoFollowUpService
from app.persistence.mongodb.history_service import MongoHistoryService
from app.persistence.mongodb.notification_service import MongoNotificationService
from app.persistence.mongodb.recurring_task_service import MongoRecurringTaskService
from app.persistence.mongodb.reminder_service import MongoReminderService
from app.persistence.mongodb.report_service import MongoReportService
from app.persistence.mongodb.settings_service import MongoSettingsService
from app.persistence.mongodb.task_service import MongoTaskService
from app.persistence.mongodb.task_template_service import MongoTaskTemplateService
from app.persistence.mongodb.user_service import MongoUserService
from app.persistence.mongodb.workflow_service import MongoWorkflowService

__all__ = [
    "MongoClientService",
    "MongoFollowUpService",
    "MongoHistoryService",
    "MongoNotificationService",
    "MongoRecurringTaskService",
    "MongoReminderService",
    "MongoReportService",
    "MongoSettingsService",
    "MongoTaskService",
    "MongoTaskTemplateService",
    "MongoUserService",
    "MongoWorkflowService",
]
