import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.space import Space
from app.models.user import User
from app.schemas.chore import ChoreRead
from app.schemas.reservation import ReservationCreate, ReservationRead, ReservationWithChore
from app.schemas.space import SpaceRead
from app.services import reservation_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}", tags=["spaces"])


@router.get("/spaces", response_model=list[SpaceRead])
async def list_spaces(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[Space]:
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    result = await db.execute(select(Space).where(Space.group_id == group_id))
    return list(result.scalars().all())


@router.get("/reservations", response_model=list[ReservationRead])
async def list_reservations(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[ReservationRead]:
    """Upcoming (and currently in-progress) reservations across every
    space in the group.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    reservations = await reservation_service.list_group_reservations(db, group_id)
    return reservations


@router.post(
    "/spaces/{space_id}/reservations",
    response_model=ReservationWithChore,
    status_code=status.HTTP_201_CREATED,
)
async def create_reservation(
    group_id: uuid.UUID,
    space_id: uuid.UUID,
    payload: ReservationCreate,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> ReservationWithChore:
    """Book a space. Reservations aren't anonymous — the booker stays
    visible to the group (unlike nudges).
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)

    space = await db.get(Space, space_id)
    if space is None or space.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Space not found.")

    try:
        reservation, chore = await reservation_service.create_reservation(
            db,
            redis,
            group_id=group_id,
            space=space,
            user_id=current_user.id,
            start_time=payload.start_time,
            duration_minutes=int(payload.duration_minutes),
        )
    except reservation_service.ReservationConflictError as exc:
        logger.warning(
            "reservation.rejected_conflict", group_id=str(group_id), space_id=str(space_id)
        )
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except reservation_service.ReservationInPastError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except reservation_service.ReservationTooFarAheadError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return ReservationWithChore(
        reservation=ReservationRead.model_validate(reservation),
        chore=ChoreRead.model_validate(chore),
    )
