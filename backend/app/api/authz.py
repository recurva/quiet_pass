"""Group-scoped authorization helpers. Kept separate from deps.py because
these depend on a group_id path parameter, not just the caller's identity.
"""

import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.membership import Membership, MembershipRole


async def get_membership(
    db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID
) -> Membership | None:
    result = await db.execute(
        select(Membership).where(Membership.group_id == group_id, Membership.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def require_membership(
    db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID
) -> Membership:
    membership = await get_membership(db, group_id, user_id)
    if membership is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Not a member of this group."
        )
    return membership


async def require_admin(db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID) -> Membership:
    membership = await require_membership(db, group_id, user_id)
    if membership.role != MembershipRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Admin role required for this action."
        )
    return membership
