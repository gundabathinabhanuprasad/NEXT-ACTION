"""MongoDB Report Service providing analytics, aggregations, and query fallbacks."""

from datetime import datetime, timedelta, timezone
import logging
from typing import Any, Dict, List, Optional, Union
import uuid

from app.models.enums import TaskPriority, TaskStatus
from app.repositories import (
    ClientRepository,
    TaskHistoryRepository,
    TaskRepository,
    UserRepository,
    WorkflowRepository,
)
from app.schemas.reports import (
    ActivityReportItem,
    ActivityReportResponse,
    FollowUpReportItem,
    ProductivityDailyTrendPoint,
    ProductivityReportResponse,
    ReminderFollowUpReportResponse,
    ReminderFollowUpSummary,
    ReminderReportItem,
    ReportFilterParams,
    TaskDetailReportItem,
    TaskDetailReportResponse,
    TaskSummaryPriorityBreakdown,
    TaskSummaryReport,
    TaskSummaryStatusBreakdown,
    WorkloadReportItem,
    WorkloadReportResponse,
)

logger = logging.getLogger("nextaction.persistence.mongodb.report")


def _build_task_filter_query(filters: Optional[ReportFilterParams], now: datetime) -> Dict[str, Any]:
    """Translate ReportFilterParams into a MongoDB query dictionary."""
    today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
    today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)

    query: Dict[str, Any] = {}
    and_clauses: List[Dict[str, Any]] = []

    if not filters:
        return query

    if filters.status:
        st = filters.status.value if hasattr(filters.status, "value") else str(filters.status)
        query["status"] = st

    if filters.priority:
        pr = filters.priority.value if hasattr(filters.priority, "value") else str(filters.priority)
        query["priority"] = pr

    if filters.client_id:
        query["client_id"] = str(filters.client_id)

    if filters.workflow_id:
        query["workflow_id"] = str(filters.workflow_id)

    if filters.unassigned is True:
        and_clauses.append({"$or": [{"assigned_user_id": None}, {"assigned_user_id": {"$exists": False}}]})
    elif filters.assigned_user_id:
        query["assigned_user_id"] = str(filters.assigned_user_id)

    if filters.date_from and filters.date_to:
        query["created_at"] = {"$gte": filters.date_from, "$lte": filters.date_to}
    elif filters.date_from:
        query["created_at"] = {"$gte": filters.date_from}
    elif filters.date_to:
        query["created_at"] = {"$lte": filters.date_to}

    if filters.overdue is True:
        query["due_date"] = {"$lt": now}
        query["status"] = {"$nin": ["completed", "cancelled"]}

    if filters.due_today is True:
        query["due_date"] = {"$gte": today_start, "$lte": today_end}
        query["status"] = {"$nin": ["completed", "cancelled"]}

    if filters.upcoming is True:
        query["due_date"] = {"$gt": now}
        query["status"] = {"$nin": ["completed", "cancelled"]}

    if filters.no_next_action is True or filters.has_next_action is False:
        and_clauses.append({"$or": [{"next_action_date": None}, {"next_action_date": {"$exists": False}}]})
    elif filters.has_next_action is True:
        query["next_action_date"] = {"$ne": None, "$exists": True}

    if filters.near_max_attempts is True:
        query["status"] = {"$nin": ["completed", "cancelled"]}
        query["$expr"] = {"$gte": ["$attempt_count", {"$subtract": ["$max_attempts", 1]}]}

    if filters.source:
        if filters.source == "manual":
            query["template_id"] = None
            query["recurring_task_id"] = None
        elif filters.source == "template":
            query["template_id"] = {"$ne": None}
        elif filters.source == "recurring":
            query["recurring_task_id"] = {"$ne": None}

    if filters.search and filters.search.strip():
        term = filters.search.strip()
        reg = {"$regex": term, "$options": "i"}
        search_or = [
            {"title": reg},
            {"description": reg},
            {"subject_line": reg},
            {"client_name": reg},
            {"workflow_name": reg},
            {"assigned_user_name": reg},
            {"assigned_user_email": reg},
        ]
        and_clauses.append({"$or": search_or})

    if and_clauses:
        if "$and" in query:
            query["$and"].extend(and_clauses)
        else:
            query["$and"] = and_clauses

    return query


class MongoReportService:
    """MongoDB implementation for all management reporting and export features."""

    def __init__(
        self,
        task_repo: Optional[TaskRepository] = None,
        history_repo: Optional[TaskHistoryRepository] = None,
        user_repo: Optional[UserRepository] = None,
        client_repo: Optional[ClientRepository] = None,
        workflow_repo: Optional[WorkflowRepository] = None,
    ):
        self.task_repo = task_repo or TaskRepository()
        self.history_repo = history_repo or TaskHistoryRepository()
        self.user_repo = user_repo or UserRepository()
        self.client_repo = client_repo or ClientRepository()
        self.workflow_repo = workflow_repo or WorkflowRepository()

    def get_task_summary_report(
        self,
        filters: Optional[ReportFilterParams] = None,
    ) -> TaskSummaryReport:
        """Compute aggregated task metrics and distributions in MongoDB."""
        now = datetime.now(timezone.utc)
        today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
        today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)

        match_query = _build_task_filter_query(filters, now)
        pipeline = [
            {"$match": match_query} if match_query else {"$match": {}},
            {"$group": {
                "_id": None,
                "total_tasks": {"$sum": 1},
                "open_tasks": {"$sum": {"$cond": [{"$in": ["$status", ["pending", "in_progress"]]}, 1, 0]}},
                "completed_tasks": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
                "cancelled_tasks": {"$sum": {"$cond": [{"$eq": ["$status", "cancelled"]}, 1, 0]}},
                "overdue_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$lt": ["$due_date", now]},
                    ]},
                    1,
                    0,
                ]}},
                "due_today_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$gte": ["$due_date", today_start]},
                        {"$lte": ["$due_date", today_end]},
                    ]},
                    1,
                    0,
                ]}},
                "upcoming_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$gt": ["$due_date", now]},
                    ]},
                    1,
                    0,
                ]}},
                "near_max_attempts": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$gte": ["$attempt_count", {"$subtract": ["$max_attempts", 1]}]},
                    ]},
                    1,
                    0,
                ]}},
                "max_attempts_reached": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$gte": ["$attempt_count", "$max_attempts"]},
                    ]},
                    1,
                    0,
                ]}},
                "pending": {"$sum": {"$cond": [{"$eq": ["$status", "pending"]}, 1, 0]}},
                "in_progress": {"$sum": {"$cond": [{"$eq": ["$status", "in_progress"]}, 1, 0]}},
                "completed": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
                "cancelled": {"$sum": {"$cond": [{"$eq": ["$status", "cancelled"]}, 1, 0]}},
                "urgent": {"$sum": {"$cond": [{"$eq": ["$priority", "urgent"]}, 1, 0]}},
                "high": {"$sum": {"$cond": [{"$eq": ["$priority", "high"]}, 1, 0]}},
                "medium": {"$sum": {"$cond": [{"$eq": ["$priority", "medium"]}, 1, 0]}},
                "low": {"$sum": {"$cond": [{"$eq": ["$priority", "low"]}, 1, 0]}},
            }},
        ]

        results = list(self.task_repo.collection.aggregate(pipeline))
        row = results[0] if results else {}

        return TaskSummaryReport(
            total_tasks=row.get("total_tasks", 0),
            open_tasks=row.get("open_tasks", 0),
            completed_tasks=row.get("completed_tasks", 0),
            cancelled_tasks=row.get("cancelled_tasks", 0),
            overdue_tasks=row.get("overdue_tasks", 0),
            due_today_tasks=row.get("due_today_tasks", 0),
            upcoming_tasks=row.get("upcoming_tasks", 0),
            near_max_attempts=row.get("near_max_attempts", 0),
            max_attempts_reached=row.get("max_attempts_reached", 0),
            status_breakdown=TaskSummaryStatusBreakdown(
                pending=row.get("pending", 0),
                in_progress=row.get("in_progress", 0),
                completed=row.get("completed", 0),
                cancelled=row.get("cancelled", 0),
            ),
            priority_breakdown=TaskSummaryPriorityBreakdown(
                urgent=row.get("urgent", 0),
                high=row.get("high", 0),
                medium=row.get("medium", 0),
                low=row.get("low", 0),
            ),
        )

    def get_task_detail_report(
        self,
        filters: Optional[ReportFilterParams] = None,
        sort_by: str = "created_at",
        sort_order: str = "desc",
        page: int = 1,
        page_size: int = 20,
    ) -> TaskDetailReportResponse:
        """Retrieve paginated, enriched task detail records from MongoDB."""
        now = datetime.now(timezone.utc)
        match_query = _build_task_filter_query(filters, now)

        total = self.task_repo.collection.count_documents(match_query)

        sort_dir = 1 if sort_order.lower() == "asc" else -1
        allowed_sorts = {
            "created_at", "updated_at", "due_date", "next_action_date",
            "priority", "status", "title", "attempt_count",
        }
        sort_key = sort_by if sort_by in allowed_sorts else "created_at"

        skip = max(0, (page - 1) * page_size)
        cursor = (
            self.task_repo.collection.find(match_query)
            .sort([(sort_key, sort_dir), ("created_at", -1)])
            .skip(skip)
            .limit(page_size)
        )

        items: List[TaskDetailReportItem] = []
        for doc in cursor:
            source = "manual"
            if doc.get("recurring_task_id"):
                source = "recurring"
            elif doc.get("template_id"):
                source = "template"

            status_val = doc.get("status", "pending")
            priority_val = doc.get("priority", "medium")

            items.append(
                TaskDetailReportItem(
                    id=str(doc.get("_id", "")),
                    title=doc.get("title", ""),
                    subject_line=doc.get("subject_line"),
                    description=doc.get("description"),
                    status=TaskStatus(status_val) if status_val in TaskStatus._value2member_map_ else TaskStatus.PENDING,
                    priority=TaskPriority(priority_val) if priority_val in TaskPriority._value2member_map_ else TaskPriority.MEDIUM,
                    client_id=doc.get("client_id"),
                    client_name=doc.get("client_name"),
                    workflow_id=doc.get("workflow_id"),
                    workflow_name=doc.get("workflow_name"),
                    assigned_user_id=doc.get("assigned_user_id"),
                    assigned_user_name=doc.get("assigned_user_name"),
                    assigned_user_email=doc.get("assigned_user_email"),
                    due_date=doc.get("due_date"),
                    next_action_date=doc.get("next_action_date"),
                    attempt_count=doc.get("attempt_count", 0),
                    max_attempts=doc.get("max_attempts", 2),
                    created_at=doc.get("created_at") or now,
                    updated_at=doc.get("updated_at") or now,
                    completed_at=doc.get("completed_at"),
                    source=source,
                )
            )

        return TaskDetailReportResponse(
            items=items,
            total=total,
            page=page,
            page_size=page_size,
        )

    def get_productivity_report(
        self,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        filters: Optional[ReportFilterParams] = None,
    ) -> ProductivityReportResponse:
        """Compute productivity velocity and completion rate metrics with daily trend series."""
        now = datetime.now(timezone.utc)
        if date_to is None:
            date_to = now.replace(hour=23, minute=59, second=59, microsecond=999999)
        if date_from is None:
            date_from = (date_to - timedelta(days=29)).replace(hour=0, minute=0, second=0, microsecond=0)

        if date_from > date_to:
            date_from, date_to = date_to, date_from

        base_filter: Dict[str, Any] = {}
        if filters:
            if filters.client_id:
                base_filter["client_id"] = str(filters.client_id)
            if filters.workflow_id:
                base_filter["workflow_id"] = str(filters.workflow_id)
            if filters.unassigned is True:
                base_filter["$or"] = [{"assigned_user_id": None}, {"assigned_user_id": {"$exists": False}}]
            elif filters.assigned_user_id:
                base_filter["assigned_user_id"] = str(filters.assigned_user_id)

        # 1. Created tasks per day
        created_match = {
            **base_filter,
            "created_at": {"$gte": date_from, "$lte": date_to},
        }
        created_pipeline = [
            {"$match": created_match},
            {"$group": {
                "_id": {"$dateToString": {"format": "%Y-%m-%d", "date": "$created_at"}},
                "cnt": {"$sum": 1},
            }},
        ]
        created_map = {row["_id"]: row["cnt"] for row in self.task_repo.collection.aggregate(created_pipeline) if row["_id"]}

        # 2. Completed tasks per day
        completed_match = {
            **base_filter,
            "completed_at": {"$gte": date_from, "$lte": date_to},
        }
        completed_pipeline = [
            {"$match": completed_match},
            {"$group": {
                "_id": {"$dateToString": {"format": "%Y-%m-%d", "date": "$completed_at"}},
                "cnt": {"$sum": 1},
            }},
        ]
        completed_map = {row["_id"]: row["cnt"] for row in self.task_repo.collection.aggregate(completed_pipeline) if row["_id"]}

        # 3. Overdue tasks per day (due_date in day, and (status in pending/in_progress or completed_at > due_date))
        overdue_match = {
            **base_filter,
            "due_date": {"$gte": date_from, "$lte": date_to},
            "$or": [
                {"status": {"$in": ["pending", "in_progress"]}},
                {"$expr": {"$gt": ["$completed_at", "$due_date"]}},
            ],
        }
        overdue_pipeline = [
            {"$match": overdue_match},
            {"$group": {
                "_id": {"$dateToString": {"format": "%Y-%m-%d", "date": "$due_date"}},
                "cnt": {"$sum": 1},
            }},
        ]
        overdue_map = {row["_id"]: row["cnt"] for row in self.task_repo.collection.aggregate(overdue_pipeline) if row["_id"]}

        # Fill daily trends
        cur = date_from.date()
        end_date = date_to.date()
        daily_trends: List[ProductivityDailyTrendPoint] = []
        total_created = 0
        total_completed = 0
        total_overdue = 0

        while cur <= end_date:
            d_str = cur.strftime("%Y-%m-%d")
            c_cnt = created_map.get(d_str, 0)
            cmp_cnt = completed_map.get(d_str, 0)
            ovd_cnt = overdue_map.get(d_str, 0)

            total_created += c_cnt
            total_completed += cmp_cnt
            total_overdue += ovd_cnt

            rate = round((cmp_cnt / c_cnt * 100.0), 1) if c_cnt > 0 else (100.0 if cmp_cnt > 0 else 0.0)

            daily_trends.append(
                ProductivityDailyTrendPoint(
                    date=d_str,
                    created_count=c_cnt,
                    completed_count=cmp_cnt,
                    overdue_count=ovd_cnt,
                    completion_rate=rate,
                )
            )
            cur += timedelta(days=1)

        overall_rate = round((total_completed / total_created * 100.0), 1) if total_created > 0 else (100.0 if total_completed > 0 else 0.0)

        return ProductivityReportResponse(
            date_from=date_from,
            date_to=date_to,
            total_created=total_created,
            total_completed=total_completed,
            total_overdue=total_overdue,
            overall_completion_rate=overall_rate,
            daily_trends=daily_trends,
        )

    def get_workload_report(
        self,
        filters: Optional[ReportFilterParams] = None,
    ) -> WorkloadReportResponse:
        """Compute operational workloads partitioned across Assignees, Clients, and Workflows."""
        now = datetime.now(timezone.utc)
        today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
        today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)
        col = self.task_repo.collection

        # 1. By Assignee
        assignee_pipeline = [
            {"$group": {
                "_id": {"id": "$assigned_user_id", "name": "$assigned_user_name", "email": "$assigned_user_email"},
                "open_tasks": {"$sum": {"$cond": [{"$in": ["$status", ["pending", "in_progress"]]}, 1, 0]}},
                "completed_tasks": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
                "overdue_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$lt": ["$due_date", now]},
                    ]},
                    1,
                    0,
                ]}},
                "due_today_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$gte": ["$due_date", today_start]},
                        {"$lte": ["$due_date", today_end]},
                    ]},
                    1,
                    0,
                ]}},
                "total_tasks": {"$sum": 1},
            }},
            {"$sort": {"open_tasks": -1}},
        ]
        assignee_docs = list(col.aggregate(assignee_pipeline))
        by_assignee: List[WorkloadReportItem] = []
        for ad in assignee_docs:
            u_id = ad["_id"].get("id")
            u_name = ad["_id"].get("name") or ("Unassigned" if u_id is None else "Former user")
            u_email = ad["_id"].get("email")

            by_assignee.append(
                WorkloadReportItem(
                    id=u_id,
                    name=u_name,
                    email=u_email,
                    open_tasks=ad["open_tasks"],
                    completed_tasks=ad["completed_tasks"],
                    overdue_tasks=ad["overdue_tasks"],
                    due_today_tasks=ad["due_today_tasks"],
                    total_tasks=ad["total_tasks"],
                )
            )

        # Sort assignee: highest open tasks first, then unassigned last
        by_assignee.sort(key=lambda x: (x.id is None, -(x.open_tasks or 0), x.name))

        # 2. By Client
        client_pipeline = [
            {"$match": {"client_id": {"$ne": None}}},
            {"$group": {
                "_id": {"id": "$client_id", "name": "$client_name"},
                "open_tasks": {"$sum": {"$cond": [{"$in": ["$status", ["pending", "in_progress"]]}, 1, 0]}},
                "completed_tasks": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
                "overdue_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$lt": ["$due_date", now]},
                    ]},
                    1,
                    0,
                ]}},
                "due_today_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$gte": ["$due_date", today_start]},
                        {"$lte": ["$due_date", today_end]},
                    ]},
                    1,
                    0,
                ]}},
                "total_tasks": {"$sum": 1},
            }},
            {"$sort": {"open_tasks": -1}},
            {"$limit": 100},
        ]
        client_docs = list(col.aggregate(client_pipeline))
        by_client: List[WorkloadReportItem] = [
            WorkloadReportItem(
                id=cd["_id"]["id"],
                name=cd["_id"].get("name") or "Unknown Client",
                open_tasks=cd["open_tasks"],
                completed_tasks=cd["completed_tasks"],
                overdue_tasks=cd["overdue_tasks"],
                due_today_tasks=cd["due_today_tasks"],
                total_tasks=cd["total_tasks"],
            )
            for cd in client_docs if cd["_id"].get("id")
        ]

        # 3. By Workflow
        workflow_pipeline = [
            {"$match": {"workflow_id": {"$ne": None}}},
            {"$group": {
                "_id": {"id": "$workflow_id", "name": "$workflow_name"},
                "open_tasks": {"$sum": {"$cond": [{"$in": ["$status", ["pending", "in_progress"]]}, 1, 0]}},
                "completed_tasks": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
                "overdue_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$lt": ["$due_date", now]},
                    ]},
                    1,
                    0,
                ]}},
                "due_today_tasks": {"$sum": {"$cond": [
                    {"$and": [
                        {"$in": ["$status", ["pending", "in_progress"]]},
                        {"$gte": ["$due_date", today_start]},
                        {"$lte": ["$due_date", today_end]},
                    ]},
                    1,
                    0,
                ]}},
                "total_tasks": {"$sum": 1},
            }},
            {"$sort": {"open_tasks": -1}},
            {"$limit": 100},
        ]
        workflow_docs = list(col.aggregate(workflow_pipeline))
        by_workflow: List[WorkloadReportItem] = [
            WorkloadReportItem(
                id=wd["_id"]["id"],
                name=wd["_id"].get("name") or "Unknown Workflow",
                open_tasks=wd["open_tasks"],
                completed_tasks=wd["completed_tasks"],
                overdue_tasks=wd["overdue_tasks"],
                due_today_tasks=wd["due_today_tasks"],
                total_tasks=wd["total_tasks"],
            )
            for wd in workflow_docs if wd["_id"].get("id")
        ]

        total_open = sum(item.open_tasks for item in by_assignee)
        total_completed = sum(item.completed_tasks for item in by_assignee)
        total_overdue = sum(item.overdue_tasks for item in by_assignee)
        total_all = sum(item.total_tasks for item in by_assignee)

        return WorkloadReportResponse(
            by_assignee=by_assignee,
            by_client=by_client,
            by_workflow=by_workflow,
            total_open_tasks=total_open,
            total_completed_tasks=total_completed,
            total_overdue_tasks=total_overdue,
            total_tasks=total_all,
        )

    def get_activity_report(
        self,
        action: Optional[str] = None,
        actor_id: Optional[Union[uuid.UUID, str]] = None,
        task_id: Optional[Union[uuid.UUID, str]] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        search: Optional[str] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> ActivityReportResponse:
        """Retrieve audit history entries with action counts and actor details."""
        query: Dict[str, Any] = {}
        if action and action.strip():
            query["action"] = action.strip().lower()
        if actor_id:
            query["created_by_user_id"] = str(actor_id)
        if task_id:
            query["task_id"] = str(task_id)
        if date_from and date_to:
            query["created_at"] = {"$gte": date_from, "$lte": date_to}
        elif date_from:
            query["created_at"] = {"$gte": date_from}
        elif date_to:
            query["created_at"] = {"$lte": date_to}

        if search and search.strip():
            term = search.strip()
            reg = {"$regex": term, "$options": "i"}
            query["$or"] = [
                {"action": reg},
                {"reason": reg},
                {"old_value": reg},
                {"new_value": reg},
            ]

        col = self.history_repo.collection
        total = col.count_documents(query)

        # Action counts
        action_pipeline = [
            {"$group": {"_id": "$action", "cnt": {"$sum": 1}}},
        ]
        action_counts = {row["_id"]: row["cnt"] for row in col.aggregate(action_pipeline) if row["_id"]}

        skip = max(0, (page - 1) * page_size)
        cursor = col.find(query).sort([("created_at", -1), ("_id", -1)]).skip(skip).limit(page_size)
        docs = list(cursor)

        # Batch resolve task titles and user details
        t_ids = list({d.get("task_id") for d in docs if d.get("task_id")})
        u_ids = list({d.get("created_by_user_id") for d in docs if d.get("created_by_user_id")})

        task_title_map: Dict[str, str] = {}
        if t_ids:
            for t in self.task_repo.collection.find({"_id": {"$in": t_ids}}, {"title": 1}):
                task_title_map[str(t["_id"])] = t.get("title", "")

        user_map: Dict[str, Dict[str, Any]] = {}
        if u_ids:
            for u in self.user_repo.collection.find({"_id": {"$in": u_ids}}, {"name": 1, "email": 1}):
                user_map[str(u["_id"])] = u

        items: List[ActivityReportItem] = []
        for d in docs:
            act_user_id = d.get("created_by_user_id")
            user_doc = user_map.get(str(act_user_id)) if act_user_id else None
            actor_name = user_doc.get("name") if user_doc else ("Former user" if act_user_id else "System")
            actor_email = user_doc.get("email") if user_doc else None
            task_t = task_title_map.get(str(d.get("task_id"))) if d.get("task_id") else None

            items.append(
                ActivityReportItem(
                    id=str(d.get("_id", "")),
                    task_id=d.get("task_id"),
                    task_title=task_t,
                    action=d.get("action", ""),
                    actor_id=act_user_id,
                    actor_name=actor_name,
                    actor_email=actor_email,
                    old_value=d.get("old_value"),
                    new_value=d.get("new_value"),
                    reason=d.get("reason"),
                    created_at=d.get("created_at") or datetime.now(timezone.utc),
                )
            )

        return ActivityReportResponse(
            items=items,
            total=total,
            page=page,
            page_size=page_size,
            action_counts=action_counts,
        )

    def get_reminders_followups_report(
        self,
        filters: Optional[ReportFilterParams] = None,
    ) -> ReminderFollowUpReportResponse:
        """Compute reminder and follow-up queue metrics and detailed items."""
        now = datetime.now(timezone.utc)
        today_start = datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=timezone.utc)
        today_end = datetime(now.year, now.month, now.day, 23, 59, 59, 999999, tzinfo=timezone.utc)
        col = self.task_repo.collection

        base_match: Dict[str, Any] = {}
        if filters:
            if filters.client_id:
                base_match["client_id"] = str(filters.client_id)
            if filters.workflow_id:
                base_match["workflow_id"] = str(filters.workflow_id)
            if filters.assigned_user_id:
                base_match["assigned_user_id"] = str(filters.assigned_user_id)

        # 1. Reminders
        rem_match = {**base_match, "reminders.0": {"$exists": True}}
        rem_pipeline = [
            {"$match": rem_match},
            {"$unwind": "$reminders"},
            {"$project": {
                "task_id": {"$ifNull": ["$reminders.task_id", {"$toString": "$_id"}]},
                "task_title": "$title",
                "remind_at": "$reminders.remind_at",
                "message": "$reminders.message",
                "is_sent": "$reminders.is_sent",
                "created_at": "$reminders.created_at",
                "id": "$reminders._id",
            }},
            {"$sort": {"created_at": -1, "remind_at": 1}},
        ]
        all_rems = list(col.aggregate(rem_pipeline))

        reminders_due = 0
        reminders_sent = 0
        reminders_pending = 0
        rem_items: List[ReminderReportItem] = []

        for r in all_rems:
            is_sent = bool(r.get("is_sent", False))
            r_at = r.get("remind_at")
            if is_sent:
                reminders_sent += 1
            else:
                reminders_pending += 1
                if r_at:
                    r_at_utc = r_at.replace(tzinfo=timezone.utc) if r_at.tzinfo is None else r_at
                    if r_at_utc <= now:
                        reminders_due += 1

            if len(rem_items) < 100:
                rem_items.append(
                    ReminderReportItem(
                        id=str(r.get("id") or r.get("_id") or uuid.uuid4()),
                        task_id=str(r.get("task_id") or ""),
                        task_title=r.get("task_title") or "Deleted Task",
                        remind_at=r.get("remind_at") or now,
                        is_sent=is_sent,
                        message=r.get("message") or "Reminder alert",
                        created_at=r.get("created_at") or now,
                    )
                )

        # 2. Follow-ups
        fu_match = {**base_match, "follow_ups.0": {"$exists": True}}
        fu_pipeline = [
            {"$match": fu_match},
            {"$unwind": "$follow_ups"},
            {"$project": {
                "task_id": {"$ifNull": ["$follow_ups.task_id", {"$toString": "$_id"}]},
                "task_title": "$title",
                "scheduled_at": "$follow_ups.scheduled_at",
                "completed_at": "$follow_ups.completed_at",
                "notes": "$follow_ups.notes",
                "created_at": "$follow_ups.created_at",
                "id": "$follow_ups._id",
            }},
            {"$sort": {"created_at": -1, "scheduled_at": 1}},
        ]
        all_fus = list(col.aggregate(fu_pipeline))

        follow_ups_overdue = 0
        follow_ups_today = 0
        follow_ups_upcoming = 0
        follow_ups_completed = 0
        follow_ups_pending = 0
        fu_items: List[FollowUpReportItem] = []

        for f in all_fus:
            cmp_at = f.get("completed_at")
            is_cmp = cmp_at is not None
            sch_at = f.get("scheduled_at")
            if is_cmp:
                follow_ups_completed += 1
            else:
                follow_ups_pending += 1
                if sch_at:
                    sch_at_utc = sch_at.replace(tzinfo=timezone.utc) if sch_at.tzinfo is None else sch_at
                    if sch_at_utc < today_start:
                        follow_ups_overdue += 1
                    elif sch_at_utc <= today_end:
                        follow_ups_today += 1
                    else:
                        follow_ups_upcoming += 1

            if len(fu_items) < 100:
                fu_items.append(
                    FollowUpReportItem(
                        id=str(f.get("id") or f.get("_id") or uuid.uuid4()),
                        task_id=str(f.get("task_id") or ""),
                        task_title=f.get("task_title") or "Deleted Task",
                        scheduled_at=f.get("scheduled_at") or now,
                        completed_at=cmp_at,
                        notes=f.get("notes"),
                        is_completed=is_cmp,
                        created_at=f.get("created_at") or now,
                    )
                )

        summary = ReminderFollowUpSummary(
            reminders_due=reminders_due,
            reminders_sent=reminders_sent,
            reminders_pending=reminders_pending,
            reminders_total=len(all_rems),
            follow_ups_overdue=follow_ups_overdue,
            follow_ups_today=follow_ups_today,
            follow_ups_upcoming=follow_ups_upcoming,
            follow_ups_completed=follow_ups_completed,
            follow_ups_pending=follow_ups_pending,
            follow_ups_total=len(all_fus),
        )

        return ReminderFollowUpReportResponse(
            summary=summary,
            reminders=rem_items,
            follow_ups=fu_items,
        )
