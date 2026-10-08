"""Dinner headcount: a daily per-house tally of who's home for dinner.

"Daily" and "5:00 PM" are both house-local, inherently calendar-day
concepts — computing them in UTC would mean the day (and the cutoff)
roll over at 5:30am IST, not midnight, which isn't what anyone asking
"who's home for dinner tonight" means. The app is India-only today (the
same assumption phone_entry_page.dart's +91 default already makes), so
this uses a fixed IST offset (UTC+5:30, no DST to worry about) rather
than per-house timezone storage that doesn't exist anywhere else in the
data model yet — a real scope decision, not an oversight, and worth
revisiting the moment this app serves a non-Indian house.

The cutoff is soft by design (the client's own ask): cutoff_passed is
informational only, returned alongside the tally so the UI can say
"final" — nothing here ever rejects a write for being late.
"""

import uuid
from datetime import date, datetime, timedelta, timezone

from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.models.dinner_headcount import DinnerHeadcount, DinnerStatus
from app.schemas.dinner import DinnerResponseRead, DinnerTallyRead
from app.services.status_service import publish_group_event

logger = get_logger(__name__)

IST = timezone(timedelta(hours=5, minutes=30))
CUTOFF_HOUR_IST = 17  # 5:00 PM


def today_in_house_local() -> date:
    return datetime.now(IST).date()


def cutoff_at_utc(day: date) -> datetime:
    """The given house-local calendar day's 5:00 PM, as an absolute UTC
    instant — a pure function of `day` alone, which is what makes this
    directly unit-testable without mocking the wall clock (see
    tests/test_dinner.py).
    """
    local_cutoff = datetime(day.year, day.month, day.day, CUTOFF_HOUR_IST, 0, tzinfo=IST)
    return local_cutoff.astimezone(timezone.utc)


def is_cutoff_passed(day: date, now_utc: datetime | None = None) -> bool:
    now_utc = now_utc or datetime.now(timezone.utc)
    return now_utc >= cutoff_at_utc(day)


async def set_dinner_status(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    user_id: uuid.UUID,
    status: DinnerStatus,
) -> DinnerResponseRead:
    """Upserts today's response for one member. Atomic under concurrency
    (two devices for the same account, or a retried request) via
    Postgres's own ON CONFLICT — not a SELECT-then-INSERT-or-UPDATE,
    which would have exactly the same lost-update race every other
    upsert-shaped endpoint in this codebase already avoids.
    """
    day = today_in_house_local()
    stmt = (
        pg_insert(DinnerHeadcount)
        .values(id=uuid.uuid4(), group_id=group_id, user_id=user_id, day=day, status=status)
        .on_conflict_do_update(
            constraint="uq_dinner_headcount_group_user_day",
            set_={"status": status, "updated_at": datetime.now(timezone.utc)},
        )
        .returning(DinnerHeadcount)
    )
    result = await db.execute(stmt)
    row = result.scalar_one()
    await db.commit()
    await db.refresh(row)

    logger.info(
        "dinner.status_set",
        group_id=str(group_id),
        user_id=str(user_id),
        status=status.value,
        day=day.isoformat(),
    )

    payload = {
        "event": "dinner_update",
        "group_id": str(group_id),
        "user_id": str(user_id),
        "status": status.value,
        "day": day.isoformat(),
    }
    await publish_group_event(redis, group_id, payload)

    return DinnerResponseRead(user_id=row.user_id, status=row.status, updated_at=row.updated_at)


async def get_tally(db: AsyncSession, group_id: uuid.UUID) -> DinnerTallyRead:
    day = today_in_house_local()
    result = await db.execute(
        select(DinnerHeadcount).where(
            DinnerHeadcount.group_id == group_id, DinnerHeadcount.day == day
        )
    )
    rows = list(result.scalars().all())

    responses = [
        DinnerResponseRead(user_id=row.user_id, status=row.status, updated_at=row.updated_at)
        for row in rows
    ]
    home_count = sum(1 for row in rows if row.status == DinnerStatus.HOME)
    staying_out_count = sum(1 for row in rows if row.status == DinnerStatus.STAYING_OUT)

    return DinnerTallyRead(
        day=day,
        cutoff_at=cutoff_at_utc(day),
        cutoff_passed=is_cutoff_passed(day),
        home_count=home_count,
        staying_out_count=staying_out_count,
        responses=responses,
    )
