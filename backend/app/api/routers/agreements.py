import uuid

from fastapi import APIRouter, Depends, status
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.authz import require_admin, require_membership
from app.api.deps import get_current_user, get_db, get_redis
from app.core.logging import get_logger
from app.models.user import User
from app.schemas.agreement import AgreementCreate, AgreementRead, AgreementUpdate
from app.services import agreement_service

logger = get_logger(__name__)
router = APIRouter(prefix="/groups/{group_id}/agreements", tags=["agreements"])


@router.get("", response_model=list[AgreementRead])
async def get_agreements(
    group_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[AgreementRead]:
    """Any member can view the board — only admins can change it."""
    await require_membership(db, group_id=group_id, user_id=current_user.id)
    return await agreement_service.list_agreements(db, group_id=group_id)


@router.post("", response_model=AgreementRead, status_code=status.HTTP_201_CREATED)
async def create_agreement(
    group_id: uuid.UUID,
    payload: AgreementCreate,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> AgreementRead:
    await require_admin(db, group_id=group_id, user_id=current_user.id)
    return await agreement_service.create_agreement(
        db, redis, group_id=group_id, user_id=current_user.id, payload=payload
    )


@router.patch("/{agreement_id}", response_model=AgreementRead)
async def update_agreement(
    group_id: uuid.UUID,
    agreement_id: uuid.UUID,
    payload: AgreementUpdate,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> AgreementRead:
    await require_admin(db, group_id=group_id, user_id=current_user.id)
    return await agreement_service.update_agreement(
        db, redis, group_id=group_id, agreement_id=agreement_id, payload=payload
    )


@router.delete("/{agreement_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_agreement(
    group_id: uuid.UUID,
    agreement_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
    current_user: User = Depends(get_current_user),
) -> None:
    await require_admin(db, group_id=group_id, user_id=current_user.id)
    await agreement_service.delete_agreement(db, redis, group_id=group_id, agreement_id=agreement_id)
