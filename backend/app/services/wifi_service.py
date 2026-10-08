"""Wi-Fi credentials for a house's guest QR portal: one row per group,
admin-set, member-readable (any member needs to be able to pull up the QR
to show a guest, not just an admin). Storage and retrieval only — this
app never joins anyone to the network itself; see wifi.py's router
docstring for why.
"""

import uuid

from fastapi import HTTPException, status
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.models.wifi_credentials import WifiCredentials
from app.schemas.wifi import WifiCredentialsRead, WifiCredentialsSet
from app.services.status_service import publish_group_event

logger = get_logger(__name__)


async def get_wifi_credentials(db: AsyncSession, group_id: uuid.UUID) -> WifiCredentialsRead:
    result = await db.execute(
        select(WifiCredentials).where(WifiCredentials.group_id == group_id)
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No Wi-Fi details set for this house yet.",
        )
    return WifiCredentialsRead.model_validate(row, from_attributes=True)


async def set_wifi_credentials(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    payload: WifiCredentialsSet,
) -> WifiCredentialsRead:
    """Upserts the single row for this group — same atomic
    ON-CONFLICT-DO-UPDATE pattern as dinner_service.set_dinner_status,
    for the same reason: avoids a racy select-then-insert-or-update if
    two admins save at once.
    """
    stmt = (
        pg_insert(WifiCredentials)
        .values(id=uuid.uuid4(), group_id=group_id, ssid=payload.ssid, password=payload.password)
        .on_conflict_do_update(
            index_elements=["group_id"],
            set_={"ssid": payload.ssid, "password": payload.password},
        )
        .returning(WifiCredentials)
    )
    result = await db.execute(stmt)
    row = result.scalar_one()
    await db.commit()
    await db.refresh(row)

    logger.info("wifi.credentials_set", group_id=str(group_id))
    await publish_group_event(redis, group_id, {"event": "wifi_update", "group_id": str(group_id)})
    return WifiCredentialsRead.model_validate(row, from_attributes=True)
