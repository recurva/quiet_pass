"""Booking a space and its atomic conflict check.

The only thing that actually has to be race-safe here is "does this
overlap an existing booking on the same space (including the buffer)?" —
that's handled entirely by the `ex_reservations_no_overlap` EXCLUDE
constraint on the reservations table (see app/models/reservation.py), not
by anything in this file. This module just builds the buffered range,
attempts the insert, and translates a constraint violation into a clean
error. Everything else here (past-time check, max-advance check) is a
plain, non-racy validation of the request itself.
"""

import json
import uuid
from datetime import datetime, timedelta, timezone

from redis.asyncio import Redis
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import get_logger
from app.models.chore import Chore
from app.models.reservation import Reservation
from app.models.space import Space
from app.schemas.reservation import ReservationRead
from app.services.status_service import group_channel

logger = get_logger(__name__)

DEFAULT_SPACE_NAMES = ["Living Room", "Kitchen", "Main Desk"]

# Per-space chore wording. Matched case-insensitively against the space
# name; anything not listed gets the generic fallback. Adding a new default
# space's template is just a new entry here.
_CHORE_TEMPLATES: dict[str, str] = {
    "living room": "Tidy the living room and fluff the cushions.",
    "kitchen": "Wipe down the counters and load any dishes.",
    "main desk": "Clear your things off the desk.",
}
_DEFAULT_CHORE_TEMPLATE = "Tidy up after your booking."


class ReservationError(Exception):
    """Base for booking failures; routers translate these to HTTP errors."""


class ReservationConflictError(ReservationError):
    def __init__(self) -> None:
        super().__init__("That time overlaps an existing booking (or its buffer) on this space.")


class ReservationInPastError(ReservationError):
    def __init__(self) -> None:
        super().__init__("Start time must be in the future.")


class ReservationTooFarAheadError(ReservationError):
    def __init__(self, max_days: int) -> None:
        self.max_days = max_days
        super().__init__(f"Bookings can only be made up to {max_days} days ahead.")


def _chore_template_for(space_name: str) -> str:
    return _CHORE_TEMPLATES.get(space_name.strip().lower(), _DEFAULT_CHORE_TEMPLATE)


async def seed_default_spaces(db: AsyncSession, group_id: uuid.UUID) -> list[Space]:
    """Called once, right after a group is created."""
    spaces = [Space(group_id=group_id, name=name) for name in DEFAULT_SPACE_NAMES]
    db.add_all(spaces)
    await db.flush()
    return spaces


async def create_reservation(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    space: Space,
    user_id: uuid.UUID,
    start_time: datetime,
    duration_minutes: int,
) -> tuple[Reservation, Chore]:
    now = datetime.now(timezone.utc)
    if start_time < now:
        raise ReservationInPastError()

    max_start = now + timedelta(days=settings.reservation_max_advance_days)
    if start_time > max_start:
        raise ReservationTooFarAheadError(settings.reservation_max_advance_days)

    end_time = start_time + timedelta(minutes=duration_minutes)
    buffer = timedelta(minutes=settings.reservation_buffer_minutes)

    # Captured as plain values up front, not re-read off `space` later:
    # `db.rollback()` on a conflict expires every object loaded in this
    # session (regardless of expire_on_commit, which only governs commit),
    # so an attribute access on `space` *after* a rollback triggers an
    # implicit lazy-reload — one that can't complete synchronously in
    # async SQLAlchemy, raising "greenlet_spawn has not been called".
    space_id = space.id
    space_name = space.name

    reservation = Reservation(
        group_id=group_id,
        space_id=space_id,
        user_id=user_id,
        start_time=start_time,
        end_time=end_time,
    )
    # `during` pads the trailing edge only: [start, end + buffer). Padding
    # both edges would require a full `buffer` gap on *each* side of every
    # booking — i.e. `2 * buffer` between two adjacent ones — which
    # overshoots the spec. Padding just the end is enough: for any two
    # reservations on the same space, whichever comes first has its
    # padded end extended by `buffer`, so the second can't start until
    # that padded end has passed — a `buffer`-minute gap either way,
    # correct regardless of booking order. The EXCLUDE constraint checks
    # overlap against this padded range, not [start_time, end_time)
    # directly — that's what makes the buffer rule atomic instead of a
    # separate, racy pre-check. func.tstzrange(...) is a SQL expression,
    # evaluated by Postgres itself at INSERT time.
    reservation.during = func.tstzrange(start_time, end_time + buffer, "[)")

    db.add(reservation)
    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        logger.warning(
            "reservation.conflict",
            group_id=str(group_id),
            space_id=str(space_id),
            user_id=str(user_id),
        )
        raise ReservationConflictError() from exc

    chore = Chore(
        reservation_id=reservation.id,
        user_id=user_id,
        template=_chore_template_for(space_name),
        due_at=end_time,
    )
    db.add(chore)
    await db.commit()
    await db.refresh(reservation)
    await db.refresh(chore)

    reservation_read = ReservationRead.model_validate(reservation)
    payload = {
        "event": "reservation",
        "space_name": space.name,
        **reservation_read.model_dump(mode="json"),
    }
    await redis.publish(group_channel(group_id), json.dumps(payload))

    logger.info(
        "reservation.created",
        group_id=str(group_id),
        space_id=str(space.id),
        user_id=str(user_id),
        reservation_id=str(reservation.id),
    )

    return reservation, chore


async def list_group_reservations(
    db: AsyncSession, group_id: uuid.UUID, include_past: bool = False
) -> list[Reservation]:
    query = select(Reservation).where(Reservation.group_id == group_id)
    if not include_past:
        query = query.where(Reservation.end_time >= datetime.now(timezone.utc))
    query = query.order_by(Reservation.start_time)
    result = await db.execute(query)
    return list(result.scalars().all())
