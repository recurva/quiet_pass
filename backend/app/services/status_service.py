import json
import uuid

from redis.asyncio import Redis

from app.core.logging import get_logger
from app.schemas.status import HouseStatus, StatusRead

logger = get_logger(__name__)

_KEY_PREFIX = "status"


def _status_key(group_id: uuid.UUID, user_id: uuid.UUID) -> str:
    return f"{_KEY_PREFIX}:{group_id}:{user_id}"


def group_channel(group_id: uuid.UUID) -> str:
    """The Redis pub/sub channel a group's status changes are published on.
    Public so the WebSocket route can subscribe directly.
    """
    return f"{_KEY_PREFIX}:group:{group_id}"


async def set_status(
    redis: Redis,
    group_id: uuid.UUID,
    user_id: uuid.UUID,
    status: HouseStatus,
    ttl_seconds: int,
) -> StatusRead:
    """Write a member's live status to Redis with a TTL and publish the
    change to the group's pub/sub channel. Postgres never sees this value.
    """
    key = _status_key(group_id, user_id)
    await redis.set(key, status.value, ex=ttl_seconds)

    payload = {
        "event": "status_update",
        "group_id": str(group_id),
        "user_id": str(user_id),
        "status": status.value,
        "ttl_seconds": ttl_seconds,
    }
    await redis.publish(group_channel(group_id), json.dumps(payload))

    logger.info("status.set", group_id=str(group_id), user_id=str(user_id), status=status.value)
    return StatusRead(
        group_id=group_id, user_id=user_id, status=status, ttl_seconds=ttl_seconds
    )


async def get_status(
    redis: Redis, group_id: uuid.UUID, user_id: uuid.UUID
) -> StatusRead:
    """Read a single member's live status. Returns status=None if expired
    or never set.
    """
    key = _status_key(group_id, user_id)
    value = await redis.get(key)
    ttl = await redis.ttl(key) if value is not None else None

    return StatusRead(
        group_id=group_id,
        user_id=user_id,
        status=HouseStatus(value) if value else None,
        ttl_seconds=ttl if ttl and ttl > 0 else None,
    )


async def get_group_statuses(redis: Redis, group_id: uuid.UUID) -> list[StatusRead]:
    """Read every live status currently set for a group."""
    pattern = _status_key(group_id, "*")
    results: list[StatusRead] = []

    async for key in redis.scan_iter(match=pattern):
        user_id = uuid.UUID(key.split(":")[-1])
        value = await redis.get(key)
        ttl = await redis.ttl(key)
        if value is None:
            continue
        results.append(
            StatusRead(
                group_id=group_id,
                user_id=user_id,
                status=HouseStatus(value),
                ttl_seconds=ttl if ttl and ttl > 0 else None,
            )
        )

    return results
