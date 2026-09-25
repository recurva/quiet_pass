import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.user import User
from app.schemas.nudge import NudgeRead, NudgeSend
from app.services import nudge_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}/nudges", tags=["nudges"])


@router.post("", response_model=NudgeRead, status_code=status.HTTP_201_CREATED)
async def send_nudge(
    group_id: uuid.UUID,
    payload: NudgeSend,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> NudgeRead:
    """Send a nudge to the group. The caller must be a member; the response
    (and what's broadcast to everyone else) never names the sender.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)

    try:
        return await nudge_service.send_nudge(
            redis,
            db,
            group_id=group_id,
            sender_id=current_user.id,
            nudge_type=payload.type,
            duration_minutes=int(payload.duration_minutes) if payload.duration_minutes else None,
            custom_message=payload.message,
        )
    except nudge_service.QuietPulseCooldownError as exc:
        logger.warning(
            "nudge.cooldown_blocked",
            group_id=str(group_id),
            user_id=str(current_user.id),
            retry_after_seconds=exc.retry_after_seconds,
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"You can send another quiet pulse in {exc.retry_after_seconds} seconds."
            ),
        ) from exc
    except nudge_service.QuietPulseDailyCapError as exc:
        logger.warning(
            "nudge.daily_cap_blocked",
            group_id=str(group_id),
            user_id=str(current_user.id),
            daily_cap=exc.daily_cap,
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"This house has reached its quiet-pulse limit for today "
                f"({exc.daily_cap})."
            ),
        ) from exc
