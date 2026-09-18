import json
import uuid
from datetime import datetime, timedelta, timezone

from redis.asyncio import Redis
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import get_logger
from app.models.device_token import DeviceToken
from app.models.membership import Membership
from app.schemas.nudge import NudgeRead, NudgeType
from app.services import push_service
from app.services.status_service import group_channel

logger = get_logger(__name__)

_KEY_PREFIX = "nudge"

# One message per type. To add a preset: add a NudgeType member (schemas/nudge.py)
# and a line here — nothing else in the send path changes.
_PRESET_MESSAGES: dict[NudgeType, str] = {
    NudgeType.PACKAGE_ARRIVED: "A package has arrived.",
    NudgeType.FRONT_DOOR_UNLOCKED: "The front door is unlocked.",
    NudgeType.SINK_FULL: "The sink is full.",
}


class NudgeError(Exception):
    """Base for nudge-sending failures; routers translate these to HTTP errors."""


class QuietPulseCooldownError(NudgeError):
    def __init__(self, retry_after_seconds: int):
        self.retry_after_seconds = retry_after_seconds
        super().__init__(f"Quiet pulse cooldown active for {retry_after_seconds}s.")


class QuietPulseDailyCapError(NudgeError):
    def __init__(self, daily_cap: int):
        self.daily_cap = daily_cap
        super().__init__(f"Quiet pulse daily cap of {daily_cap} reached.")


def render_message(nudge_type: NudgeType, duration_minutes: int | None) -> str:
    """The server-generated neutral wording. Callers never supply free text."""
    if nudge_type == NudgeType.QUIET_PULSE:
        return f"A housemate asked for {duration_minutes} minutes of quiet."
    return _PRESET_MESSAGES[nudge_type]


def _cooldown_key(group_id: uuid.UUID, sender_id: uuid.UUID) -> str:
    return f"{_KEY_PREFIX}:cooldown:{group_id}:{sender_id}"


def _daily_cap_key(group_id: uuid.UUID, day: str) -> str:
    return f"{_KEY_PREFIX}:quiet_pulse_count:{group_id}:{day}"


def _seconds_until_utc_midnight() -> int:
    now = datetime.now(timezone.utc)
    tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    return int((tomorrow - now).total_seconds())


async def _enforce_quiet_pulse_limits(
    redis: Redis, group_id: uuid.UUID, sender_id: uuid.UUID
) -> None:
    """Per-sender cooldown, then per-group daily cap. Order matters: a
    cooldown-blocked attempt never touches the cap counter, and a
    cap-blocked attempt doesn't start a cooldown the sender didn't earn.
    """
    cooldown_key = _cooldown_key(group_id, sender_id)
    cooldown_ttl = await redis.ttl(cooldown_key)
    if cooldown_ttl and cooldown_ttl > 0:
        raise QuietPulseCooldownError(retry_after_seconds=cooldown_ttl)

    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    cap_key = _daily_cap_key(group_id, day)
    count = await redis.incr(cap_key)
    if count == 1:
        await redis.expire(cap_key, _seconds_until_utc_midnight())
    if count > settings.quiet_pulse_daily_cap:
        await redis.decr(cap_key)  # don't let a rejected attempt eat the cap
        raise QuietPulseDailyCapError(daily_cap=settings.quiet_pulse_daily_cap)

    await redis.set(cooldown_key, "1", ex=settings.quiet_pulse_cooldown_seconds)


async def _push_tokens_for_group(
    db: AsyncSession, group_id: uuid.UUID, exclude_user_id: uuid.UUID
) -> list[str]:
    """Every device token belonging to a group member other than the
    sender. The sender already knows they sent it — pushing to their own
    devices too would just be noise, and (like every other nudge payload)
    there's nothing sender-identifying here to push to begin with.
    """
    result = await db.execute(
        select(DeviceToken.token)
        .join(Membership, Membership.user_id == DeviceToken.user_id)
        .where(Membership.group_id == group_id, Membership.user_id != exclude_user_id)
    )
    return [row[0] for row in result.all()]


async def _send_push(
    db: AsyncSession, group_id: uuid.UUID, sender_id: uuid.UUID, nudge: NudgeRead
) -> None:
    """Best-effort FCM push to every other member's devices, so a nudge
    reaches a backgrounded or locked phone, not just an open WebSocket
    connection. Never raises: a push outage (or, right now, no FCM
    credentials at all — see push_service) must not stop the nudge from
    reaching anyone over the WebSocket.
    """
    tokens = await _push_tokens_for_group(db, group_id, sender_id)
    if not tokens:
        return

    result = await push_service.send_to_tokens(
        tokens,
        title="QuietPass",
        body=nudge.message,
        data={"event": "nudge", "group_id": str(group_id), "type": nudge.type.value},
    )

    if result.invalid_tokens:
        await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(result.invalid_tokens)))
        await db.commit()
        logger.info(
            "push.stale_tokens_removed",
            group_id=str(group_id),
            count=len(result.invalid_tokens),
        )


async def send_nudge(
    redis: Redis,
    db: AsyncSession,
    group_id: uuid.UUID,
    sender_id: uuid.UUID,
    nudge_type: NudgeType,
    duration_minutes: int | None,
) -> NudgeRead:
    """Render the neutral message, apply quiet-pulse limits, publish to the
    group's WebSocket channel for anyone with the app open (step five), and
    push to everyone else's devices (step seven) — same neutral message,
    same no-sender-identity guarantee, on both paths.

    Tradeoff, kept simple on purpose: a member with the app foregrounded
    gets the WebSocket delivery only (push notifications are addressed to
    every *other* member regardless of their app's foreground/background
    state — FCM itself doesn't know that). Flutter is what avoids a double
    notification: it receives the foreground push silently and relies on
    the WebSocket-driven in-app banner instead of also rendering a system
    notification for it. A more precise version would track live
    presence per connection and exclude currently-connected members from
    the push entirely; not worth the complexity yet.
    """
    if nudge_type == NudgeType.QUIET_PULSE:
        await _enforce_quiet_pulse_limits(redis, group_id, sender_id)

    nudge = NudgeRead(
        id=uuid.uuid4(),
        group_id=group_id,
        type=nudge_type,
        message=render_message(nudge_type, duration_minutes),
        duration_minutes=duration_minutes,
        created_at=datetime.now(timezone.utc),
    )

    payload = {"event": "nudge", **nudge.model_dump(mode="json")}
    await redis.publish(group_channel(group_id), json.dumps(payload))

    # sender_id is logged (internal, for the cap/cooldown) but never appears
    # in `nudge` / `payload` above, which is what other members receive.
    logger.info(
        "nudge.sent",
        group_id=str(group_id),
        sender_id=str(sender_id),
        type=nudge_type.value,
    )

    await _send_push(db, group_id, sender_id, nudge)

    return nudge
