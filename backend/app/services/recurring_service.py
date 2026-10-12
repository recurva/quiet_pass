"""Recurring weekly bookings.

Two design decisions were explicitly left to this module's judgment;
both are documented here rather than just implemented silently.

**Partial conflict handling**: when a candidate occurrence's time slot is
already taken, the whole series is NOT rejected — the series is created,
every free occurrence is booked, and the taken ones are reported back as
`skipped` with a reason. The alternative (all-or-nothing) would mean one
contested Tuesday blocks an otherwise-free Thursday for the rest of the
horizon, which is a worse outcome for a shared house than "book what you
can, tell me what you couldn't." Each occurrence attempt runs in its own
SQL savepoint (`db.begin_nested()`), so one occurrence's conflict never
rolls back occurrences already booked earlier in the same request.

**Materialization strategy**: occurrences are materialized up front, as
real `Reservation` rows, for a fixed horizon
(`settings.recurring_series_horizon_weeks`, default 8 weeks) — not
generated lazily on a rolling window by a background job. This backend
has no scheduler/worker infrastructure (Cloud Run is request/response
only; the only "jobs" that exist are one-off Alembic migration runs a
human triggers manually), so a true rolling horizon would mean building
and operating a cron trigger just for this feature. Materializing
up-front is simpler, fully covered by the same EXCLUDE constraint and
buffer as any other reservation with zero new runtime machinery, and
bounded (no unbounded row growth). The real tradeoff: a series "runs
out" after the horizon and doesn't silently extend itself — a member
who wants it to continue has to create a new series once it's close to
the end. Worth revisiting with a real background-job runner if recurring
bookings need to extend indefinitely.
"""

import uuid
from datetime import date, datetime, time, timedelta, timezone

from redis.asyncio import Redis
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import get_logger
from app.models.chore import Chore
from app.models.recurring_series import RecurringSeries
from app.models.reservation import Reservation
from app.models.space import Space
from app.schemas.chore import ChoreRead
from app.schemas.recurring_series import (
    RecurringSeriesCreate,
    RecurringSeriesRead,
    SkippedOccurrence,
)
from app.schemas.reservation import ReservationRead, ReservationWithChore
from app.services.reservation_service import chore_template_for
from app.services.status_service import publish_group_event

logger = get_logger(__name__)


class RecurringError(Exception):
    """Base for recurring-series failures; routers translate these to HTTP errors."""


class RecurringWeeklyCapError(RecurringError):
    def __init__(self, cap: int) -> None:
        self.cap = cap
        super().__init__(
            f"That would exceed the limit of {cap} recurring slots per person per week."
        )


class RecurringSeriesNotFoundError(RecurringError):
    def __init__(self) -> None:
        super().__init__("Recurring series not found.")


def _candidate_occurrences(
    weekdays: list[int], start_hour_utc: int, start_minute_utc: int, duration_minutes: int
) -> list[tuple[datetime, datetime]]:
    """Every (start, end) UTC datetime pair, for each matching weekday,
    from today through the horizon — excluding anything already in the
    past (today's weekday with a start time that's already passed). Pure
    function of the inputs and "now", so it's directly unit-testable
    without touching the database.
    """
    now = datetime.now(timezone.utc)
    today = now.date()
    horizon_end = today + timedelta(weeks=settings.recurring_series_horizon_weeks)

    occurrences: list[tuple[datetime, datetime]] = []
    current = today
    while current < horizon_end:
        if current.weekday() in weekdays:
            start = datetime.combine(
                current, time(hour=start_hour_utc, minute=start_minute_utc), tzinfo=timezone.utc
            )
            if start >= now:
                end = start + timedelta(minutes=duration_minutes)
                occurrences.append((start, end))
        current += timedelta(days=1)
    return occurrences


async def _active_weekday_count(db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID) -> int:
    """Sum of weekday-slots across every one of this user's existing
    series in this group — "active" just means the series row still
    exists; there's no separate enabled/disabled flag; cancelling a
    series deletes its row (see cancel_series).
    """
    result = await db.execute(
        select(func.array_length(RecurringSeries.weekdays, 1)).where(
            RecurringSeries.group_id == group_id, RecurringSeries.user_id == user_id
        )
    )
    return sum(length for (length,) in result.all() if length)


async def create_recurring_series(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    space: Space,
    user_id: uuid.UUID,
    payload: RecurringSeriesCreate,
) -> tuple[RecurringSeriesRead, list[ReservationWithChore], list[SkippedOccurrence]]:
    # Unlike the EXCLUDE constraint that protects every occurrence insert
    # below, the weekly cap is an app-level read-then-check
    # (_active_weekday_count) with nothing in the schema enforcing it —
    # two genuinely concurrent series-creation calls from the same user
    # could each read the cap as not-yet-reached and both proceed,
    # landing combined over the limit (confirmed empirically in
    # test_concurrent_series_creation_can_race_past_the_weekly_cap before
    # this lock was added — both requests returned 201). A Postgres
    # advisory transaction lock, scoped to this (group, user) pair, makes
    # a second concurrent call block here until the first's transaction
    # commits or rolls back, so the second's cap read always sees the
    # first's already-created series. Automatically released at the end
    # of this transaction — no separate unlock call needed.
    await db.execute(
        text("SELECT pg_advisory_xact_lock(hashtext(:key))"),
        {"key": f"recurring_series_cap:{group_id}:{user_id}"},
    )

    existing_count = await _active_weekday_count(db, group_id, user_id)
    if existing_count + len(payload.weekdays) > settings.recurring_series_max_slots_per_week:
        raise RecurringWeeklyCapError(settings.recurring_series_max_slots_per_week)

    series = RecurringSeries(
        id=uuid.uuid4(),
        group_id=group_id,
        space_id=space.id,
        user_id=user_id,
        weekdays=payload.weekdays,
        start_hour_utc=payload.start_hour_utc,
        start_minute_utc=payload.start_minute_utc,
        duration_minutes=int(payload.duration_minutes),
    )
    db.add(series)
    await db.flush()

    buffer = timedelta(minutes=settings.reservation_buffer_minutes)
    chore_template = chore_template_for(space.name)

    created: list[ReservationWithChore] = []
    skipped: list[SkippedOccurrence] = []

    for start, end in _candidate_occurrences(
        payload.weekdays, payload.start_hour_utc, payload.start_minute_utc, int(payload.duration_minutes)
    ):
        # Each occurrence gets its own savepoint: a conflict here must only
        # discard *this* occurrence's half-written insert, never the
        # occurrences (and the series row itself) already flushed earlier
        # in this same outer transaction. See module docstring.
        savepoint = await db.begin_nested()
        try:
            reservation = Reservation(
                id=uuid.uuid4(),
                group_id=group_id,
                space_id=space.id,
                user_id=user_id,
                recurring_series_id=series.id,
                start_time=start,
                end_time=end,
            )
            reservation.during = func.tstzrange(start, end + buffer, "[)")
            db.add(reservation)
            await db.flush()

            chore = Chore(
                id=uuid.uuid4(),
                reservation_id=reservation.id,
                user_id=user_id,
                template=chore_template,
                due_at=end,
            )
            db.add(chore)
            await db.flush()
        except IntegrityError:
            await savepoint.rollback()
            skipped.append(SkippedOccurrence(start_time=start, end_time=end, reason="conflict"))
            continue
        else:
            await savepoint.commit()
            created.append(
                ReservationWithChore(
                    reservation=ReservationRead.model_validate(reservation),
                    chore=ChoreRead.model_validate(chore),
                )
            )

    await db.commit()
    await db.refresh(series)

    for item in created:
        payload_out = {
            "event": "reservation",
            "space_name": space.name,
            **item.reservation.model_dump(mode="json"),
        }
        await publish_group_event(redis, group_id, payload_out)

    logger.info(
        "recurring_series.created",
        group_id=str(group_id),
        space_id=str(space.id),
        user_id=str(user_id),
        series_id=str(series.id),
        created_count=len(created),
        skipped_count=len(skipped),
    )

    return RecurringSeriesRead.model_validate(series), created, skipped


async def list_my_recurring_series(
    db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID
) -> list[RecurringSeriesRead]:
    result = await db.execute(
        select(RecurringSeries)
        .where(RecurringSeries.group_id == group_id, RecurringSeries.user_id == user_id)
        .order_by(RecurringSeries.created_at)
    )
    return [RecurringSeriesRead.model_validate(row) for row in result.scalars().all()]


async def cancel_series(
    db: AsyncSession, redis: Redis, group_id: uuid.UUID, series_id: uuid.UUID
) -> list[uuid.UUID]:
    """Deletes every *future* occurrence of this series (their chores
    cascade-delete via Chore.reservation_id's own ON DELETE CASCADE), then
    the series row itself — past occurrences are deliberately left alone
    for history; their recurring_series_id just goes NULL via the FK's ON
    DELETE SET NULL. Returns the ids of the occurrences that were removed,
    for the WS fan-out and the caller's response.
    """
    series = await db.get(RecurringSeries, series_id)
    if series is None or series.group_id != group_id:
        raise RecurringSeriesNotFoundError()

    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(Reservation.id).where(
            Reservation.recurring_series_id == series_id, Reservation.start_time >= now
        )
    )
    future_ids = [row[0] for row in result.all()]

    for reservation_id in future_ids:
        reservation = await db.get(Reservation, reservation_id)
        if reservation is not None:
            await db.delete(reservation)

    await db.delete(series)
    await db.commit()

    for reservation_id in future_ids:
        await publish_group_event(
            redis,
            group_id,
            {
                "event": "reservation_cancelled",
                "group_id": str(group_id),
                "reservation_id": str(reservation_id),
            },
        )

    logger.info(
        "recurring_series.cancelled",
        group_id=str(group_id),
        series_id=str(series_id),
        cancelled_count=len(future_ids),
    )
    return future_ids
