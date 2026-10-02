"""Transformation layer: Converts PostgreSQL ORM records to MongoDB Pydantic documents."""

from datetime import datetime, timezone
from typing import Optional

from app.documents.client import ClientDocument
from app.documents.event import EventDocument
from app.documents.notification import NotificationDocument
from app.documents.recurring_task import (
    RecurringTaskDocument,
    RecurringTaskExecutionDocument,
)
from app.documents.refresh_token import RefreshTokenDocument
from app.documents.task import FollowUpSubDocument, ReminderSubDocument, TaskDocument
from app.documents.task_history import TaskHistoryDocument
from app.documents.task_template import TaskTemplateDocument
from app.documents.user import UserDocument
from app.documents.user_settings import UserSettingsDocument
from app.documents.workflow import WorkflowDocument

from app.models.client import Client
from app.models.event import Event
from app.models.notification import Notification
from app.models.recurring_task import RecurringTask, RecurringTaskExecution
from app.models.refresh_token import RefreshToken
from app.models.task import Task
from app.models.task_history import TaskHistory
from app.models.task_template import TaskTemplate
from app.models.user import User
from app.models.user_settings import UserSettings
from app.models.workflow import Workflow


def ensure_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """Normalize datetime to timezone-aware UTC datetime."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


class EntityTransformer:
    """Transforms PostgreSQL models into Phase 29 MongoDB document schemas with strict ID preservation."""

    @staticmethod
    def transform_user(user: User) -> UserDocument:
        """Transform User ORM record to UserDocument."""
        return UserDocument(
            _id=str(user.id),
            name=user.name,
            email=user.email.strip().lower(),
            password_hash=user.password_hash or "",
            is_active=user.is_active,
            created_at=ensure_utc(user.created_at),
            updated_at=ensure_utc(user.updated_at),
        )

    @staticmethod
    def transform_user_settings(settings: UserSettings) -> UserSettingsDocument:
        """Transform UserSettings ORM record to UserSettingsDocument."""
        return UserSettingsDocument(
            _id=str(settings.id),
            user_id=str(settings.user_id),
            display_name_override=settings.display_name_override,
            timezone=settings.timezone,
            date_format=settings.date_format,
            time_format=settings.time_format,
            first_day_of_week=settings.first_day_of_week,
            theme=settings.theme,
            compact_mode=settings.compact_mode,
            default_task_priority=settings.default_task_priority,
            default_task_status_filter=settings.default_task_status_filter,
            default_task_sort=settings.default_task_sort,
            default_task_sort_order=settings.default_task_sort_order,
            default_max_attempts=settings.default_max_attempts,
            default_page_size=settings.default_page_size,
            default_dashboard_time_range=settings.default_dashboard_time_range,
            default_report_date_range=settings.default_report_date_range,
            default_report_type=settings.default_report_type,
            default_export_format=settings.default_export_format,
            notify_task_assigned=settings.notify_task_assigned,
            notify_task_reassigned=settings.notify_task_reassigned,
            notify_reminder_due=settings.notify_reminder_due,
            notify_follow_up_due=settings.notify_follow_up_due,
            notify_next_action_due=settings.notify_next_action_due,
            notify_task_overdue=settings.notify_task_overdue,
            notify_attempt_limit_reached=settings.notify_attempt_limit_reached,
            notify_task_completed=settings.notify_task_completed,
            notify_task_reopened=settings.notify_task_reopened,
            created_at=ensure_utc(settings.created_at),
            updated_at=ensure_utc(settings.updated_at),
        )

    @staticmethod
    def transform_client(client: Client) -> ClientDocument:
        """Transform Client ORM record to ClientDocument."""
        return ClientDocument(
            _id=str(client.id),
            name=client.name,
            company=client.company,
            email=client.email,
            phone=client.phone,
            notes=client.notes,
            created_at=ensure_utc(client.created_at),
            updated_at=ensure_utc(client.updated_at),
        )

    @staticmethod
    def transform_workflow(wf: Workflow) -> WorkflowDocument:
        """Transform Workflow ORM record to WorkflowDocument."""
        return WorkflowDocument(
            _id=str(wf.id),
            name=wf.name,
            description=wf.description,
            is_active=wf.is_active,
            created_at=ensure_utc(wf.created_at),
            updated_at=ensure_utc(wf.updated_at),
        )

    @staticmethod
    def transform_task_template(template: TaskTemplate) -> TaskTemplateDocument:
        """Transform TaskTemplate ORM record to TaskTemplateDocument."""
        return TaskTemplateDocument(
            _id=str(template.id),
            name=template.name,
            description=template.description,
            subject_line=template.subject_line,
            workflow_id=str(template.workflow_id) if template.workflow_id else None,
            client_id=str(template.client_id) if template.client_id else None,
            assigned_user_id=str(template.assigned_user_id) if template.assigned_user_id else None,
            priority=template.priority,
            max_attempts=template.max_attempts,
            default_due_offset_days=template.default_due_offset_days,
            default_next_action_offset_days=template.default_next_action_offset_days,
            is_active=template.is_active,
            created_by_user_id=str(template.created_by_user_id),
            created_at=ensure_utc(template.created_at),
            updated_at=ensure_utc(template.updated_at),
        )

    @staticmethod
    def transform_recurring_task(rec: RecurringTask) -> RecurringTaskDocument:
        """Transform RecurringTask ORM record to RecurringTaskDocument."""
        return RecurringTaskDocument(
            _id=str(rec.id),
            template_id=str(rec.template_id) if rec.template_id else None,
            name=rec.name,
            description=rec.description,
            subject_line=rec.subject_line,
            workflow_id=str(rec.workflow_id) if rec.workflow_id else None,
            client_id=str(rec.client_id) if rec.client_id else None,
            assigned_user_id=str(rec.assigned_user_id) if rec.assigned_user_id else None,
            priority=rec.priority,
            max_attempts=rec.max_attempts,
            due_offset_days=rec.due_offset_days,
            next_action_offset_days=rec.next_action_offset_days,
            recurrence_type=rec.recurrence_type,
            interval=rec.interval,
            day_of_week=rec.day_of_week,
            day_of_month=rec.day_of_month,
            start_date=ensure_utc(rec.start_date),
            end_date=ensure_utc(rec.end_date),
            next_run_at=ensure_utc(rec.next_run_at),
            last_run_at=ensure_utc(rec.last_run_at),
            is_active=rec.is_active,
            created_by_user_id=str(rec.created_by_user_id),
            created_at=ensure_utc(rec.created_at),
            updated_at=ensure_utc(rec.updated_at),
        )

    @staticmethod
    def transform_task(task: Task) -> TaskDocument:
        """Transform Task ORM record to TaskDocument with embedded reminders and follow-ups."""
        embedded_reminders = [
            ReminderSubDocument(
                id=str(r.id),
                task_id=str(task.id),
                remind_at=ensure_utc(r.remind_at),
                message=r.message,
                is_sent=r.is_sent,
                created_at=ensure_utc(r.created_at),
                updated_at=ensure_utc(r.updated_at),
            )
            for r in (task.reminders or [])
        ]

        embedded_follow_ups = [
            FollowUpSubDocument(
                id=str(f.id),
                task_id=str(task.id),
                scheduled_at=ensure_utc(f.scheduled_at),
                completed_at=ensure_utc(f.completed_at),
                notes=f.notes,
                created_at=ensure_utc(f.created_at),
                updated_at=ensure_utc(f.updated_at),
            )
            for f in (task.follow_ups or [])
        ]

        # Extract denormalized summary fields
        client_name = task.client.name if task.client else None
        workflow_name = task.workflow.name if task.workflow else None
        assigned_user_name = task.assigned_user.name if task.assigned_user else None
        assigned_user_email = task.assigned_user.email if task.assigned_user else None

        return TaskDocument(
            _id=str(task.id),
            title=task.title,
            description=task.description,
            subject_line=task.subject_line,
            workflow_id=str(task.workflow_id) if task.workflow_id else None,
            client_id=str(task.client_id) if task.client_id else None,
            assigned_user_id=str(task.assigned_user_id) if task.assigned_user_id else None,
            template_id=str(task.template_id) if task.template_id else None,
            recurring_task_id=str(task.recurring_task_id) if task.recurring_task_id else None,
            status=task.status,
            priority=task.priority,
            due_date=ensure_utc(task.due_date),
            next_action_date=ensure_utc(task.next_action_date),
            attempt_count=task.attempt_count,
            max_attempts=task.max_attempts,
            completed_at=ensure_utc(task.completed_at),
            reminders=embedded_reminders,
            follow_ups=embedded_follow_ups,
            client_name=client_name,
            workflow_name=workflow_name,
            assigned_user_name=assigned_user_name,
            assigned_user_email=assigned_user_email,
            created_at=ensure_utc(task.created_at),
            updated_at=ensure_utc(task.updated_at),
        )

    @staticmethod
    def transform_task_history(hist: TaskHistory) -> TaskHistoryDocument:
        """Transform TaskHistory ORM record to TaskHistoryDocument."""
        return TaskHistoryDocument(
            _id=str(hist.id),
            task_id=str(hist.task_id) if hist.task_id else None,
            action=hist.action,
            old_value=hist.old_value,
            new_value=hist.new_value,
            reason=hist.reason,
            created_by_user_id=str(hist.created_by_user_id) if hist.created_by_user_id else None,
            created_at=ensure_utc(hist.created_at),
        )

    @staticmethod
    def transform_recurring_task_execution(
        exec_item: RecurringTaskExecution,
    ) -> RecurringTaskExecutionDocument:
        """Transform RecurringTaskExecution ORM record to RecurringTaskExecutionDocument."""
        return RecurringTaskExecutionDocument(
            _id=str(exec_item.id),
            recurring_task_id=str(exec_item.recurring_task_id),
            scheduled_for=ensure_utc(exec_item.scheduled_for),
            task_id=str(exec_item.task_id) if exec_item.task_id else None,
            status=exec_item.status,
            executed_at=ensure_utc(exec_item.executed_at),
        )

    @staticmethod
    def transform_notification(notif: Notification) -> NotificationDocument:
        """Transform Notification ORM record to NotificationDocument."""
        return NotificationDocument(
            _id=str(notif.id),
            user_id=str(notif.user_id),
            task_id=str(notif.task_id) if notif.task_id else None,
            type=notif.type,
            title=notif.title,
            message=notif.message,
            dedup_key=notif.dedup_key,
            is_read=notif.is_read,
            read_at=ensure_utc(notif.read_at),
            created_at=ensure_utc(notif.created_at),
            updated_at=ensure_utc(notif.updated_at),
        )

    @staticmethod
    def transform_event(event: Event) -> EventDocument:
        """Transform Event ORM record to EventDocument."""
        return EventDocument(
            _id=str(event.id),
            title=event.title,
            description=event.description,
            start_at=ensure_utc(event.start_at),
            end_at=ensure_utc(event.end_at),
            location=event.location,
            task_id=str(event.task_id) if event.task_id else None,
            client_id=str(event.client_id) if event.client_id else None,
            created_at=ensure_utc(event.created_at),
            updated_at=ensure_utc(event.updated_at),
        )

    @staticmethod
    def transform_refresh_token(rt: RefreshToken) -> RefreshTokenDocument:
        """Transform RefreshToken ORM record to RefreshTokenDocument."""
        return RefreshTokenDocument(
            _id=str(rt.id),
            user_id=str(rt.user_id),
            token_hash=rt.token_hash,
            expires_at=ensure_utc(rt.expires_at),
            is_revoked=rt.is_revoked,
            revoked_at=ensure_utc(rt.revoked_at),
            replaced_by_id=str(rt.replaced_by_id) if rt.replaced_by_id else None,
            ip_address=getattr(rt, "ip_address", None),
            user_agent=getattr(rt, "user_agent", None),
            created_at=ensure_utc(rt.created_at),
            updated_at=getattr(rt, "updated_at", ensure_utc(rt.created_at)),
        )
