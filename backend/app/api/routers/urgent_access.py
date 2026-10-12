import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.space import Space
from app.models.user import User
from app.schemas.urgent_access import UrgentAccessRequestRead
from app.services import urgent_access_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}", tags=["urgent-access"])


@router.post(
    "/spaces/{space_id}/reservations/{reservation_id}/urgent-access-request",
    response_model=UrgentAccessRequestRead,
)
async def send_urgent_access_request(
    group_id: uuid.UUID,
    space_id: uuid.UUID,
    reservation_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> UrgentAccessRequestRead:
    """A polite notification to the current holder — never cancels or
    modifies their booking. See urgent_access_service's module docstring
    for the identity and rate-limit decisions.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)

    space = await db.get(Space, space_id)
    if space is None or space.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Space not found.")

    try:
        return await urgent_access_service.request_urgent_access(
            db,
            redis,
            group_id=group_id,
            space_id=space_id,
            reservation_id=reservation_id,
            requester_id=current_user.id,
            space_name=space.name,
        )
    except urgent_access_service.ReservationNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except urgent_access_service.ReservationNotActiveError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except urgent_access_service.CannotRequestOwnBookingError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except urgent_access_service.UrgentAccessCooldownError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
            headers={"Retry-After": str(exc.retry_after_seconds)},
        ) from exc
