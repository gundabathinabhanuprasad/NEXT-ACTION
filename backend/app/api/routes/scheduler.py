"""Scheduler and Automated Notification Delivery API endpoints."""

from typing import Optional
from fastapi import APIRouter, Depends, status

from app.api.dependencies import CurrentUserDep, DatabaseDep
from app.schemas.scheduler import SchedulerEvaluationRequest, SchedulerEvaluationResponse
from app.services.scheduling_service import SchedulingService

router = APIRouter(prefix="/scheduler", tags=["Scheduler"])


@router.post(
    "/evaluate",
    response_model=SchedulerEvaluationResponse,
    status_code=status.HTTP_200_OK,
    summary="Trigger automated reminder and notification evaluation",
)
def evaluate_scheduler_endpoint(
    db: DatabaseDep,
    current_user: CurrentUserDep,
    request: Optional[SchedulerEvaluationRequest] = None,
) -> SchedulerEvaluationResponse:
    """Trigger the production scheduling engine.

    Evaluates:
    - Reminders due
    - Follow-ups due
    - Next actions due
    - Overdue tasks
    - Attempt limit alerts (near max and max attempts)

    Guarantees:
    - Idempotent and deterministic deduplication via PostgreSQL unique constraint
    - User notification preferences respected (Phase 18)
    - TaskHistory audit trail fully preserved
    - Safe transaction boundaries with failure isolation
    - Returns structured diagnostic metrics without exposing internal database details
    """
    as_of = request.as_of if request else None
    # Security: REST API trigger is strictly isolated to the authenticated user
    target_user_id = current_user.id

    return SchedulingService.evaluate_all(
        db=db,
        as_of=as_of,
        user_id=target_user_id,
    )
