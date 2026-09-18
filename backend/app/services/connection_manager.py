"""Tracks this worker's live WebSocket connections per group.

This is bookkeeping only — cleanup on disconnect, connection counts for
logging — not the fan-out mechanism. With multiple server workers, a
group's connections are split across processes with no shared memory, so
delivering a status change to *every* connection can't route through this
registry. Redis pub/sub is what does that: each connection subscribes to
the group's channel directly (see app/api/routers/ws.py), so a publish from
any worker reaches every connection on every worker.
"""

import uuid
from collections import defaultdict

from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[uuid.UUID, set[WebSocket]] = defaultdict(set)

    def register(self, group_id: uuid.UUID, websocket: WebSocket) -> None:
        self._connections[group_id].add(websocket)

    def unregister(self, group_id: uuid.UUID, websocket: WebSocket) -> None:
        connections = self._connections.get(group_id)
        if connections is None:
            return
        connections.discard(websocket)
        if not connections:
            del self._connections[group_id]

    def connection_count(self, group_id: uuid.UUID) -> int:
        return len(self._connections.get(group_id, ()))
