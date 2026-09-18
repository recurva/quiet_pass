from fastapi import APIRouter, Depends, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_db
from app.core.logging import get_logger
from app.models.device_token import DeviceToken
from app.models.user import User
from app.schemas.device_token import DeviceTokenRead, DeviceTokenRegister

logger = get_logger(__name__)
router = APIRouter(prefix="/device-tokens", tags=["device-tokens"])


@router.post("", response_model=DeviceTokenRead, status_code=status.HTTP_201_CREATED)
async def register_device_token(
    payload: DeviceTokenRegister,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> DeviceToken:
    """Register (or re-register) an FCM device token for the caller. A
    token that already exists is reassigned to the caller and its
    last_seen_at bumped, rather than erroring — covers both "refreshed
    token for the same user" and "reused device, different account" without
    two different endpoints.
    """
    result = await db.execute(select(DeviceToken).where(DeviceToken.token == payload.token))
    existing = result.scalar_one_or_none()

    if existing is not None:
        existing.user_id = current_user.id
        existing.platform = payload.platform
        await db.commit()
        await db.refresh(existing)
        logger.info(
            "device_token.reregistered", user_id=str(current_user.id), platform=payload.platform
        )
        return existing

    device_token = DeviceToken(
        user_id=current_user.id, token=payload.token, platform=payload.platform
    )
    db.add(device_token)
    await db.commit()
    await db.refresh(device_token)
    logger.info(
        "device_token.registered", user_id=str(current_user.id), platform=payload.platform
    )
    return device_token


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device_token(
    token: str = Query(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """Explicit sign-out-time cleanup. (Stale/invalid tokens are also
    removed automatically after a failed FCM send — see push_service.)
    """
    result = await db.execute(
        select(DeviceToken).where(
            DeviceToken.token == token, DeviceToken.user_id == current_user.id
        )
    )
    device_token = result.scalar_one_or_none()
    if device_token is not None:
        await db.delete(device_token)
        await db.commit()
        logger.info("device_token.unregistered", user_id=str(current_user.id))
