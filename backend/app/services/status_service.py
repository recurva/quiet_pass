import json
import uuid
from datetime import datetime, timedelta, timezone

from redis.asyncio import Redis

from app.core.logging import get_logger
from app.schemas.status import STATUS_DURATION_RULES, HouseStatus, StatusRead

logger = get_logger(__name__)

_KEY_PREFIX = "status"


class StatusError(Exception):
    """Base for status-set failures; the router translates these to HTTP errors."""


class InvalidStatusDurationError(StatusError):
    def __init__(self, status: HouseStatus, allowed_minutes: tuple[int, ...]) -> None:
        self.status = status
        self.allowed_minutes = allowed_minutes
        options = ", ".join(f"{m}m" for m in allowed_minutes)
        super().__init__(f"{status.value} accepts these durations only: {options}.")


def _status_key(group_id: uuid.UUID, user_id: uuid.UUID) -> str:
    return f"{_KEY_PREFIX}:{group_id}:{user_id}"


def group_channel(group_id: uuid.UUID) -> str:
    """The Redis pub/sub channel a group's status changes are published on.
    Public so the WebSocket route can subscribe directly.
    """
    return f"{_KEY_PREFIX}:group:{group_id}"


def resolve_ttl_seconds(status: HouseStatus, duration_minutes: int | None) -> int | None:
    """Turns a client's requested status + optional duration into a TTL in
    seconds, enforcing the Time Limits spec. Returns None for Open to Chat
    (indefinite, no cap) or any status where the caller omitted a duration
    and the status has no default (shouldn't happen given the rules table,
    but falls through to indefinite rather than crashing).

    The allowed-minutes check happens here, not just in the Flutter picker
    — a client is never trusted to have actually sent one of the offered
    presets, and the result is additionally clamped to `cap_minutes` as a
    second line of defense even though every entry in `allowed_minutes` is
    already within its own cap by construction.
    """
    if status == HouseStatus.OPEN_TO_CHAT:
        return None

    rule = STATUS_DURATION_RULES[status]
    minutes = rule.default_minutes if duration_minutes is None else duration_minutes
    if minutes not in rule.allowed_minutes:
        raise InvalidStatusDurationError(status, rule.allowed_minutes)

    return min(minutes, rule.cap_minutes) * 60


async def set_status(
    redis: Redis,
    group_id: uuid.UUID,
    user_id: uuid.UUID,
    status: HouseStatus,
    ttl_seconds: int | None,
) -> StatusRead:
    """Write a member's live status to Redis and publish the change to the
    group's pub/sub channel. Postgres never sees this value.

    `ttl_seconds=None` (Open to Chat only) sets the key with no expiry at
    all, rather than skipping the write — an explicit, persistent
    "open_to_chat" entry is simpler to reason about than relying on key
    absence to mean the same thing, and `get_status`/`get_group_statuses`
    already treat a missing key as Open to Chat too (covers a member who
    never set anything, or whose previous status's TTL has since lapsed —
    Redis expires it silently, with nothing server-side needed to notice).
    """
    key = _status_key(group_id, user_id)
    if ttl_seconds is None:
        await redis.set(key, status.value)
        expires_at = None
    else:
        await redis.set(key, status.value, ex=ttl_seconds)
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)

    payload = {
        "event": "status_update",
        "group_id": str(group_id),
        "user_id": str(user_id),
        "status": status.value,
        "ttl_seconds": ttl_seconds,
        "expires_at": expires_at.isoformat() if expires_at else None,
    }
    await redis.publish(group_channel(group_id), json.dumps(payload))

    logger.info(
        "status.set",
        group_id=str(group_id),
        user_id=str(user_id),
        status=status.value,
        ttl_seconds=ttl_seconds,
    )
    return StatusRead(
        group_id=group_id,
        user_id=user_id,
        status=status,
        ttl_seconds=ttl_seconds,
        expires_at=expires_at,
    )


def _read_result(group_id: uuid.UUID, user_id: uuid.UUID, value: str | None, ttl: int | None) -> StatusRead:
    if value is None:
        # Never set, or its TTL has since lapsed — the spec's "open by
        # default" rule, not a separate null/"no status" state.
        return StatusRead(group_id=group_id, user_id=user_id, status=HouseStatus.OPEN_TO_CHAT)

    remaining = ttl if ttl and ttl > 0 else None
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=remaining) if remaining else None
    return StatusRead(
        group_id=group_id,
        user_id=user_id,
        status=HouseStatus(value),
        ttl_seconds=remaining,
        expires_at=expires_at,
    )


async def clear_status(redis: Redis, group_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Deletes a member's live status key outright, rather than leaving it
    to expire on its own TTL. Needed specifically for a departing member
    (leaving a group, or deleting their account): Open to Chat has no TTL
    at all, so without this a departed member's last status would sit in
    Redis and keep showing up in get_group_statuses for the group's
    remaining members indefinitely.
    """
    await redis.delete(_status_key(group_id, user_id))


async def get_status(redis: Redis, group_id: uuid.UUID, user_id: uuid.UUID) -> StatusRead:
    """Read a single member's live status. Resolves to Open to Chat if
    expired or never set — see `_read_result`.
    """
    key = _status_key(group_id, user_id)
    value = await redis.get(key)
    ttl = await redis.ttl(key) if value is not None else None
    return _read_result(group_id, user_id, value, ttl)


async def get_group_statuses(redis: Redis, group_id: uuid.UUID) -> list[StatusRead]:
    """Read every live status currently set for a group. Only returns
    members with a Redis key present — a member who has never set a status
    (or whose TTL lapsed and was never re-set) simply isn't in this list;
    callers render that absence as Open to Chat the same way `get_status`
    would resolve it explicitly, so the two stay consistent without this
    function needing the group's full membership list to fill gaps.
    """
    pattern = _status_key(group_id, "*")
    results: list[StatusRead] = []

    async for key in redis.scan_iter(match=pattern):
        user_id = uuid.UUID(key.split(":")[-1])
        value = await redis.get(key)
        ttl = await redis.ttl(key)
        if value is None:
            continue
        results.append(_read_result(group_id, user_id, value, ttl))

    return results
