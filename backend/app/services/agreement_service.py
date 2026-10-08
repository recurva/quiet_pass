"""House agreements pinboard: a per-house list of pinned, plain-text
items (house rules, trash schedule, landlord contact, free-text notes).
Admin-only write, member-readable — enforced by the router via
`require_admin`/`require_membership`, not here; this module assumes the
caller has already been authorized and just does the DB work.
"""

import uuid

from fastapi import HTTPException, status
from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.models.agreement import Agreement
from app.schemas.agreement import AgreementCreate, AgreementRead, AgreementUpdate
from app.services.status_service import publish_group_event

logger = get_logger(__name__)


async def list_agreements(db: AsyncSession, group_id: uuid.UUID) -> list[AgreementRead]:
    result = await db.execute(
        select(Agreement).where(Agreement.group_id == group_id).order_by(Agreement.created_at)
    )
    return [AgreementRead.model_validate(row, from_attributes=True) for row in result.scalars().all()]


async def create_agreement(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    user_id: uuid.UUID,
    payload: AgreementCreate,
) -> AgreementRead:
    agreement = Agreement(
        id=uuid.uuid4(),
        group_id=group_id,
        created_by=user_id,
        title=payload.title,
        content=payload.content,
    )
    db.add(agreement)
    await db.commit()
    await db.refresh(agreement)

    logger.info("agreement.created", group_id=str(group_id), agreement_id=str(agreement.id))
    await publish_group_event(
        redis, group_id, {"event": "agreement_update", "group_id": str(group_id)}
    )
    return AgreementRead.model_validate(agreement, from_attributes=True)


async def _get_or_404(db: AsyncSession, group_id: uuid.UUID, agreement_id: uuid.UUID) -> Agreement:
    result = await db.execute(
        select(Agreement).where(Agreement.id == agreement_id, Agreement.group_id == group_id)
    )
    agreement = result.scalar_one_or_none()
    if agreement is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Agreement not found.")
    return agreement


async def update_agreement(
    db: AsyncSession,
    redis: Redis,
    group_id: uuid.UUID,
    agreement_id: uuid.UUID,
    payload: AgreementUpdate,
) -> AgreementRead:
    agreement = await _get_or_404(db, group_id, agreement_id)
    agreement.title = payload.title
    agreement.content = payload.content
    await db.commit()
    await db.refresh(agreement)

    logger.info("agreement.updated", group_id=str(group_id), agreement_id=str(agreement_id))
    await publish_group_event(
        redis, group_id, {"event": "agreement_update", "group_id": str(group_id)}
    )
    return AgreementRead.model_validate(agreement, from_attributes=True)


async def delete_agreement(
    db: AsyncSession, redis: Redis, group_id: uuid.UUID, agreement_id: uuid.UUID
) -> None:
    agreement = await _get_or_404(db, group_id, agreement_id)
    await db.delete(agreement)
    await db.commit()

    logger.info("agreement.deleted", group_id=str(group_id), agreement_id=str(agreement_id))
    await publish_group_event(
        redis, group_id, {"event": "agreement_update", "group_id": str(group_id)}
    )
