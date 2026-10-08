import uuid

from fastapi import APIRouter, Depends
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_admin, require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.user import User
from app.schemas.wifi import WifiCredentialsRead, WifiCredentialsSet
from app.services import wifi_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}/wifi", tags=["wifi"])


@router.get("", response_model=WifiCredentialsRead)
async def get_wifi(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> WifiCredentialsRead:
    """Any member can read this — someone other than the admin who set it
    up still needs to be able to pull up the QR to show a guest.
    """
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await wifi_service.get_wifi_credentials(db, group_id=group_id)


@router.put("", response_model=WifiCredentialsRead)
async def set_wifi(
    group_id: uuid.UUID,
    payload: WifiCredentialsSet,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> WifiCredentialsRead:
    """Admin-only: sets or changes the house's Wi-Fi SSID/password used to
    render the guest QR. This endpoint never touches the device's own
    network connection — it's pure storage for what the QR will encode.
    """
    await require_admin(db, group_id=group_id, user_id=current_user.id)
    return await wifi_service.set_wifi_credentials(db, redis, group_id=group_id, payload=payload)
