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

import uuid
from datetime import datetime, timedelta, timezone

from redis.asyncio import Redis
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import get_logger
from app.models.chore import Chore
from app.models.device_token import DeviceToken
from app.models.recurring_series import RecurringSeries
from app.models.reservation import Reservation
from app.models.space import Space
from app.schemas.reservation import ReservationRead
from app.services import push_service
from app.services.status_service import publish_group_event

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


class ReservationNotFoundError(ReservationError):
    def __init__(self) -> None:
        super().__init__("Reservation not found.")


class ReservationNotOwnedError(ReservationError):
    def __init__(self) -> None:
        super().__init__("Only the person who booked this, or an admin, can cancel it.")


def chore_template_for(space_name: str) -> str:
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
        template=chore_template_for(space_name),
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
    await publish_group_event(redis, group_id, payload)

    logger.info(
        "reservation.created",
        group_id=str(group_id),
        space_id=str(space.id),
        user_id=str(user_id),
        reservation_id=str(reservation.id),
    )

    return reservation, chore


async def cancel_reservation(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    reservation_id: uuid.UUID,
    acting_user_id: uuid.UUID,
    acting_user_is_admin: bool,
) -> None:
    """Cancels one occurrence — works identically for an ad-hoc booking and
    a single occurrence of a recurring series (the series row itself, and
    every *other* occurrence, are untouched). The reservation's chore
    cascade-deletes via Chore.reservation_id's own ON DELETE CASCADE.
    """
    reservation = await db.get(Reservation, reservation_id)
    if reservation is None or reservation.group_id != group_id:
        raise ReservationNotFoundError()
    if reservation.user_id != acting_user_id and not acting_user_is_admin:
        raise ReservationNotOwnedError()

    space_id = reservation.space_id
    holder_id = reservation.user_id
    cancelled_by_someone_else = holder_id != acting_user_id
    space = await db.get(Space, space_id) if cancelled_by_someone_else else None

    await db.delete(reservation)
    await db.commit()

    await publish_group_event(
        redis,
        group_id,
        {
            "event": "reservation_cancelled",
            "group_id": str(group_id),
            "reservation_id": str(reservation_id),
        },
    )

    # Admin-cancelled-someone-else's-booking case only — a self-cancel
    # needs no notification (the booker is the one who just acted). Same
    # best-effort push pattern as member-removal (memberships.py's
    # remove_membership): never raises, the cancellation has already
    # committed by this point regardless.
    if cancelled_by_someone_else and space is not None:
        tokens_result = await db.execute(
            select(DeviceToken.token).where(DeviceToken.user_id == holder_id)
        )
        tokens = [row[0] for row in tokens_result.all()]
        if tokens:
            await push_service.send_to_tokens(
                tokens,
                title="QuietPass",
                body=f"Your booking for {space.name} was cancelled by an admin.",
                data={"event": "reservation_cancelled", "group_id": str(group_id)},
            )

    logger.info(
        "reservation.cancelled",
        group_id=str(group_id),
        space_id=str(space_id),
        cancelled_by_someone_else=cancelled_by_someone_else,
        reservation_id=str(reservation_id),
        acting_user_id=str(acting_user_id),
    )


async def cancel_future_reservations_for_departing_member(
    db: AsyncSession, redis: Redis, group_id: uuid.UUID, user_id: uuid.UUID
) -> list[uuid.UUID]:
    """Called when a member leaves (or is removed from) a group — NOT on
    account deletion, which already cascades every reservation
    automatically via Reservation.user_id's own ON DELETE CASCADE (see
    users.py's delete_current_user docstring). Leaving a single group
    doesn't delete the User row, so that cascade never fires; without
    this, a departed member's future bookings — including, critically,
    every future occurrence of a recurring series — would sit there
    holding the space indefinitely with no one left who can cancel them
    (the booker is no longer a member; see RecurringSeries's own
    cancel-series permission check).

    Deletes every future reservation this user holds in this one group
    (their chores cascade-delete via Chore.reservation_id's own ON
    DELETE CASCADE) and, for any recurring series of theirs that's left
    with no remaining future occurrences, the now-pointless series row
    too — same cleanup cancel_series itself does. Returns the cancelled
    reservation ids for the caller's own logging/event purposes.
    """
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(Reservation).where(
            Reservation.group_id == group_id,
            Reservation.user_id == user_id,
            Reservation.start_time >= now,
        )
    )
    future_reservations = list(result.scalars().all())
    touched_series_ids = {
        r.recurring_series_id for r in future_reservations if r.recurring_series_id is not None
    }

    cancelled_ids = [r.id for r in future_reservations]
    for reservation in future_reservations:
        await db.delete(reservation)
    await db.flush()

    # A series with zero remaining occurrences (every future one just got
    # deleted above) has nothing left to represent — clean it up the same
    # way cancel_series does, rather than leaving an orphaned recurrence
    # rule that can never produce another booking (its owner isn't a
    # member of this group anymore).
    for series_id in touched_series_ids:
        remaining = await db.execute(
            select(Reservation.id).where(Reservation.recurring_series_id == series_id).limit(1)
        )
        if remaining.first() is None:
            series = await db.get(RecurringSeries, series_id)
            if series is not None:
                await db.delete(series)

    await db.commit()

    for reservation_id in cancelled_ids:
        await publish_group_event(
            redis,
            group_id,
            {
                "event": "reservation_cancelled",
                "group_id": str(group_id),
                "reservation_id": str(reservation_id),
            },
        )

    if cancelled_ids:
        logger.info(
            "reservation.cancelled_on_departure",
            group_id=str(group_id),
            user_id=str(user_id),
            cancelled_count=len(cancelled_ids),
            series_removed_count=len(touched_series_ids),
        )

    return cancelled_ids


async def list_group_reservations(
    db: AsyncSession, group_id: uuid.UUID, include_past: bool = False
) -> list[Reservation]:
    query = select(Reservation).where(Reservation.group_id == group_id)
    if not include_past:
        query = query.where(Reservation.end_time >= datetime.now(timezone.utc))
    query = query.order_by(Reservation.start_time).limit(1000)
    result = await db.execute(query)
    return list(result.scalars().all())
