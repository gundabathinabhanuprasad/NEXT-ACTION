"""Central API router aggregating all v1 sub-routers."""

from fastapi import APIRouter
from app.api.routes.activity import router as activity_router
from app.api.routes.auth import router as auth_router
from app.api.routes.clients import router as clients_router
from app.api.routes.dashboard import router as dashboard_router
from app.api.routes.follow_ups import router as follow_ups_router
from app.api.routes.notifications import router as notifications_router
from app.api.routes.recurring_tasks import router as recurring_tasks_router
from app.api.routes.reminders import router as reminders_router
from app.api.routes.reports import router as reports_router
from app.api.routes.scheduler import router as scheduler_router
from app.api.routes.settings import router as settings_router
from app.api.routes.task_templates import router as task_templates_router
from app.api.routes.tasks import router as tasks_router
from app.api.routes.users import router as users_router
from app.api.routes.workflows import router as workflows_router

api_v1_router = APIRouter(prefix="/api/v1")
api_v1_router.include_router(auth_router)
api_v1_router.include_router(users_router)
api_v1_router.include_router(clients_router)
api_v1_router.include_router(workflows_router)
api_v1_router.include_router(task_templates_router)
api_v1_router.include_router(recurring_tasks_router)
api_v1_router.include_router(tasks_router)
api_v1_router.include_router(reminders_router)
api_v1_router.include_router(follow_ups_router)
api_v1_router.include_router(notifications_router)
api_v1_router.include_router(activity_router)
api_v1_router.include_router(dashboard_router)
api_v1_router.include_router(reports_router)
api_v1_router.include_router(scheduler_router)
api_v1_router.include_router(settings_router)

__all__ = ["api_v1_router"]
