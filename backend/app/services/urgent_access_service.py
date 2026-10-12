"""Emergency override: "urgent 5-minute access request."

This is deliberately a polite notification, not a takeover — the
holder's booking is never cancelled or modified by a request; sending one
only pushes a notification to the holder and broadcasts it over the
group's WebSocket. Nothing here is persisted as its own row (same shape
as a nudge: ephemeral, broadcast-only, nothing to query back later).

**Identity**: the requester is NOT anonymous, unlike a nudge. A nudge is
a generic, undirected signal to the whole house ("the sink is full") —
there's no one specific person it's "from" in any way that matters to
the recipient. An urgent access request is the opposite: it's a direct
ask *about a specific booking*, and the holder has an obvious, legitimate
reason to know who's asking — "someone needs this" versus "Alex needs
this" change whether and how quickly the holder responds, and reservations
themselves already aren't anonymous (the booker is visible on every
reservation). Hiding the requester here would be inconsistent with that
and would strip useful context for no privacy benefit.

**Rate limiting**: one atomic Redis SET-NX cooldown per (holder,
requester) pair, same mechanism as the quiet-pulse cooldown
(nudge_service._enforce_quiet_pulse_limits) — claiming the cooldown key
*is* the check, so two concurrent requests from the same person can't
both slip through before either one's key is visible to the other. No
daily cap on top of it (unlike quiet pulse): the cooldown alone is
enough to stop one person from pestering one holder repeatedly, and a
per-group daily cap would also block *different* people with genuinely
separate urgent needs from reaching the same holder on a busy day, which
isn't the spam this is meant to prevent.
"""

import uuid
from datetime import datetime, timezone

from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import get_logger
from app.models.device_token import DeviceToken
from app.models.reservation import Reservation
from app.schemas.urgent_access import UrgentAccessRequestRead
from app.services import push_service
from app.services.status_service import publish_group_event

logger = get_logger(__name__)

_KEY_PREFIX = "urgent_access"


class UrgentAccessError(Exception):
    """Base for urgent-access-request failures; routers translate these to HTTP errors."""


class ReservationNotFoundError(UrgentAccessError):
    def __init__(self) -> None:
        super().__init__("Reservation not found.")


class ReservationNotActiveError(UrgentAccessError):
    def __init__(self) -> None:
        super().__init__("This space isn't currently booked.")


class CannotRequestOwnBookingError(UrgentAccessError):
    def __init__(self) -> None:
        super().__init__("You can't send an urgent access request for your own booking.")


class UrgentAccessCooldownError(UrgentAccessError):
    def __init__(self, retry_after_seconds: int) -> None:
        self.retry_after_seconds = retry_after_seconds
        super().__init__(f"Urgent access request cooldown active for {retry_after_seconds}s.")


def _cooldown_key(holder_id: uuid.UUID, requester_id: uuid.UUID) -> str:
    return f"{_KEY_PREFIX}:cooldown:{holder_id}:{requester_id}"


async def _claim_cooldown(redis: Redis, holder_id: uuid.UUID, requester_id: uuid.UUID) -> None:
    key = _cooldown_key(holder_id, requester_id)
    claimed = await redis.set(key, "1", ex=settings.urgent_access_cooldown_seconds, nx=True)
    if not claimed:
        ttl = await redis.ttl(key)
        raise UrgentAccessCooldownError(retry_after_seconds=max(ttl, 1))


async def _send_push_to_holder(db: AsyncSession, holder_id: uuid.UUID, space_name: str) -> None:
    result = await db.execute(select(DeviceToken.token).where(DeviceToken.user_id == holder_id))
    tokens = [row[0] for row in result.all()]
    if not tokens:
        return
    await push_service.send_to_tokens(
        tokens,
        title="Urgent access request",
        body=f"A housemate needs {space_name} for 5 minutes.",
        data={"event": "urgent_access_request", "space_name": space_name},
    )


async def request_urgent_access(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    space_id: uuid.UUID,
    reservation_id: uuid.UUID,
    requester_id: uuid.UUID,
    space_name: str,
) -> UrgentAccessRequestRead:
    reservation = await db.get(Reservation, reservation_id)
    if reservation is None or reservation.group_id != group_id or reservation.space_id != space_id:
        raise ReservationNotFoundError()

    now = datetime.now(timezone.utc)
    if not (reservation.start_time <= now < reservation.end_time):
        raise ReservationNotActiveError()

    holder_id = reservation.user_id
    if holder_id == requester_id:
        raise CannotRequestOwnBookingError()

    await _claim_cooldown(redis, holder_id, requester_id)

    request = UrgentAccessRequestRead(
        group_id=group_id,
        space_id=space_id,
        reservation_id=reservation_id,
        holder_id=holder_id,
        requester_id=requester_id,
        created_at=now,
    )

    payload = {"event": "urgent_access_request", **request.model_dump(mode="json")}
    await publish_group_event(redis, group_id, payload)

    logger.info(
        "urgent_access.requested",
        group_id=str(group_id),
        space_id=str(space_id),
        reservation_id=str(reservation_id),
        holder_id=str(holder_id),
        requester_id=str(requester_id),
    )

    await _send_push_to_holder(db, holder_id, space_name)

    return request
