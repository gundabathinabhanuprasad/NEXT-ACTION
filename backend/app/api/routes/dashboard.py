"""Dashboard and Productivity Analytics API routes."""

from fastapi import APIRouter, Query, status
from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.dashboard import DashboardSummaryResponse

router = APIRouter(prefix="/dashboard", tags=["Dashboard & Productivity Analytics"])


@router.get(
    "/summary",
    response_model=DashboardSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Get consolidated dashboard summary and analytics",
)
def get_dashboard_summary_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    time_range: str = Query(
        "last_7_days",
        pattern="^(today|last_7_days|last_30_days|this_month)$",
        description="Time range for trend calculations and in-range metrics (today, last_7_days, last_30_days, this_month)",
    ),
) -> DashboardSummaryResponse:
    """Retrieve consolidated operational KPIs, status/priority distributions, attempt pressure,

    workload breakdown across assignees/clients/workflows, scheduling analytics, and trend curves.
    """
    from app.services.dashboard_service import get_dashboard_summary

    return get_dashboard_summary(
        db=db,
        user_id=current_user.id,
        time_range=time_range,
    )
