import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.membership import MembershipRole
from app.models.recurring_series import RecurringSeries
from app.models.space import Space
from app.models.user import User
from app.schemas.recurring_series import (
    RecurringSeriesCancelResult,
    RecurringSeriesCreate,
    RecurringSeriesCreateResult,
    RecurringSeriesRead,
)
from app.services import recurring_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}", tags=["recurring"])


@router.post(
    "/spaces/{space_id}/recurring-series",
    response_model=RecurringSeriesCreateResult,
    status_code=status.HTTP_201_CREATED,
)
async def create_recurring_series(
    group_id: uuid.UUID,
    space_id: uuid.UUID,
    payload: RecurringSeriesCreate,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> RecurringSeriesCreateResult:
    """Creates the series and books every free occurrence in the horizon
    up front. `skipped` lists any occurrence that lost to an existing
    booking — the series is still created and its free occurrences are
    still booked; see recurring_service's module docstring for why this
    isn't all-or-nothing.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)

    space = await db.get(Space, space_id)
    if space is None or space.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Space not found.")

    try:
        series, created, skipped = await recurring_service.create_recurring_series(
            db, redis, group_id=group_id, space=space, user_id=current_user.id, payload=payload
        )
    except recurring_service.RecurringWeeklyCapError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    return RecurringSeriesCreateResult(series=series, created=created, skipped=skipped)


@router.get("/recurring-series", response_model=list[RecurringSeriesRead])
async def list_my_recurring_series(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[RecurringSeriesRead]:
    """Only the caller's own series — same "view your own stuff" scope as
    the rest of the app's per-user data.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await recurring_service.list_my_recurring_series(db, group_id, current_user.id)


@router.delete("/recurring-series/{series_id}", response_model=RecurringSeriesCancelResult)
async def cancel_recurring_series(
    group_id: uuid.UUID,
    series_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> RecurringSeriesCancelResult:
    """Cancels every future occurrence and the series itself. Only the
    series owner or an admin may cancel it.
    """
    membership = await require_membership(db, group_id=group_id, user_id=current_user.id)

    series = await db.get(RecurringSeries, series_id)
    if series is None or series.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recurring series not found.")
    if series.user_id != current_user.id and membership.role != MembershipRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the person who created this series, or an admin, can cancel it.",
        )

    try:
        cancelled_ids = await recurring_service.cancel_series(db, redis, group_id, series_id)
    except recurring_service.RecurringSeriesNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return RecurringSeriesCancelResult(series_id=series_id, cancelled_occurrence_ids=cancelled_ids)
