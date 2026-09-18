import uuid

from fastapi import APIRouter, Depends
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.user import User
from app.schemas.status import StatusRead, StatusSet
from app.services import status_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}/status", tags=["status"])


@router.put("", response_model=StatusRead)
async def set_my_status(
    group_id: uuid.UUID,
    payload: StatusSet,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> StatusRead:
    """Set the caller's own status. Only members of the group may do this."""
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await status_service.set_status(
        redis,
        group_id=group_id,
        user_id=current_user.id,
        status=payload.status,
        ttl_seconds=int(payload.ttl_seconds),
    )


@router.get("/{user_id}", response_model=StatusRead)
async def get_member_status(
    group_id: uuid.UUID,
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> StatusRead:
    """View any member's status, gated on the caller sharing the group."""
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await status_service.get_status(redis, group_id=group_id, user_id=user_id)


@router.get("", response_model=list[StatusRead])
async def get_group_statuses(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> list[StatusRead]:
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await status_service.get_group_statuses(redis, group_id=group_id)
