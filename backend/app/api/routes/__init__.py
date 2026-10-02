"""API routes package."""

from app.api.routes.auth import router as auth_router
from app.api.routes.clients import router as clients_router
from app.api.routes.follow_ups import router as follow_ups_router
from app.api.routes.notifications import router as notifications_router
from app.api.routes.recurring_tasks import router as recurring_tasks_router
from app.api.routes.reminders import router as reminders_router
from app.api.routes.task_templates import router as task_templates_router
from app.api.routes.tasks import router as tasks_router
from app.api.routes.users import router as users_router
from app.api.routes.workflows import router as workflows_router

__all__ = [
    "auth_router",
    "users_router",
    "tasks_router",
    "reminders_router",
    "follow_ups_router",
    "clients_router",
    "workflows_router",
    "notifications_router",
    "task_templates_router",
    "recurring_tasks_router",
]

