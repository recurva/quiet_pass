import asyncio
import contextlib
import json
import uuid

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import get_membership
from app.api.deps import authenticate_token, get_db, get_redis
from app.core.firebase import TokenExpiredError, TokenInvalidError
from app.core.logging import get_logger
from app.services import status_service
from app.services.connection_manager import ConnectionManager

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}", tags=["status-stream"])

manager = ConnectionManager()

# Custom WebSocket close codes (4000-4999 is the app-defined range).
CLOSE_UNAUTHENTICATED = 4401
CLOSE_FORBIDDEN = 4403


def filter_message_for_recipient(raw: str, recipient_user_id: str) -> str | None:
    """Applies the one generic, non-event-specific rewrite this relay
    makes: a publisher may set `"exclude_user_id"` on its payload
    (nudge_service.send_nudge is the only one that does today) to mean
    "deliver to every connection on this channel except this one user's
    own" — e.g. so a sender never receives their own nudge back as an
    incoming alert.

    Returns `None` if this message must not reach `recipient_user_id` at
    all (the exclude matches), otherwise the text to actually send — with
    the `exclude_user_id` key always stripped out first, so the key
    itself never reaches *any* client, including every other recipient
    for whom it didn't match. A non-JSON or non-dict payload (not
    expected from any current publisher) passes through unchanged rather
    than being dropped.

    A standalone, pure function rather than inline in the WS loop
    specifically so this one piece of actual decision logic has direct
    unit coverage without needing a WebSocket test harness at all.
    """
    try:
        decoded = json.loads(raw)
    except (TypeError, ValueError):
        return raw

    if not isinstance(decoded, dict) or "exclude_user_id" not in decoded:
        return raw

    excluded_user_id = decoded.pop("exclude_user_id")
    if excluded_user_id == recipient_user_id:
        return None
    return json.dumps(decoded)


@router.websocket("/ws")
async def group_status_stream(
    websocket: WebSocket,
    group_id: uuid.UUID,
    token: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
) -> None:
    """Live status stream for a group. Browsers can't set custom headers on
    a WebSocket handshake, so the Firebase ID token travels as a query
    param instead of an Authorization header, verified the same way as
    `get_current_user`.

    On accept: sends one `{"event": "snapshot", "statuses": [...]}` message
    with every member's current status, then relays whatever's published on
    the group's Redis channel — from any server worker, not just this one —
    as-is. Publishers (status_service, nudge_service) each stamp their own
    `"event"` field, so this route never inspects or rewrites message
    content for any *event-specific* reason; it's a dumb relay by design.

    The one deliberate, generic exception: a publisher may set
    `"exclude_user_id"` on its payload (nudge_service.send_nudge is the
    only one that does today) to mean "deliver to every connection on this
    channel except this one user's own" — e.g. so a sender never receives
    their own nudge back as an incoming alert. See `pump_redis_to_client`
    below. The key itself never reaches any client — it's stripped before
    relaying regardless of whether this connection matches it.
    """
    # Starlette only sends a real WS close *frame* (with our custom code)
    # once the handshake has been accepted; closing beforehand just rejects
    # the HTTP upgrade with a blanket 403 and the client never sees why. So
    # every auth/membership check below happens after accept().
    await websocket.accept()

    if not token:
        logger.warning("ws.missing_token", group_id=str(group_id))
        await websocket.close(code=CLOSE_UNAUTHENTICATED)
        return

    try:
        user, _ = await authenticate_token(db, token)
    except TokenExpiredError:
        logger.warning("ws.token_expired", group_id=str(group_id))
        await websocket.close(code=CLOSE_UNAUTHENTICATED)
        return
    except TokenInvalidError as exc:
        logger.warning("ws.token_invalid", group_id=str(group_id), error=str(exc))
        await websocket.close(code=CLOSE_UNAUTHENTICATED)
        return
    except Exception as exc:
        logger.error("ws.auth_failed", group_id=str(group_id), error=str(exc))
        await websocket.close(code=CLOSE_UNAUTHENTICATED)
        return

    membership = await get_membership(db, group_id=group_id, user_id=user.id)
    if membership is None:
        logger.warning("ws.not_member", group_id=str(group_id), user_id=str(user.id))
        await websocket.close(code=CLOSE_FORBIDDEN)
        return

    manager.register(group_id, websocket)
    logger.info(
        "ws.connected",
        group_id=str(group_id),
        user_id=str(user.id),
        connections=manager.connection_count(group_id),
    )

    channel = status_service.group_channel(group_id)
    pubsub = redis.pubsub()
    await pubsub.subscribe(channel)

    async def pump_redis_to_client() -> None:
        async for message in pubsub.listen():
            if message.get("type") != "message":
                continue

            outgoing = filter_message_for_recipient(message["data"], str(user.id))
            if outgoing is None:
                continue

            try:
                await websocket.send_text(outgoing)
            except Exception as exc:
                # A client disconnecting mid-message races this task's own
                # loop; without this it surfaced as an unretrieved
                # asyncio task exception (a warning buried in server
                # logs, not a diagnosable event) instead of the same
                # clean shutdown the outer receive_text() loop already
                # gets via WebSocketDisconnect. Stop pumping — the outer
                # try/finally's cleanup still runs regardless of how this
                # task ends.
                logger.warning(
                    "ws.pump_send_failed", group_id=str(group_id), error=str(exc)
                )
                return

    pump_task = asyncio.create_task(pump_redis_to_client())

    try:
        snapshot = await status_service.get_group_statuses(redis, group_id=group_id)
        await websocket.send_json(
            {"event": "snapshot", "statuses": [s.model_dump(mode="json") for s in snapshot]}
        )
        # No messages expected from the client; this just blocks until the
        # socket closes, surfacing that as WebSocketDisconnect below.
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        logger.info("ws.disconnected", group_id=str(group_id), user_id=str(user.id))
    except Exception as exc:
        logger.error(
            "ws.stream_error", group_id=str(group_id), user_id=str(user.id), error=str(exc)
        )
    finally:
        pump_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await pump_task
        with contextlib.suppress(Exception):
            await pubsub.unsubscribe(channel)
            await pubsub.aclose()
        manager.unregister(group_id, websocket)
        logger.info(
            "ws.cleaned_up",
            group_id=str(group_id),
            user_id=str(user.id),
            connections=manager.connection_count(group_id),
        )
