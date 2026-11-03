"""Custom spaces: admin-only create/remove.

A custom space is just another row in the `spaces` table — exactly what
the three seeded defaults already are (see
`reservation_service.seed_default_spaces`); there's no separate storage
model to generalize. Removing a space must not orphan whatever's booked
on it, so `remove_space` reuses the exact same cancellation functions a
booker or admin would otherwise hit directly
(`reservation_service.cancel_reservation` for an ad-hoc booking,
`recurring_service.cancel_series` for a whole weekly series) rather than
duplicating that logic here — each already does its own WS fan-out,
chore cascade, and (for an admin cancelling someone else's booking) push
notification, so this module doesn't need to re-implement any of that.
"""

import uuid
from datetime import datetime, timezone

from fastapi import HTTPException, status
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.models.reservation import Reservation
from app.models.space import Space
from app.schemas.space import SpaceCreate, SpaceRead
from app.services import recurring_service, reservation_service
from app.services.status_service import publish_group_event

logger = get_logger(__name__)


async def create_space(
    db: AsyncSession, redis: Redis, group_id: uuid.UUID, payload: SpaceCreate
) -> SpaceRead:
    space = Space(group_id=group_id, name=payload.name.strip())
    db.add(space)
    await db.commit()
    await db.refresh(space)

    logger.info("space.created", group_id=str(group_id), space_id=str(space.id))
    await publish_group_event(redis, group_id, {"event": "space_update", "group_id": str(group_id)})
    return SpaceRead.model_validate(space, from_attributes=True)


async def remove_space(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    space_id: uuid.UUID,
    acting_user_id: uuid.UUID,
) -> None:
    """Cancels every reservation on this space that hasn't ended yet
    (active-right-now bookings included, not just ones that haven't
    started) before deleting the space itself. Each one goes through the
    same path a real cancellation would: whole recurring series via
    `cancel_series` (once per distinct series — that already removes
    every future occurrence plus the series row), everything else via
    `cancel_reservation` with `acting_user_is_admin=True` so an admin can
    clear a booking they don't own, same as cancelling someone else's
    booking from the Spaces screen directly. Purely historical
    (already-ended) reservations are left for the space row's own
    ON DELETE CASCADE — nothing live is watching a dead row's history.
    """
    space = await db.get(Space, space_id)
    if space is None or space.group_id != group_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Space not found.")

    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(Reservation).where(Reservation.space_id == space_id, Reservation.end_time >= now)
    )
    live_reservations = list(result.scalars().all())
    series_ids = {
        r.recurring_series_id for r in live_reservations if r.recurring_series_id is not None
    }
    ad_hoc_ids = [r.id for r in live_reservations if r.recurring_series_id is None]

    for series_id in series_ids:
        await recurring_service.cancel_series(db, redis, group_id=group_id, series_id=series_id)

    for reservation_id in ad_hoc_ids:
        await reservation_service.cancel_reservation(
            db,
            redis,
            group_id=group_id,
            reservation_id=reservation_id,
            acting_user_id=acting_user_id,
            acting_user_is_admin=True,
        )

    # Re-fetched rather than reusing `space`: each cancel_* call above
    # commits its own transaction, which (expire_on_commit, the default)
    # expires every object this session is tracking — an attribute touch
    # on the stale `space` reference (including what `db.delete` needs)
    # would trigger an implicit lazy-reload that can't complete
    # synchronously here. Same lesson as create_reservation's own
    # "captured as plain values, not re-read off `space`" comment.
    space = await db.get(Space, space_id)
    if space is not None:
        await db.delete(space)
        await db.commit()

    logger.info(
        "space.removed",
        group_id=str(group_id),
        space_id=str(space_id),
        cancelled_series_count=len(series_ids),
        cancelled_ad_hoc_count=len(ad_hoc_ids),
    )
    await publish_group_event(redis, group_id, {"event": "space_update", "group_id": str(group_id)})
