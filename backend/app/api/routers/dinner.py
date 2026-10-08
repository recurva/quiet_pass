import uuid

from fastapi import APIRouter, Depends
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.user import User
from app.schemas.dinner import DinnerResponseRead, DinnerSet, DinnerTallyRead
from app.services import dinner_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}/dinner", tags=["dinner"])


@router.put("", response_model=DinnerResponseRead)
async def set_my_dinner_status(
    group_id: uuid.UUID,
    payload: DinnerSet,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> DinnerResponseRead:
    """Set (or change) the caller's own dinner response for today. No
    cutoff enforcement here — the 5pm cutoff is soft by design, shown to
    the UI as `cutoff_passed` on the tally below, never a 4xx.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await dinner_service.set_dinner_status(
        db, redis, group_id=group_id, user_id=current_user.id, status=payload.status
    )


@router.get("", response_model=DinnerTallyRead)
async def get_dinner_tally(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DinnerTallyRead:
    """Today's full tally — every response so far, who's in, who's out,
    and whether the soft cutoff has passed."""
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await dinner_service.get_tally(db, group_id=group_id)
