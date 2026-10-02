"""Phase 19 Automated Reminder, Notification Delivery & Scheduling Engine.

Provides idempotent, deterministic, bounded, failure-isolated evaluation of:
- Due Reminders
- Due / Overdue Follow-ups
- Due / Overdue Next Actions
- Overdue Tasks
- Attempt Limit Alerts (Near Max & Max Attempts)

Integrates strictly with:
- Phase 18 UserSettings notification preferences
- Phase 18 IANA Timezones for calendar day boundary evaluation
- PostgreSQL partial unique index (uq_notifications_user_dedup) for race-safe deduplication
- Controlled transaction boundaries (savepoints) for robust failure isolation
"""

from datetime import datetime, time as dt_time, timedelta, timezone
import logging
import time
from typing import Dict, List, Optional, Set, Tuple
import uuid
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.models.enums import TaskStatus
from app.models.follow_up import FollowUp
from app.models.notification import Notification
from app.models.reminder import Reminder
from app.models.task import Task
from app.models.user_settings import UserSettings
from app.schemas.scheduler import CategoryEvaluationDetail, SchedulerEvaluationResponse
from app.services.notification_service import should_notify_user

logger = logging.getLogger(__name__)


def get_user_timezone(db: Session, user_id: uuid.UUID) -> ZoneInfo:
    """Retrieve the IANA timezone for a user, defaulting to UTC if not configured or invalid."""
    settings = db.scalars(
        select(UserSettings).where(UserSettings.user_id == user_id)
    ).first()
    if not settings or not settings.timezone:
        return ZoneInfo("UTC")
    try:
        return ZoneInfo(settings.timezone)
    except Exception:
        logger.warning(f"Invalid timezone '{settings.timezone}' for user {user_id}; fallback to UTC")
        return ZoneInfo("UTC")


def get_user_calendar_bounds(
    db: Session,
    user_id: uuid.UUID,
    as_of: datetime,
) -> Tuple[ZoneInfo, datetime, datetime]:
    """Calculate UTC timestamps corresponding to the start (00:00:00) and end (00:00:00 next day)

    of the user's local calendar day for the given point in time.
    """
    user_tz = get_user_timezone(db, user_id)
    if as_of.tzinfo is None:
        as_of = as_of.replace(tzinfo=timezone.utc)
    local_dt = as_of.astimezone(user_tz)

    # Local start of day (midnight)
    local_start = datetime.combine(local_dt.date(), dt_time.min, tzinfo=user_tz)
    local_end = local_start + timedelta(days=1)

    # Convert bounds back to UTC for query comparisons
    utc_start = local_start.astimezone(timezone.utc)
    utc_end = local_end.astimezone(timezone.utc)
    return user_tz, utc_start, utc_end


def _preload_existing_dedup_keys(
    db: Session,
    user_dedup_pairs: List[Tuple[uuid.UUID, str]],
) -> Set[Tuple[uuid.UUID, str]]:
    """Batch-lookup existing notifications matching (user_id, dedup_key) to avoid N+1 queries."""
    if not user_dedup_pairs:
        return set()

    # If small set, query directly with or_
    existing: Set[Tuple[uuid.UUID, str]] = set()
    # Batch query by unique user IDs
    user_ids = {pair[0] for pair in user_dedup_pairs}
    dedup_keys = {pair[1] for pair in user_dedup_pairs}

    stmt = select(Notification.user_id, Notification.dedup_key).where(
        Notification.user_id.in_(user_ids),
        Notification.dedup_key.in_(dedup_keys),
    )
    for row in db.execute(stmt):
        existing.add((row[0], row[1]))
    return existing


class SchedulingService:
    """Production scheduling and automated reminder evaluation engine."""

    @staticmethod
    def evaluate_reminders(
        db: Session,
        as_of: datetime,
        user_id: Optional[uuid.UUID] = None,
    ) -> CategoryEvaluationDetail:
        """Evaluate unsent reminders due on or before `as_of`."""
        metrics = CategoryEvaluationDetail()

        stmt = (
            select(Reminder)
            .join(Task, Reminder.task_id == Task.id)
            .options(joinedload(Reminder.task))
            .where(
                Reminder.is_sent.is_(False),
                Reminder.remind_at <= as_of,
                Task.assigned_user_id.is_not(None),
            )
        )
        if user_id is not None:
            stmt = stmt.where(Task.assigned_user_id == user_id)

        due_reminders = list(db.scalars(stmt).all())
        metrics.evaluated = len(due_reminders)
        if not due_reminders:
            return metrics

        # Preload dedup keys to avoid N+1
        pairs = [(r.task.assigned_user_id, f"reminder:{r.id}:{r.remind_at.isoformat()}") for r in due_reminders if r.task.assigned_user_id]
        existing_keys = _preload_existing_dedup_keys(db, pairs)

        for reminder in due_reminders:
            target_user_id = reminder.task.assigned_user_id
            if not target_user_id:
                continue

            dedup = f"reminder:{reminder.id}:{reminder.remind_at.isoformat()}"
            try:
                with db.begin_nested():
                    if (target_user_id, dedup) in existing_keys:
                        metrics.duplicates_skipped += 1
                        reminder.is_sent = True
                        continue

                    if not should_notify_user(db, target_user_id, "reminder_due"):
                        metrics.preferences_suppressed += 1
                        reminder.is_sent = True
                        continue

                    notif = Notification(
                        user_id=target_user_id,
                        task_id=reminder.task.id,
                        type="reminder_due",
                        title=f"Reminder: {reminder.task.title}",
                        message=reminder.message,
                        dedup_key=dedup,
                        is_read=False,
                    )
                    db.add(notif)
                    reminder.is_sent = True
                    metrics.notifications_created += 1
                    existing_keys.add((target_user_id, dedup))
            except IntegrityError:
                # Handled by DB unique constraint race-safety
                metrics.duplicates_skipped += 1
                reminder.is_sent = True
            except Exception as e:
                logger.exception(f"Error evaluating reminder {reminder.id}: {e}")
                metrics.errors += 1

        return metrics

    @staticmethod
    def evaluate_follow_ups(
        db: Session,
        as_of: datetime,
        user_id: Optional[uuid.UUID] = None,
    ) -> CategoryEvaluationDetail:
        """Evaluate incomplete follow-ups scheduled on or before `as_of`."""
        metrics = CategoryEvaluationDetail()

        stmt = (
            select(FollowUp)
            .join(Task, FollowUp.task_id == Task.id)
            .options(joinedload(FollowUp.task))
            .where(
                FollowUp.completed_at.is_(None),
                FollowUp.scheduled_at <= as_of,
                Task.assigned_user_id.is_not(None),
            )
        )
        if user_id is not None:
            stmt = stmt.where(Task.assigned_user_id == user_id)

        due_follow_ups = list(db.scalars(stmt).all())
        metrics.evaluated = len(due_follow_ups)
        if not due_follow_ups:
            return metrics

        pairs = [(f.task.assigned_user_id, f"follow_up:{f.id}:{f.scheduled_at.isoformat()}") for f in due_follow_ups if f.task.assigned_user_id]
        existing_keys = _preload_existing_dedup_keys(db, pairs)

        for follow_up in due_follow_ups:
            target_user_id = follow_up.task.assigned_user_id
            if not target_user_id:
                continue

            dedup = f"follow_up:{follow_up.id}:{follow_up.scheduled_at.isoformat()}"
            try:
                with db.begin_nested():
                    if (target_user_id, dedup) in existing_keys:
                        metrics.duplicates_skipped += 1
                        continue

                    if not should_notify_user(db, target_user_id, "follow_up_due"):
                        metrics.preferences_suppressed += 1
                        continue

                    notif = Notification(
                        user_id=target_user_id,
                        task_id=follow_up.task.id,
                        type="follow_up_due",
                        title=f"Follow-up Due: {follow_up.task.title}",
                        message=follow_up.notes or "Scheduled follow-up action is due.",
                        dedup_key=dedup,
                        is_read=False,
                    )
                    db.add(notif)
                    metrics.notifications_created += 1
                    existing_keys.add((target_user_id, dedup))
            except IntegrityError:
                metrics.duplicates_skipped += 1
            except Exception as e:
                logger.exception(f"Error evaluating follow-up {follow_up.id}: {e}")
                metrics.errors += 1

        return metrics

    @staticmethod
    def evaluate_next_actions(
        db: Session,
        as_of: datetime,
        user_id: Optional[uuid.UUID] = None,
    ) -> CategoryEvaluationDetail:
        """Evaluate tasks whose next action date is due on or before `as_of`."""
        metrics = CategoryEvaluationDetail()

        stmt = (
            select(Task)
            .where(
                Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                Task.next_action_date.is_not(None),
                Task.next_action_date <= as_of,
                Task.assigned_user_id.is_not(None),
            )
        )
        if user_id is not None:
            stmt = stmt.where(Task.assigned_user_id == user_id)

        due_tasks = list(db.scalars(stmt).all())
        metrics.evaluated = len(due_tasks)
        if not due_tasks:
            return metrics

        pairs = [(t.assigned_user_id, f"next_action:{t.id}:{t.next_action_date.isoformat()}") for t in due_tasks if t.assigned_user_id and t.next_action_date]
        existing_keys = _preload_existing_dedup_keys(db, pairs)

        for task in due_tasks:
            if not task.assigned_user_id or not task.next_action_date:
                continue

            dedup = f"next_action:{task.id}:{task.next_action_date.isoformat()}"
            try:
                with db.begin_nested():
                    if (task.assigned_user_id, dedup) in existing_keys:
                        metrics.duplicates_skipped += 1
                        continue

                    if not should_notify_user(db, task.assigned_user_id, "next_action_due"):
                        metrics.preferences_suppressed += 1
                        continue

                    notif = Notification(
                        user_id=task.assigned_user_id,
                        task_id=task.id,
                        type="next_action_due",
                        title=f"Next Action Due: {task.title}",
                        message=f"Next action scheduled for {task.next_action_date.strftime('%Y-%m-%d %H:%M UTC')}.",
                        dedup_key=dedup,
                        is_read=False,
                    )
                    db.add(notif)
                    metrics.notifications_created += 1
                    existing_keys.add((task.assigned_user_id, dedup))
            except IntegrityError:
                metrics.duplicates_skipped += 1
            except Exception as e:
                logger.exception(f"Error evaluating next action for task {task.id}: {e}")
                metrics.errors += 1

        return metrics

    @staticmethod
    def evaluate_overdue_tasks(
        db: Session,
        as_of: datetime,
        user_id: Optional[uuid.UUID] = None,
    ) -> CategoryEvaluationDetail:
        """Evaluate overdue tasks whose due date is on or before `as_of`."""
        metrics = CategoryEvaluationDetail()

        stmt = (
            select(Task)
            .where(
                Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                Task.due_date.is_not(None),
                Task.due_date <= as_of,
                Task.assigned_user_id.is_not(None),
            )
        )
        if user_id is not None:
            stmt = stmt.where(Task.assigned_user_id == user_id)

        overdue_tasks = list(db.scalars(stmt).all())
        metrics.evaluated = len(overdue_tasks)
        if not overdue_tasks:
            return metrics

        pairs = [(t.assigned_user_id, f"task_overdue:{t.id}:{t.due_date.isoformat()}") for t in overdue_tasks if t.assigned_user_id and t.due_date]
        existing_keys = _preload_existing_dedup_keys(db, pairs)

        for task in overdue_tasks:
            if not task.assigned_user_id or not task.due_date:
                continue

            dedup = f"task_overdue:{task.id}:{task.due_date.isoformat()}"
            try:
                with db.begin_nested():
                    if (task.assigned_user_id, dedup) in existing_keys:
                        metrics.duplicates_skipped += 1
                        continue

                    if not should_notify_user(db, task.assigned_user_id, "task_overdue"):
                        metrics.preferences_suppressed += 1
                        continue

                    notif = Notification(
                        user_id=task.assigned_user_id,
                        task_id=task.id,
                        type="task_overdue",
                        title=f"Task Overdue: {task.title}",
                        message=f"Task passed its scheduled due date of {task.due_date.strftime('%Y-%m-%d %H:%M UTC')}.",
                        dedup_key=dedup,
                        is_read=False,
                    )
                    db.add(notif)
                    metrics.notifications_created += 1
                    existing_keys.add((task.assigned_user_id, dedup))
            except IntegrityError:
                metrics.duplicates_skipped += 1
            except Exception as e:
                logger.exception(f"Error evaluating overdue task {task.id}: {e}")
                metrics.errors += 1

        return metrics

    @staticmethod
    def evaluate_attempt_limits(
        db: Session,
        as_of: datetime,
        user_id: Optional[uuid.UUID] = None,
    ) -> CategoryEvaluationDetail:
        """Evaluate attempt limits: both max attempts reached and near max attempts."""
        metrics = CategoryEvaluationDetail()

        # 1. Max attempts reached (attempt_count >= max_attempts)
        stmt_max = (
            select(Task)
            .where(
                Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                Task.attempt_count >= Task.max_attempts,
                Task.assigned_user_id.is_not(None),
            )
        )
        if user_id is not None:
            stmt_max = stmt_max.where(Task.assigned_user_id == user_id)

        # 2. Near max attempts (attempt_count > 0 and attempt_count == max_attempts - 1)
        stmt_near = (
            select(Task)
            .where(
                Task.status.notin_([TaskStatus.COMPLETED, TaskStatus.CANCELLED]),
                Task.attempt_count > 0,
                Task.attempt_count == Task.max_attempts - 1,
                Task.assigned_user_id.is_not(None),
            )
        )
        if user_id is not None:
            stmt_near = stmt_near.where(Task.assigned_user_id == user_id)

        max_tasks = list(db.scalars(stmt_max).all())
        near_tasks = list(db.scalars(stmt_near).all())
        metrics.evaluated = len(max_tasks) + len(near_tasks)

        # Max attempts candidate keys
        pairs_max = [(t.assigned_user_id, f"attempt_limit:{t.id}:{t.attempt_count}") for t in max_tasks if t.assigned_user_id]
        pairs_near = [(t.assigned_user_id, f"near_max_attempts:{t.id}:{t.attempt_count}") for t in near_tasks if t.assigned_user_id]
        existing_keys = _preload_existing_dedup_keys(db, pairs_max + pairs_near)

        # Process max attempts
        for task in max_tasks:
            if not task.assigned_user_id:
                continue

            dedup = f"attempt_limit:{task.id}:{task.attempt_count}"
            try:
                with db.begin_nested():
                    if (task.assigned_user_id, dedup) in existing_keys:
                        metrics.duplicates_skipped += 1
                        continue

                    if not should_notify_user(db, task.assigned_user_id, "attempt_limit_reached"):
                        metrics.preferences_suppressed += 1
                        continue

                    notif = Notification(
                        user_id=task.assigned_user_id,
                        task_id=task.id,
                        type="attempt_limit_reached",
                        title=f"Max Attempts Reached: {task.title}",
                        message=f"Task reached maximum attempt limit ({task.attempt_count}/{task.max_attempts}). Authorized override required.",
                        dedup_key=dedup,
                        is_read=False,
                    )
                    db.add(notif)
                    metrics.notifications_created += 1
                    existing_keys.add((task.assigned_user_id, dedup))
            except IntegrityError:
                metrics.duplicates_skipped += 1
            except Exception as e:
                logger.exception(f"Error evaluating max attempts for task {task.id}: {e}")
                metrics.errors += 1

        # Process near max attempts
        for task in near_tasks:
            if not task.assigned_user_id:
                continue

            dedup = f"near_max_attempts:{task.id}:{task.attempt_count}"
            try:
                with db.begin_nested():
                    if (task.assigned_user_id, dedup) in existing_keys:
                        metrics.duplicates_skipped += 1
                        continue

                    if not should_notify_user(db, task.assigned_user_id, "attempt_limit_reached"):
                        metrics.preferences_suppressed += 1
                        continue

                    notif = Notification(
                        user_id=task.assigned_user_id,
                        task_id=task.id,
                        type="near_max_attempts",
                        title=f"Near Max Attempts: {task.title}",
                        message=f"Task '{task.title}' is nearing its maximum attempt limit ({task.attempt_count}/{task.max_attempts}).",
                        dedup_key=dedup,
                        is_read=False,
                    )
                    db.add(notif)
                    metrics.notifications_created += 1
                    existing_keys.add((task.assigned_user_id, dedup))
            except IntegrityError:
                metrics.duplicates_skipped += 1
            except Exception as e:
                logger.exception(f"Error evaluating near max attempts for task {task.id}: {e}")
                metrics.errors += 1

        return metrics

    @classmethod
    def evaluate_all(
        cls,
        db: Session,
        as_of: Optional[datetime] = None,
        user_id: Optional[uuid.UUID] = None,
    ) -> SchedulerEvaluationResponse:
        """Unified scheduling evaluation entrypoint.

        Evaluates reminders, follow-ups, next actions, overdue tasks, and attempt limits.
        Isolates record-level errors, records category metrics, and commits valid updates.
        """
        start_time = time.perf_counter()
        now = as_of or datetime.now(timezone.utc)
        if now.tzinfo is None:
            now = now.replace(tzinfo=timezone.utc)

        # 1. Reminders
        rem_metrics = cls.evaluate_reminders(db, now, user_id=user_id)

        # 2. Follow-ups
        fu_metrics = cls.evaluate_follow_ups(db, now, user_id=user_id)

        # 3. Next Actions
        na_metrics = cls.evaluate_next_actions(db, now, user_id=user_id)

        # 4. Overdue Tasks
        od_metrics = cls.evaluate_overdue_tasks(db, now, user_id=user_id)

        # 5. Attempt Limits
        al_metrics = cls.evaluate_attempt_limits(db, now, user_id=user_id)

        # Commit all successful database insertions/updates
        db.commit()

        details = {
            "reminders": rem_metrics,
            "follow_ups": fu_metrics,
            "next_actions": na_metrics,
            "overdue_tasks": od_metrics,
            "attempt_limits": al_metrics,
        }

        total_evaluated = sum(m.evaluated for m in details.values())
        total_created = sum(m.notifications_created for m in details.values())
        total_skipped = sum(m.duplicates_skipped for m in details.values())
        total_suppressed = sum(m.preferences_suppressed for m in details.values())
        total_errors = sum(m.errors for m in details.values())
        duration_ms = round((time.perf_counter() - start_time) * 1000.0, 2)

        return SchedulerEvaluationResponse(
            evaluated=total_evaluated,
            notifications_created=total_created,
            duplicates_skipped=total_skipped,
            preferences_suppressed=total_suppressed,
            errors_count=total_errors,
            duration_ms=duration_ms,
            evaluated_at=now,
            user_id=user_id,
            details=details,
        )
